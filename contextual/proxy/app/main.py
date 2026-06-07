"""
Contextual Thin Proxy
FastAPI app that proxies Mapbox APIs,
caches results in Redis, and protects API keys.
"""

import hashlib
import json
import logging
import re
import time
from typing import Optional

import httpx
import redis.asyncio as redis
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from redis.exceptions import ResponseError
from starlette.responses import JSONResponse

from app import metrics


class Settings(BaseSettings):
    mapbox_token: str = Field(default="", alias="MAPBOX_TOKEN")
    rate_limit_per_minute: int = Field(default=60, alias="RATE_LIMIT_PER_MINUTE")
    max_cache_seconds: int = Field(default=86400, alias="MAX_CACHE_SECONDS")  # 24h
    cors_origins: str = Field(default="*", alias="CORS_ORIGINS")
    require_redis_tls: bool = Field(default=False, alias="REQUIRE_REDIS_TLS")
    redis_url: str = Field(default="redis://localhost:6379/0", alias="REDIS_URL")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        populate_by_name=True,
    )

    @field_validator("redis_url")
    @classmethod
    def _redis_url_must_use_tls_when_required(cls, v: str, info) -> str:
        values = info.data
        if values.get("require_redis_tls") and not v.startswith("rediss://"):
            raise ValueError(
                "REQUIRE_REDIS_TLS is enabled but REDIS_URL does not use rediss://. "
                "Configure your Redis provider to use TLS (e.g., rediss://host:6379/0)."
            )
        return v


