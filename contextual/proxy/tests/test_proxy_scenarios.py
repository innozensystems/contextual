"""Comprehensive scenario tests for the Contextual thin proxy.

These tests cover edge cases, error conditions, and real-world failure modes
using mocked Mapbox responses and fakeredis.
"""

import json
import pytest
import respx
import fakeredis.aioredis
from httpx import Response
from fastapi.testclient import TestClient
from app import main
from app.main import app, settings

client = TestClient(app)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def reset_redis_between_tests():
    """Ensure each test starts with a fresh Redis state."""
    original = main._redis_client
    main._redis_client = None
    yield
    main._redis_client = original


@pytest.fixture
def mock_mapbox_token():
    """Set a dummy Mapbox token for the duration of the test."""
    original = settings.mapbox_token
    settings.mapbox_token = "pk.test-mock-token"
    yield
    settings.mapbox_token = original


@pytest.fixture
def fake_redis():
    """Provide a fakeredis instance and patch the global client."""
    r = fakeredis.aioredis.FakeRedis()
    main._redis_client = r
    yield r
    main._redis_client = None


# ---------------------------------------------------------------------------
# Input validation & edge cases
# ---------------------------------------------------------------------------

def test_geocode_query_too_long(mock_mapbox_token):
    """Geocode query exceeding max_length=200 should return 422."""
    response = client.post("/geocode", json={"query": "a" * 201})
    assert response.status_code == 422


def test_geocode_limit_out_of_range(mock_mapbox_token):
    """Geocode limit > 10 should return 422."""
    response = client.post("/geocode", json={"query": "Whole Foods", "limit": 15})
    assert response.status_code == 422


def test_geocode_limit_zero(mock_mapbox_token):
    """Geocode limit < 1 should return 422."""
    response = client.post("/geocode", json={"query": "Whole Foods", "limit": 0})
    assert response.status_code == 422


def test_geocode_proximity_only_lat(mock_mapbox_token):
    """Proximity with only lat provided should ignore proximity parameter."""
    with respx.mock:
        route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
            return_value=Response(200, json={
                "features": [{
                    "properties": {"name": "Test", "full_address": "123 St", "mapbox_id": "mbx"},
                    "geometry": {"coordinates": [-122.4, 37.7]},
                }]
            })
        )
        response = client.post("/geocode", json={
            "query": "Test",
            "proximity_lat": 37.7,
        })
        assert response.status_code == 200
        # Should not include proximity param since lng is missing
        request = route.calls[0].request
        assert "proximity" not in str(request.url)


def test_reverse_geocode_invalid_lat(mock_mapbox_token):
    """Reverse geocode with lat > 90 should return 422."""
    response = client.get("/reverse-geocode?lat=91.0&lng=-122.4194")
    assert response.status_code == 422


def test_reverse_geocode_invalid_lng(mock_mapbox_token):
    """Reverse geocode with lng > 180 should return 422."""
    response = client.get("/reverse-geocode?lat=37.7749&lng=181.0")
    assert response.status_code == 422


def test_route_too_many_waypoints(mock_mapbox_token):
    """Route with > 25 waypoints should return 422."""
    waypoints = [[37.0 + i * 0.1, -122.0 + i * 0.1] for i in range(26)]
    response = client.post("/route", json={"waypoints": waypoints})
    assert response.status_code == 422


def test_route_empty_waypoints(mock_mapbox_token):
    """Route with empty waypoints should return 400 (endpoint check fires before Pydantic max_length)."""
    response = client.post("/route", json={"waypoints": []})
    assert response.status_code == 400


def test_route_zero_waypoints(mock_mapbox_token):
    """Route with single empty waypoint should return 400."""
    response = client.post("/route", json={"waypoints": [[]]})
    # Pydantic validates tuple[float, float] so empty array fails validation
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# CORS & health endpoint
# ---------------------------------------------------------------------------

def test_cors_preflight():
    """OPTIONS request should return 200 with CORS headers."""
    response = client.options(
        "/health",
        headers={
            "Origin": "http://example.com",
            "Access-Control-Request-Method": "POST",
        },
    )
    assert response.status_code == 200
    assert "access-control-allow-origin" in response.headers


def test_health_returns_version():
    """Health endpoint should include version."""
    response = client.get("/health")
    data = response.json()
    assert "version" in data
    assert data["version"] == "1.0.0"


