"""Tests for the Contextual thin proxy."""

import pytest
from fastapi.testclient import TestClient
from app.main import app, Settings

client = TestClient(app)


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


def test_route_insufficient_waypoints():
    response = client.post("/route", json={"waypoints": [[37.7749, -122.4194]]})
    assert response.status_code == 400
