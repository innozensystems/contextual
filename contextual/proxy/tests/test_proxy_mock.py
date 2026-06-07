"""Mocked tests for the Contextual thin proxy.

These tests mock Mapbox API responses (via respx) and Redis (via fakeredis)
so the suite runs fully offline and covers happy paths, caching, and errors.
"""

import fakeredis.aioredis
import pytest
import respx
from fastapi.testclient import TestClient
from httpx import Response

from app import main
from app.main import app, settings

client = TestClient(
    app, headers={"x-device-id": "test-device-12345", "x-api-key": "test-api-key"}
)


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
# Existing baseline tests (no mocks needed)
# ---------------------------------------------------------------------------


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_geocode_missing_token():
    response = client.post("/geocode", json={"query": "Whole Foods"})
    assert response.status_code == 503


def test_geocode_validation_error():
    response = client.post("/geocode", json={"query": ""})
    assert response.status_code == 422


def test_reverse_geocode_missing_token():
    response = client.get("/reverse-geocode?lat=37.7749&lng=-122.4194")
    assert response.status_code == 503


def test_route_missing_token():
    response = client.post(
        "/route",
        json={"waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]], "optimize": True},
    )
    assert response.status_code == 503


def test_route_insufficient_waypoints(mock_mapbox_token):
    response = client.post("/route", json={"waypoints": [[37.7749, -122.4194]]})
    assert response.status_code == 400


# ---------------------------------------------------------------------------
# Mocked happy-path tests
# ---------------------------------------------------------------------------


@respx.mock
def test_geocode_success(mock_mapbox_token, fake_redis):
    """Geocode returns parsed results and caches them."""
    mb_response = {
        "features": [
            {
                "properties": {
                    "name": "Whole Foods Market",
                    "full_address": "123 Market St, San Francisco, CA",
                    "mapbox_id": "mbx-123",
                },
                "geometry": {"coordinates": [-122.4194, 37.7749]},
            }
        ]
    }
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json=mb_response)
    )

    response = client.post("/geocode", json={"query": "Whole Foods"})
    assert response.status_code == 200
    data = response.json()
    assert data["cached"] is False
    assert data["source"] == "mapbox"
    assert len(data["results"]) == 1
    assert data["results"][0]["name"] == "Whole Foods Market"
    assert data["results"][0]["latitude"] == 37.7749
    assert data["results"][0]["longitude"] == -122.4194
    assert route.called


@respx.mock
def test_geocode_cache_hit(mock_mapbox_token, fake_redis):
    """Second identical geocode request returns cached result without hitting Mapbox."""
    mb_response = {
        "features": [
            {
                "properties": {
                    "name": "Whole Foods Market",
                    "full_address": "123 Market St",
                    "mapbox_id": "mbx-123",
                },
                "geometry": {"coordinates": [-122.4194, 37.7749]},
            }
        ]
    }
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(200, json=mb_response)
    )

    # First request — hits Mapbox
    r1 = client.post("/geocode", json={"query": "Whole Foods"})
    assert r1.status_code == 200
    assert r1.json()["cached"] is False
    assert route.called

    # Reset call count
    route.calls.clear()

    # Second request — should be cached
    r2 = client.post("/geocode", json={"query": "Whole Foods"})
    assert r2.status_code == 200
    assert r2.json()["cached"] is True
    assert not route.called  # Mapbox not hit again


@respx.mock
def test_reverse_geocode_success(mock_mapbox_token, fake_redis):
    mb_response = {
        "features": [
            {
                "properties": {
                    "name": "San Francisco City Hall",
                    "full_address": "1 Dr Carlton B Goodlett Pl, San Francisco, CA",
                    "mapbox_id": "mbx-456",
                },
                "geometry": {"coordinates": [-122.4194, 37.7793]},
            }
        ]
    }
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/reverse").mock(
        return_value=Response(200, json=mb_response)
    )

    response = client.get("/reverse-geocode?lat=37.7793&lng=-122.4194")
    assert response.status_code == 200
    data = response.json()
    assert data["cached"] is False
    assert data["result"]["name"] == "San Francisco City Hall"
    assert data["result"]["latitude"] == 37.7793
    assert data["result"]["longitude"] == -122.4194
    assert route.called