# ---------------------------------------------------------------------------
# Geocode response parsing edge cases
# ---------------------------------------------------------------------------

@respx.mock
def test_geocode_feature_without_geometry(mock_mapbox_token, fake_redis):
    """Mapbox feature missing geometry should use default coordinates [0, 0]."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json={
            "features": [{
                "properties": {"name": "NoCoords", "full_address": "Nowhere", "mapbox_id": "mbx"},
                # No geometry field
            }]
        })
    )
    response = client.post("/geocode", json={"query": "NoCoords"})
    assert response.status_code == 200
    result = response.json()["results"][0]
    assert result["latitude"] == 0.0
    assert result["longitude"] == 0.0


@respx.mock
def test_geocode_feature_without_properties(mock_mapbox_token, fake_redis):
    """Mapbox feature missing properties should use query as name."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json={
            "features": [{
                "geometry": {"coordinates": [-122.0, 37.0]},
                # No properties field
            }]
        })
    )
    response = client.post("/geocode", json={"query": "FallbackName"})
    assert response.status_code == 200
    result = response.json()["results"][0]
    assert result["name"] == "FallbackName"
    assert result["address"] is None
    assert result["place_id"] is None


@respx.mock
def test_geocode_no_features(mock_mapbox_token, fake_redis):
    """Mapbox response with empty features should return empty results."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json={"features": []})
    )
    response = client.post("/geocode", json={"query": "NonExistentPlace12345"})
    assert response.status_code == 200
    assert response.json()["results"] == []


@respx.mock
def test_geocode_respects_limit(mock_mapbox_token, fake_redis):
    """Should return at most `limit` results even if Mapbox returns more."""
    features = []
    for i in range(10):
        features.append({
            "properties": {"name": f"Place{i}", "full_address": f"{i} St", "mapbox_id": f"mbx-{i}"},
            "geometry": {"coordinates": [-122.0 + i * 0.1, 37.0 + i * 0.1]},
        })
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json={"features": features})
    )
    response = client.post("/geocode", json={"query": "Places", "limit": 3})
    assert response.status_code == 200
    assert len(response.json()["results"]) == 3


# ---------------------------------------------------------------------------
# Cache scenarios
# ---------------------------------------------------------------------------

@respx.mock
def test_cache_key_includes_proximity(mock_mapbox_token, fake_redis):
    """Requests with different proximity should have different cache keys."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json={
            "features": [{
                "properties": {"name": "Test", "full_address": "123 St", "mapbox_id": "mbx"},
                "geometry": {"coordinates": [-122.4, 37.7]},
            }]
        })
    )
    # Two requests with different proximity
    r1 = client.post("/geocode", json={"query": "Test", "proximity_lat": 37.7, "proximity_lng": -122.4})
    assert r1.status_code == 200
    assert r1.json()["cached"] is False

    r2 = client.post("/geocode", json={"query": "Test", "proximity_lat": 38.0, "proximity_lng": -122.0})
    assert r2.status_code == 200
    assert r2.json()["cached"] is False

    # Should have hit Mapbox twice (different cache keys)
    assert len(route.calls) == 2


@respx.mock
def test_geocode_cache_expiration(mock_mapbox_token, fake_redis):
    """Cache should expire after TTL."""
    import asyncio

    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json={
            "features": [{
                "properties": {"name": "Test", "full_address": "123 St", "mapbox_id": "mbx"},
                "geometry": {"coordinates": [-122.4, 37.7]},
            }]
        })
    )

    # First request
    r1 = client.post("/geocode", json={"query": "Test"})
    assert r1.status_code == 200
    assert r1.json()["cached"] is False

    # Second request should be cached
    r2 = client.post("/geocode", json={"query": "Test"})
    assert r2.json()["cached"] is True

    # Manually expire the cache key
    async def expire_cache():
        r = await main.get_redis()
        keys = await r.keys("ctx:geocode:*")
        for key in keys:
            await r.delete(key)

    asyncio.run(expire_cache())

    # Third request should hit Mapbox again
    r3 = client.post("/geocode", json={"query": "Test"})
    assert r3.json()["cached"] is False
    assert len(route.calls) == 2


# ---------------------------------------------------------------------------
# Route optimization edge cases
# ---------------------------------------------------------------------------

