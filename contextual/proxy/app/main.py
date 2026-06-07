"""
Contextual Thin Proxy
FastAPI app that proxies Mapbox/Google Places APIs,
caches results in Redis, and protects API keys.
"""

import os
import hashlib
import json
from typing import Optional

import httpx
import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    mapbox_token: str = Field(default="", alias="MAPBOX_TOKEN")
    google_places_api_key: str = Field(default="", alias="GOOGLE_PLACES_API_KEY")
    redis_url: str = Field(default="redis://localhost:6379/0", alias="REDIS_URL")
    rate_limit_per_minute: int = Field(default=60, alias="RATE_LIMIT_PER_MINUTE")
    max_cache_seconds: int = Field(default=86400, alias="MAX_CACHE_SECONDS")  # 24h

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
app = FastAPI(title="Contextual Proxy", version="1.0.0")

# CORS: allow requests from mobile app origins (adjust for production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten in production
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Redis client (initialized on first use)
_redis_client: Optional[redis.Redis] = None


async def get_redis() -> redis.Redis:
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.from_url(settings.redis_url, decode_responses=True)
    return _redis_client


def _cache_key(prefix: str, params: dict) -> str:
    """Deterministic cache key from sorted params."""
    payload = json.dumps(params, sort_keys=True, separators=(",", ":"))
    return f"ctx:{prefix}:{hashlib.sha256(payload.encode()).hexdigest()[:16]}"


# ========================
# Request / Response Models
# ========================

class GeocodeRequest(BaseModel):
    query: str = Field(..., min_length=1, max_length=200, description="Address or place name")
    proximity_lat: Optional[float] = None
    proximity_lng: Optional[float] = None
    limit: int = Field(default=5, ge=1, le=10)


class GeocodeResult(BaseModel):
    name: str
    address: Optional[str] = None
    latitude: float
    longitude: float
    place_id: Optional[str] = None


class GeocodeResponse(BaseModel):
    results: list[GeocodeResult]
    source: str = "mapbox"
    cached: bool = False


class RouteRequest(BaseModel):
    waypoints: list[tuple[float, float]] = Field(
        ..., min_length=2, max_length=25, description="List of (lat, lng) waypoints"
    )
    optimize: bool = Field(default=True, description="Optimize waypoint order (TSP)")
    profile: str = Field(default="mapbox/driving", description="Routing profile")


class RouteLeg(BaseModel):
    distance_meters: float
    duration_seconds: float
    summary: str


class RouteResponse(BaseModel):
    distance_meters: float
    duration_seconds: float
    legs: list[RouteLeg]
    waypoints_order: list[int]
    geometry: Optional[str] = None  # encoded polyline


# ========================
# Endpoints
# ========================

@app.post("/geocode", response_model=GeocodeResponse)
async def geocode(req: GeocodeRequest, x_device_id: Optional[str] = Header(default=None)):
    """
    Geocode an address or place name via Mapbox.
    Results are cached for 24 hours.
    """
    if not settings.mapbox_token:
        raise HTTPException(status_code=503, detail="Mapbox token not configured")

    params = {
        "q": req.query,
        "limit": req.limit,
        "access_token": settings.mapbox_token,
    }
    if req.proximity_lat is not None and req.proximity_lng is not None:
        params["proximity"] = f"{req.proximity_lng},{req.proximity_lat}"

    cache_key = _cache_key("geocode", params)
    r = await get_redis()

    # Try cache
    cached = await r.get(cache_key)
    if cached:
        data = json.loads(cached)
        return GeocodeResponse(results=[GeocodeResult(**r) for r in data], cached=True)

    # Forward to Mapbox
    url = "https://api.mapbox.com/search/searchbox/v1/forward"
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url, params=params)

    if resp.status_code != 200:
        raise HTTPException(
            status_code=502, detail=f"Mapbox error: {resp.status_code} {resp.text[:200]}"
        )

    mb_data = resp.json()
    results: list[GeocodeResult] = []
    for feature in mb_data.get("features", [])[: req.limit]:
        props = feature.get("properties", {})
        coords = feature.get("geometry", {}).get("coordinates", [0, 0])
        results.append(
            GeocodeResult(
                name=props.get("name", req.query),
                address=props.get("full_address"),
                latitude=coords[1],
                longitude=coords[0],
                place_id=props.get("mapbox_id"),
            )
        )

    # Cache raw result
    await r.setex(cache_key, settings.max_cache_seconds, json.dumps([r.model_dump() for r in results]))

    return GeocodeResponse(results=results, cached=False)