@respx.mock
def test_reverse_geocode_no_results(mock_mapbox_token, fake_redis):
    """Reverse geocode returns 404 when Mapbox has no features."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/reverse").mock(
        return_value=Response(200, json={"features": []})
    )

    response = client.get("/reverse-geocode?lat=0.0&lng=0.0")
    assert response.status_code == 404
    assert response.json()["detail"] == "No results found"
    assert route.called


@respx.mock
def test_route_directions_success(mock_mapbox_token, fake_redis):
    """Route with optimize=False uses Directions API and parses response."""
    mb_response = {
        "routes": [
            {
                "distance": 1523.4,
                "duration": 320.0,
                "geometry": "polyline123",
                "legs": [
                    {
                        "distance": 1523.4,
                        "duration": 320.0,
                        "summary": "Market St to Mission St",
                    }
                ],
            }
        ]
    }
    route = respx.get(url__regex=r"https://api\.mapbox\.com/directions/v5/.*").mock(
        return_value=Response(200, json=mb_response)
    )

    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": False,
            "profile": "mapbox/driving",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["distance_meters"] == 1523.4
    assert data["duration_seconds"] == 320.0
    assert data["geometry"] == "polyline123"
    assert data["waypoints_order"] == [0, 1]
    assert len(data["legs"]) == 1
    assert data["legs"][0]["summary"] == "Market St to Mission St"
    assert route.called


@respx.mock
def test_route_optimized_trip_success(mock_mapbox_token, fake_redis):
    """Route with optimize=True uses Optimized-Trips API and parses waypoints_order."""
    mb_response = {
        "trips": [
            {
                "distance": 2100.0,
                "duration": 450.0,
                "geometry": "opt-polyline",
                "legs": [
                    {"distance": 1000.0, "duration": 200.0, "summary": "A to B"},
                    {"distance": 1100.0, "duration": 250.0, "summary": "B to C"},
                ],
            }
        ],
        "waypoints": [
            {"waypoint_index": 0},
            {"waypoint_index": 2},
            {"waypoint_index": 1},
        ],
    }
    route = respx.get(url__regex=r"https://api\.mapbox\.com/optimized-trips/v1/.*").mock(
        return_value=Response(200, json=mb_response)
    )

    response = client.post(
        "/route",
        json={
            "waypoints": [
                [37.7749, -122.4194],
                [37.7849, -122.4094],
                [37.7649, -122.4294],
            ],
            "optimize": True,
            "profile": "mapbox/driving",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["distance_meters"] == 2100.0
    assert data["duration_seconds"] == 450.0
    assert data["geometry"] == "opt-polyline"
    # Optimized order: 0 -> 2 -> 1
    assert data["waypoints_order"] == [0, 2, 1]
    assert len(data["legs"]) == 2
    assert route.called


@respx.mock
def test_geocode_mapbox_error(mock_mapbox_token, fake_redis):
    """When Mapbox returns an error, proxy returns 502 with detail."""
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
        return_value=Response(429, text="Rate limited")
    )

    response = client.post("/geocode", json={"query": "Whole Foods"})
    assert response.status_code == 502
    assert "Mapbox error" in response.json()["detail"]
    assert route.called


@respx.mock
def test_route_mapbox_error(mock_mapbox_token, fake_redis):
    """When Mapbox Directions returns an error, proxy returns 502."""
    route = respx.get(url__regex=r"https://api\.mapbox\.com/directions/v5/.*").mock(
        return_value=Response(500, text="Internal Server Error")
    )

    response = client.post(
        "/route",
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": False,
        },
    )
    assert response.status_code == 502
    assert "Mapbox error" in response.json()["detail"]
    assert route.called


# ---------------------------------------------------------------------------
# Redis degradation tests
# ---------------------------------------------------------------------------


def test_geocode_redis_unavailable(mock_mapbox_token):
    """When Redis is broken, geocode still works by skipping cache."""
    # Patch get_redis to raise on every call
    original_get_redis = main.get_redis

    async def broken_redis():
        raise ConnectionError("Redis is down")

    main.get_redis = broken_redis
    try:
        with respx.mock:
            mb_response = {
                "features": [
                    {
                        "properties": {
                            "name": "Target",
                            "full_address": "456 Main St",
                            "mapbox_id": "mbx-789",
                        },
                        "geometry": {"coordinates": [-122.5, 37.8]},
                    }
                ]
            }
            respx.get("https://api.mapbox.com/search/searchbox/v1/forward").mock(
                return_value=Response(200, json=mb_response)
            )

            response = client.post("/geocode", json={"query": "Target"})
            assert response.status_code == 200
            assert response.json()["cached"] is False
    finally:
        main.get_redis = original_get_redis