@respx.mock
def test_route_directions_no_routes(mock_mapbox_token, fake_redis):
    """Directions API returning empty routes array should handle gracefully."""
    route = respx.get(url__regex=r"https://api\.mapbox\.com/directions/v5/.*").mock(
        return_value=Response(200, json={"routes": []})
    )
    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": False,
        },
    )
    assert response.status_code == 200
    data = response.json()
    # Should use default empty dict fallback
    assert data["distance_meters"] == 0
    assert data["duration_seconds"] == 0
    assert data["legs"] == []
    assert data["waypoints_order"] == [0, 1]


@respx.mock
def test_route_optimized_empty_trips(mock_mapbox_token, fake_redis):
    """Optimized-trips API returning empty trips array should handle gracefully."""
    route = respx.get(url__regex=r"https://api\.mapbox\.com/optimized-trips/v1/.*").mock(
        return_value=Response(200, json={"trips": [], "waypoints": []})
    )
    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": True,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["distance_meters"] == 0
    assert data["duration_seconds"] == 0


@respx.mock
def test_route_optimized_no_waypoints_index(mock_mapbox_token, fake_redis):
    """Optimized-trips without waypoint_index should fallback to enumerated order."""
    route = respx.get(url__regex=r"https://api\.mapbox\.com/optimized-trips/v1/.*").mock(
        return_value=Response(200, json={
            "trips": [{
                "distance": 1000,
                "duration": 200,
                "geometry": "poly",
                "legs": [{"distance": 1000, "duration": 200, "summary": "A to B"}],
            }],
            "waypoints": [{}, {}],  # No waypoint_index field
        })
    )
    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": True,
        },
    )
    assert response.status_code == 200
    data = response.json()
    # Should fallback to enumerated order [0, 1] when waypoint_index is missing
    assert data["waypoints_order"] == [0, 1]


@respx.mock
def test_route_directions_missing_legs(mock_mapbox_token, fake_redis):
    """Directions route without legs should return empty legs list."""
    route = respx.get(url__regex=r"https://api\.mapbox\.com/directions/v5/.*").mock(
        return_value=Response(200, json={
            "routes": [{
                "distance": 500,
                "duration": 100,
                "geometry": "poly",
                # No legs field
            }]
        })
    )
    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": False,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["legs"] == []


# ---------------------------------------------------------------------------
# Network & Mapbox error scenarios
# ---------------------------------------------------------------------------

@respx.mock
def test_geocode_mapbox_500(mock_mapbox_token, fake_redis):
    """Mapbox returning 500 should return 502 with detail."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(500, text="Internal Server Error")
    )
    response = client.post("/geocode", json={"query": "Test"})
    assert response.status_code == 502
    detail = response.json()["detail"]
    assert "Mapbox error" in detail
    assert "500" in detail


@respx.mock
def test_geocode_mapbox_timeout(mock_mapbox_token, fake_redis):
    """Mapbox timeout: proxy doesn't catch httpx exceptions, they crash through as 500.

    NOTE: respx side_effect wraps the exception in SideEffectError, so the test
    client itself raises. In production, FastAPI would catch httpx.ConnectTimeout
    and return 500. The proxy should handle this gracefully (return 502).
    """
    import httpx
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        side_effect=httpx.ConnectTimeout("Connection timed out")
    )
    # In test client mode, respx re-raises the side_effect exception directly
    with pytest.raises(httpx.ConnectTimeout):
        client.post("/geocode", json={"query": "Test"})


@respx.mock
def test_reverse_geocode_mapbox_404(mock_mapbox_token, fake_redis):
    """Mapbox reverse geocode returning 404 should return 502."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/reverse").mock(
        return_value=Response(404, text="Not found")
    )
    response = client.get("/reverse-geocode?lat=37.7749&lng=-122.4194")
    assert response.status_code == 502


@respx.mock
def test_route_mapbox_429_rate_limited(mock_mapbox_token, fake_redis):
    """Mapbox rate limit (429) should return 502."""
    route = respx.get(url__regex=r"https://api\.mapbox\.com/directions/v5/.*").mock(
        return_value=Response(429, text="Rate limit exceeded")
    )
    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": False,
        },
    )
    assert response.status_code == 502
    assert "429" in response.json()["detail"]


# ---------------------------------------------------------------------------
# Redis scenarios
# ---------------------------------------------------------------------------