settings = Settings()

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_log_handler = logging.StreamHandler()
if settings.cors_origins != "*":  # production-ish
    _log_handler.setFormatter(logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s"))
else:
    _log_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"))

logger = logging.getLogger("contextual.proxy")
logger.setLevel(logging.INFO)
logger.addHandler(_log_handler)
logger.propagate = False

app = FastAPI(title="Contextual Proxy", version="1.0.0")

# CORS: configurable via CORS_ORIGINS env var (comma-separated, or * for dev)
# Credentials are disabled when wildcard is used to prevent credentialed XSS.
_raw_origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
if "*" in _raw_origins or settings.cors_origins == "*":
    _cors_origins = ["*"]
    _allow_credentials = False
else:
    _cors_origins = _raw_origins
    _allow_credentials = True

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# Metrics middleware: count requests by method + endpoint + status
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    route = request.url.path
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        metrics.observe_request(request.method, route, status)


# Security headers
@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response


# Request body size limit (64KB)
class MaxBodySizeMiddleware:
    def __init__(self, app, max_size: int = 65536):
        self.app = app
        self.max_size = max_size

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":  # pragma: no cover
            await self.app(scope, receive, send)
            return
        headers = dict(scope.get("headers", []))
        content_length = headers.get(b"content-length")
        if content_length:
            try:
                if int(content_length) > self.max_size:
                    response = JSONResponse(
                        {"detail": "Request body too large"},
                        status_code=413,
                    )
                    await response(scope, receive, send)
                    return
            except ValueError:
                pass
        await self.app(scope, receive, send)


app.add_middleware(MaxBodySizeMiddleware)

_DEVICE_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{16,128}$")

# Atomic Lua script for sliding-window rate limiting.
# Returns 1 if the request is allowed, 0 if the limit is exceeded.
_RATE_LIMIT_LUA = """
local key = KEYS[1]
local window_start = tonumber(ARGV[1])
local now = tonumber(ARGV[2])
local max_requests = tonumber(ARGV[3])
local expire = tonumber(ARGV[4])

redis.call("zremrangebyscore", key, 0, window_start)
local count = redis.call("zcard", key)
if count >= max_requests then
    return 0
end
redis.call("zadd", key, now, now)
redis.call("expire", key, expire)
return 1
"""


async def _check_rate_limit(client_id: str) -> bool:
    """Return True if client is within rate limit, False if exceeded.
    Uses an atomic Redis Lua script for a shared sliding window across all
    instances. Falls back to a non-atomic pipeline when the Redis provider
    does not support EVAL (e.g., some serverless/test backends).
    Falls open (allows request) if Redis is unavailable.
    """
    now = time.monotonic()
    window = 60.0  # seconds
    max_requests = settings.rate_limit_per_minute
    key = f"ratelimit:{client_id}"

    try:
        r = await get_redis()
        # Attempt atomic Lua script first (production Redis)
        try:
            result = await r.eval(
                _RATE_LIMIT_LUA,
                1,
                key,
                now - window,
                now,
                max_requests,
                int(window),
            )
            return bool(result)
        except ResponseError as exc:
            if "unknown command 'eval'" in str(exc).lower():
                # Fallback for Redis backends that don't support Lua (e.g. fakeredis)
                pipe = r.pipeline()
                pipe.zremrangebyscore(key, 0, now - window)
                pipe.zcard(key)
                _, count = await pipe.execute()
                if count >= max_requests:
                    return False
                await r.zadd(key, {str(now): now})
                await r.expire(key, int(window))
                return True
            raise
    except Exception:
        # Redis unavailable — fail open to avoid total outage
        return True


async def rate_limit_dependency(request: Request):
    """Reject requests that exceed per-minute rate limit."""
    device_id = request.headers.get("x-device-id")
    if not device_id or not _DEVICE_ID_RE.match(device_id):
        raise HTTPException(status_code=400, detail="Missing or invalid x-device-id header.")
    if not await _check_rate_limit(device_id):
        metrics.observe_rate_limit(request.url.path)
        raise HTTPException(status_code=429, detail="Rate limit exceeded. Try again later.")


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


def _safe_detail(text: str) -> str:
    """Redact sensitive tokens from upstream error text before forwarding."""
    redacted = re.sub(r"(access_token|token|key|password|secret)=[^\s&]*", r"\1=<redacted>", text, flags=re.IGNORECASE)
    return redacted[:200]


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
    waypoints: list[tuple[float, float]] = Field(..., max_length=25, description="List of (lat, lng) waypoints")
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
    cached: bool = False


# ========================
# Endpoints
# ========================


@app.post("/geocode", response_model=GeocodeResponse)
async def geocode(
    req: GeocodeRequest,
    x_device_id: Optional[str] = Header(default=None),
    _rate_limit=Depends(rate_limit_dependency),
):
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

    # Try cache
    try:
        r = await get_redis()
        cached = await r.get(cache_key)
        if cached:
            data = json.loads(cached)
            metrics.observe_cache_hit("/geocode")
            return GeocodeResponse(results=[GeocodeResult(**r) for r in data], cached=True)
    except Exception:
        metrics.observe_redis_error("get")
        pass  # Redis unavailable; fall through to Mapbox

    # Forward to Mapbox
    url = "https://api.mapbox.com/search/searchbox/v1/forward"
    try:
        with metrics.mapbox_timer("/geocode"):
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(url, params=params)
    except httpx.TimeoutException as exc:
        metrics.observe_mapbox_error("/geocode", 504)
        raise HTTPException(status_code=502, detail=f"Mapbox timeout: {exc}")

    if resp.status_code != 200:
        metrics.observe_mapbox_error("/geocode", resp.status_code)
        raise HTTPException(
            status_code=502,
            detail=f"Mapbox error: {resp.status_code} {_safe_detail(resp.text)}",
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

    metrics.observe_cache_miss("/geocode")

    # Cache raw result
    try:
        r = await get_redis()
        await r.setex(
            cache_key,
            settings.max_cache_seconds,
            json.dumps([r.model_dump() for r in results]),
        )
    except Exception:
        metrics.observe_redis_error("setex")
        pass  # Redis unavailable; skip caching

    return GeocodeResponse(results=results, cached=False)


@app.get("/reverse-geocode")
async def reverse_geocode(
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    x_device_id: Optional[str] = Header(default=None),
    _rate_limit=Depends(rate_limit_dependency),
):
    """Reverse geocode a lat/lng coordinate via Mapbox."""
    if not settings.mapbox_token:
        raise HTTPException(status_code=503, detail="Mapbox token not configured")

    params = {"access_token": settings.mapbox_token, "limit": 1}
    cache_key = _cache_key("reverse", {"lat": lat, "lng": lng})

    # Try cache
    try:
        r = await get_redis()
        cached = await r.get(cache_key)
        if cached:
            data = json.loads(cached)
            metrics.observe_cache_hit("/reverse-geocode")
            return {"result": data, "cached": True}
    except Exception:
        metrics.observe_redis_error("get")
        pass  # Redis unavailable; fall through to Mapbox

    url = "https://api.mapbox.com/search/searchbox/v1/reverse"
    try:
        with metrics.mapbox_timer("/reverse-geocode"):
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(
                    url,
                    params={
                        **params,
                        "latitude": lat,
                        "longitude": lng,
                    },
                )
    except httpx.TimeoutException as exc:
        metrics.observe_mapbox_error("/reverse-geocode", 504)
        raise HTTPException(status_code=502, detail=f"Mapbox timeout: {exc}")

    if resp.status_code != 200:
        metrics.observe_mapbox_error("/reverse-geocode", resp.status_code)
        raise HTTPException(status_code=502, detail=f"Mapbox error: {resp.status_code} {_safe_detail(resp.text)}")

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

    metrics.observe_cache_miss("/reverse-geocode")

    try:
        r = await get_redis()
        await r.setex(cache_key, settings.max_cache_seconds, json.dumps(result))
    except Exception:
        metrics.observe_redis_error("setex")
        pass  # Redis unavailable; skip caching

    return {"result": result, "cached": False}


@app.post("/route", response_model=RouteResponse)
async def route(
    req: RouteRequest,
    x_device_id: Optional[str] = Header(default=None),
    _rate_limit=Depends(rate_limit_dependency),
):
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
        # Mapbox optimize=true uses the optimized-trip API, not directions
        url = "https://api.mapbox.com/optimized-trips/v1/" + req.profile + "/" + coords_str
    else:
        params["waypoints"] = "0;" + ";".join(str(i) for i in range(len(req.waypoints)))
        url = "https://api.mapbox.com/directions/v5/" + req.profile + "/" + coords_str

    cache_key = _cache_key(
        "route",
        {"coords": coords_str, "optimize": req.optimize, "profile": req.profile},
    )

    # Try cache
    try:
        r = await get_redis()
        cached = await r.get(cache_key)
        if cached:
            data = json.loads(cached)
            data["cached"] = True
            metrics.observe_cache_hit("/route")
            return RouteResponse(**data)
    except Exception:
        metrics.observe_redis_error("get")
        pass  # Redis unavailable; fall through to Mapbox

    try:
        with metrics.mapbox_timer("/route"):
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(url, params=params)
    except httpx.TimeoutException as exc:
        metrics.observe_mapbox_error("/route", 504)
        raise HTTPException(status_code=502, detail=f"Mapbox timeout: {exc}")

    if resp.status_code != 200:
        metrics.observe_mapbox_error("/route", resp.status_code)
        raise HTTPException(
            status_code=502,
            detail=f"Mapbox error: {resp.status_code} {_safe_detail(resp.text)}",
        )

    mb_data = resp.json()

    # Parse trip data (optimized-trips returns trips[], directions returns routes[])
    if req.optimize and mb_data.get("trips"):
        trip = mb_data["trips"][0]
        legs_data = trip.get("legs", [])
        waypoints_order = [wp.get("waypoint_index", i) for i, wp in enumerate(mb_data.get("waypoints", []))]
    elif mb_data.get("routes"):
        route_obj = mb_data["routes"][0]
        trip = route_obj
        legs_data = route_obj.get("legs", [])
        waypoints_order = list(range(len(req.waypoints)))
    else:
        trip = {}
        legs_data = []
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
        cached=False,
    )

    metrics.observe_cache_miss("/route")

    try:
        r = await get_redis()
        await r.setex(cache_key, settings.max_cache_seconds, json.dumps(response.model_dump()))
    except Exception:
        metrics.observe_redis_error("setex")
        pass  # Redis unavailable; skip caching

    return response


@app.get("/health")
async def health():
    """Health check enriched with Redis connectivity status."""
    redis_status = "unknown"
    try:
        r = await get_redis()
        await r.ping()
        redis_status = "connected"
    except Exception:
        redis_status = "unavailable"
    return {"status": "ok", "redis": redis_status}


@app.get("/metrics")
async def prometheus_metrics():
    """Prometheus-compatible metrics endpoint."""
    body, content_type = metrics.render_latest()
    return Response(content=body, media_type=content_type)


if __name__ == "__main__":  # pragma: no cover
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
