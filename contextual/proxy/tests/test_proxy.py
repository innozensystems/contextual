"""Tests for the Contextual thin proxy."""

from fastapi.testclient import TestClient

from app.main import app, settings

client = TestClient(
    app, headers={"x-device-id": "test-device-12345", "x-api-key": "test-api-key"}
)


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
        json={
            "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
            "optimize": True,
        },
    )
    assert response.status_code == 503


def test_api_key_rejected_when_configured():
    """When PROXY_API_KEY is set, missing/invalid x-api-key returns 401."""
    original_key = settings.proxy_api_key
    settings.proxy_api_key = "secret-key"
    try:
        # Missing key
        client_no_key = TestClient(app, headers={"x-device-id": "test-device-12345"})
        response = client_no_key.post("/geocode", json={"query": "Whole Foods"})
        assert response.status_code == 401

        # Invalid key
        client_bad_key = TestClient(
            app, headers={"x-device-id": "test-device-12345", "x-api-key": "wrong-key"}
        )
        response = client_bad_key.post("/geocode", json={"query": "Whole Foods"})
        assert response.status_code == 401
    finally:
        settings.proxy_api_key = original_key


def test_route_insufficient_waypoints():
    original_token = settings.mapbox_token
    settings.mapbox_token = "dummy-token"
    response = client.post("/route", json={"waypoints": [[37.7749, -122.4194]]})
    settings.mapbox_token = original_token
    assert response.status_code == 400