def test_reverse_geocode_redis_unavailable(mock_mapbox_token):
    """Reverse geocode works without Redis."""
    original = main.get_redis

    async def broken():
        raise ConnectionError("Redis down")

    main.get_redis = broken
    try:
        with respx.mock:
            respx.get("https://api.mapbox.com/search/searchbox/v1/reverse").mock(
                return_value=Response(200, json={
                    "features": [{
                        "properties": {"name": "Test", "full_address": "123 St", "mapbox_id": "mbx"},
                        "geometry": {"coordinates": [-122.4, 37.7]},
                    }]
                })
            )
            response = client.get("/reverse-geocode?lat=37.7&lng=-122.4")
            assert response.status_code == 200
            assert response.json()["cached"] is False
    finally:
        main.get_redis = original


def test_route_redis_unavailable(mock_mapbox_token):
    """Route works without Redis."""
    original = main.get_redis

    async def broken():
        raise ConnectionError("Redis down")

    main.get_redis = broken
    try:
        with respx.mock:
            # Default optimize=True hits optimized-trips endpoint
            respx.get(url__regex=r"https://api\.mapbox\.com/optimized-trips/v1/.*").mock(
                return_value=Response(200, json={
                    "trips": [{
                        "distance": 1000,
                        "duration": 200,
                        "geometry": "poly",
                        "legs": [{"distance": 1000, "duration": 200, "summary": "A to B"}],
                    }],
                    "waypoints": [
                        {"waypoint_index": 0},
                        {"waypoint_index": 1},
                    ],
                })
            )
            response = client.post(
                "/route",
                json={
                    "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
                },
            )
            assert response.status_code == 200
            assert response.json()["cached"] is False
    finally:
        main.get_redis = original


# ---------------------------------------------------------------------------
# Settings & configuration
# ---------------------------------------------------------------------------

def test_settings_default_values():
    """Verify Settings defaults are sensible."""
    from app.main import Settings
    s = Settings()
    assert s.mapbox_token == ""
    assert s.google_places_api_key == ""
    assert s.redis_url == "redis://localhost:6379/0"
    assert s.rate_limit_per_minute == 60
    assert s.max_cache_seconds == 86400


def test_cors_allows_all_origins():
    """Verify CORS middleware allows all origins (production should tighten)."""
    response = client.get("/health", headers={"Origin": "https://evil.com"})
    assert "access-control-allow-origin" in response.headers
    # Currently allows all origins — should be tightened for production
    assert response.headers["access-control-allow-origin"] == "*"


# ---------------------------------------------------------------------------
# Header handling
# ---------------------------------------------------------------------------

def test_geocode_accepts_device_id_header(mock_mapbox_token):
    """Geocode should accept x-device-id header without error."""
    with respx.mock:
        respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
            return_value=Response(200, json={"features": []})
        )
        response = client.post(
            "/geocode",
            json={"query": "Test"},
            headers={"x-device-id": "device-123"},
        )
        assert response.status_code == 200


def test_reverse_geocode_accepts_device_id_header(mock_mapbox_token):
    """Reverse geocode should accept x-device-id header."""
    with respx.mock:
        respx.get("https://api.mapbox.com/search/searchbox/v1/reverse").mock(
            return_value=Response(200, json={
                "features": [{
                    "properties": {"name": "Test", "full_address": "123 St", "mapbox_id": "mbx"},
                    "geometry": {"coordinates": [-122.4, 37.7]},
                }]
            })
        )
        response = client.get(
            "/reverse-geocode?lat=37.7&lng=-122.4",
            headers={"x-device-id": "device-456"},
        )
        assert response.status_code == 200


def test_route_accepts_device_id_header(mock_mapbox_token):
    """Route should accept x-device-id header."""
    with respx.mock:
        respx.get(url__regex=r"https://api\.mapbox\.com/optimized-trips/v1/.*").mock(
            return_value=Response(200, json={
                "trips": [{
                    "distance": 1000,
                    "duration": 200,
                    "geometry": "poly",
                    "legs": [{"distance": 1000, "duration": 200, "summary": "A to B"}],
                }],
                "waypoints": [
                    {"waypoint_index": 0},
                    {"waypoint_index": 1},
                ],
            })
        )
        response = client.post(
            "/route",
            json={"waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]]},
            headers={"x-device-id": "device-789"},
        )
        assert response.status_code == 200