@app.get("/reverse-geocode")
async def reverse_geocode(
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    x_device_id: Optional[str] = Header(default=None),
):
    """Reverse geocode a lat/lng coordinate via Mapbox."""
    if not settings.mapbox_token:
        raise HTTPException(status_code=503, detail="Mapbox token not configured")

    params = {"access_token": settings.mapbox_token, "limit": 1}
    cache_key = _cache_key("reverse", {"lat": lat, "lng": lng})
    r = await get_redis()

    cached = await r.get(cache_key)
    if cached:
        data = json.loads(cached)
        return {"result": data, "cached": True}

    url = f"https://api.mapbox.com/search/searchbox/v1/reverse"
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            url,
            params={
                **params,
                "latitude": lat,
                "longitude": lng,
            },
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Mapbox error: {resp.status_code}")

    mb_data = resp.json()
    features = mb_data.get("features", [])
    if not features:
        raise HTTPException(status_code=404, detail="No results found")

    feature = features[0]
    props = feature.get("properties", {})
    coords = feature.get("geometry", {}).get("coordinates", [0, 0])
    result = {
        "name": props.get("name", "Unknown"),
        "address": props.get("full_address"),
        "latitude": coords[1],
        "longitude": coords[0],
        "place_id": props.get("mapbox_id"),
    }

    await r.setex(cache_key, settings.max_cache_seconds, json.dumps(result))
    return {"result": result, "cached": False}


@app.post("/route", response_model=RouteResponse)
async def route(req: RouteRequest, x_device_id: Optional[str] = Header(default=None)):
    """
    Get optimized driving route through waypoints.
    Uses Mapbox Directions API with optional TSP optimization.
    """
    if not settings.mapbox_token:
        raise HTTPException(status_code=503, detail="Mapbox token not configured")

    if len(req.waypoints) < 2:
        raise HTTPException(status_code=400, detail="At least 2 waypoints required")

    # Build coordinates string: lng,lat;lng,lat;...
    coords_str = ";".join(f"{lng},{lat}" for lat, lng in req.waypoints)
    params = {
        "access_token": settings.mapbox_token,
        "geometries": "polyline",
        "overview": "full",
    }
    if req.optimize:
        params["waypoints"] = "0;" + ";".join(str(i) for i in range(len(req.waypoints)))
        # Mapbox optimize=true uses the optimized-trip API, not directions
        url = "https://api.mapbox.com/optimized-trips/v1/" + req.profile + "/" + coords_str
    else:
        url = "https://api.mapbox.com/directions/v5/" + req.profile + "/" + coords_str

    cache_key = _cache_key("route", {"coords": coords_str, "optimize": req.optimize, "profile": req.profile})
    r = await get_redis()

    cached = await r.get(cache_key)
    if cached:
        data = json.loads(cached)
        return RouteResponse(**data)

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(url, params=params)

    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Mapbox error: {resp.status_code} {resp.text[:200]}")

    mb_data = resp.json()

    # Parse trip data (optimized-trips returns trips[], directions returns routes[])
    if req.optimize and "trips" in mb_data:
        trip = mb_data["trips"][0]
        legs_data = trip.get("legs", [])
        waypoints_order = [wp["waypoint_index"] for wp in mb_data.get("waypoints", [])]
    else:
        route_obj = mb_data.get("routes", [{}])[0]
        trip = route_obj
        legs_data = route_obj.get("legs", [])
        waypoints_order = list(range(len(req.waypoints)))

    legs = [
        RouteLeg(
            distance_meters=leg.get("distance", 0),
            duration_seconds=leg.get("duration", 0),
            summary=leg.get("summary", ""),
        )
        for leg in legs_data
    ]

    response = RouteResponse(
        distance_meters=trip.get("distance", 0),
        duration_seconds=trip.get("duration", 0),
        legs=legs,
        waypoints_order=waypoints_order,
        geometry=trip.get("geometry"),
    )

    await r.setex(cache_key, settings.max_cache_seconds, json.dumps(response.model_dump()))
    return response


@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
