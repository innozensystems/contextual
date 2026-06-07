"""Fill remaining coverage gaps for reverse-geocode and route cache hits."""

import json
import pytest
import respx
import fakeredis.aioredis
from httpx import Response
from fastapi.testclient import TestClient
from app import main
from app.main import app, settings

client = TestClient(app)


@pytest.fixture(autouse=True)
def reset_redis_between_tests():
    original = main._redis_client
    main._redis_client = None
    yield
    main._redis_client = original


@pytest.fixture
def mock_mapbox_token():
    original = settings.mapbox_token
    settings.mapbox_token = "pk.test-mock-token"
    yield
    settings.mapbox_token = original


@pytest.fixture
def fake_redis():
    r = fakeredis.aioredis.FakeRedis()
    main._redis_client = r
    yield r
    main._redis_client = None


@respx.mock
def test_reverse_geocode_cache_hit(mock_mapbox_token, fake_redis):
    """Second identical reverse-geocode request returns cached result."""
    mb = {
        "features": [{
            "properties": {"name": "SF City Hall", "full_address": "1 Dr Carlton B Goodlett Pl", "mapbox_id": "mbx-456"},
            "geometry": {"coordinates": [-122.4194, 37.7793]},
        }]
    }
    route = respx.get("https://api.mapbox.com/search/searchbox/v1/reverse").mock(
        return_value=Response(200, json=mb)
    )

    r1 = client.get("/reverse-geocode?lat=37.7793&lng=-122.4194")
    assert r1.status_code == 200
    assert r1.json()["cached"] is False
    assert route.called

    route.calls.clear()

    r2 = client.get("/reverse-geocode?lat=37.7793&lng=-122.4194")
    assert r2.status_code == 200
    assert r2.json()["cached"] is True
    assert not route.called


@respx.mock
def test_route_directions_cache_hit(mock_mapbox_token, fake_redis):
    """Second identical route request returns cached result."""
    mb = {
        "routes": [{
            "distance": 1523.4,
            "duration": 320.0,
            "geometry": "polyline123",
            "legs": [{"distance": 1523.4, "duration": 320.0, "summary": "Market to Mission"}],
        }]
    }
    route = respx.get(url__regex=r"https://api\.mapbox\.com/directions/v5/.*").mock(
        return_value=Response(200, json=mb)
    )

    payload = {
        "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
        "optimize": False,
        "profile": "mapbox/driving",
    }

    r1 = client.post("/route", json=payload)
    assert r1.status_code == 200
    assert r1.json()["cached"] is False
    assert route.called

    route.calls.clear()

    r2 = client.post("/route", json=payload)
    assert r2.status_code == 200
    data = r2.json()
    assert data["cached"] is True
    assert data["distance_meters"] == 1523.4
    assert not route.called


@respx.mock
def test_route_optimized_cache_hit(mock_mapbox_token, fake_redis):
    """Second identical optimized route request returns cached result."""
    mb = {
        "trips": [{
            "distance": 2100.0,
            "duration": 450.0,
            "geometry": "opt-polyline",
            "legs": [
                {"distance": 1000.0, "duration": 200.0, "summary": "A to B"},
                {"distance": 1100.0, "duration": 250.0, "summary": "B to C"},
            ],
        }],
        "waypoints": [
            {"waypoint_index": 0},
            {"waypoint_index": 2},
            {"waypoint_index": 1},
        ],
    }
    route = respx.get(url__regex=r"https://api\.mapbox\.com/optimized-trips/v1/.*").mock(
        return_value=Response(200, json=mb)
    )

    payload = {
        "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094], [37.7649, -122.4294]],
        "optimize": True,
        "profile": "mapbox/driving",
    }

    r1 = client.post("/route", json=payload)
    assert r1.status_code == 200
    assert r1.json()["cached"] is False
    assert route.called

    route.calls.clear()

    r2 = client.post("/route", json=payload)
    assert r2.status_code == 200
    data = r2.json()
    assert data["cached"] is True
    assert data["waypoints_order"] == [0, 2, 1]
    assert not route.called
