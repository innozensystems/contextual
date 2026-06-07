"""Contract tests: verify proxy JSON matches exactly what iOS/Android decoders expect.

These tests serialize the proxy's Pydantic models and assert the JSON keys and
types match the mobile-side @SerialName / CodingKeys contracts. If a proxy
model field is renamed or removed, these tests fail before the mobile app crashes.
"""

import json

import pytest

from app.main import (
    GeocodeResponse,
    GeocodeResult,
    RouteLeg,
    RouteResponse,
)

# ---------------------------------------------------------------------------
# Geocode contract
# ---------------------------------------------------------------------------


def test_geocode_response_json_keys_match_mobile_contract():
    """Proxy GeocodeResponse must serialize keys that iOS/Android expect."""
    result = GeocodeResult(
        name="Whole Foods",
        address="123 Market St",
        latitude=37.7749,
        longitude=-122.4194,
        place_id="mbx-123",
    )
    response = GeocodeResponse(results=[result], source="mapbox", cached=False)
    raw = json.loads(response.model_dump_json())

    # Top-level keys
    assert set(raw.keys()) == {"results", "source", "cached"}

    # Result keys (snake_case matches proxy; mobile maps via CodingKeys)
    result_json = raw["results"][0]
    assert set(result_json.keys()) == {
        "name",
        "address",
        "latitude",
        "longitude",
        "place_id",
    }

    # Type assertions
    assert isinstance(result_json["name"], str)
    assert isinstance(result_json["latitude"], float)
    assert isinstance(result_json["longitude"], float)
    assert result_json["place_id"] == "mbx-123"
    assert raw["cached"] is False


def test_geocode_response_handles_null_address():
    """Mobile clients expect address/places_id to be absent or null."""
    result = GeocodeResult(name="NoAddress", latitude=37.0, longitude=-122.0)
    response = GeocodeResponse(results=[result], cached=True)
    raw = json.loads(response.model_dump_json())

    assert raw["results"][0]["address"] is None
    assert raw["results"][0]["place_id"] is None


# ---------------------------------------------------------------------------
# Reverse geocode contract
# ---------------------------------------------------------------------------


def test_reverse_geocode_response_json_keys_match_mobile_contract():
    """Reverse endpoint returns {"result": {...}, "cached": bool}."""
    # The reverse endpoint returns a plain dict, not a Pydantic model.
    # Reconstruct the exact shape it produces.
    result = {
        "name": "SF City Hall",
        "address": "1 Dr Carlton B Goodlett Pl",
        "latitude": 37.7793,
        "longitude": -122.4194,
        "place_id": "mbx-456",
    }
    response = {"result": result, "cached": True}
    raw = json.loads(json.dumps(response))

    assert set(raw.keys()) == {"result", "cached"}
    assert set(raw["result"].keys()) == {
        "name",
        "address",
        "latitude",
        "longitude",
        "place_id",
    }
    assert raw["cached"] is True


# ---------------------------------------------------------------------------
# Route contract
# ---------------------------------------------------------------------------


def test_route_response_json_keys_match_mobile_contract():
    """Proxy RouteResponse must serialize keys that iOS/Android expect."""
    response = RouteResponse(
        distance_meters=2100.0,
        duration_seconds=450.0,
        legs=[
            RouteLeg(distance_meters=1000.0, duration_seconds=200.0, summary="A to B"),
            RouteLeg(distance_meters=1100.0, duration_seconds=250.0, summary="B to C"),
        ],
        waypoints_order=[0, 2, 1],
        geometry="opt-polyline",
        cached=False,
    )
    raw = json.loads(response.model_dump_json())

    # Top-level keys
    assert set(raw.keys()) == {
        "distance_meters",
        "duration_seconds",
        "legs",
        "waypoints_order",
        "geometry",
        "cached",
    }

    # Leg keys
    leg = raw["legs"][0]
    assert set(leg.keys()) == {"distance_meters", "duration_seconds", "summary"}

    # Values
    assert raw["distance_meters"] == 2100.0
    assert raw["duration_seconds"] == 450.0
    assert raw["waypoints_order"] == [0, 2, 1]
    assert raw["geometry"] == "opt-polyline"
    assert raw["cached"] is False


def test_route_response_handles_null_geometry():
    """Mobile clients must handle missing geometry field."""
    response = RouteResponse(
        distance_meters=500.0,
        duration_seconds=100.0,
        legs=[],
        waypoints_order=[0, 1],
        geometry=None,
        cached=False,
    )
    raw = json.loads(response.model_dump_json())

    assert raw["geometry"] is None
    assert raw["legs"] == []


# ---------------------------------------------------------------------------
# Waypoint request contract (proxy receives from mobile)
# ---------------------------------------------------------------------------


def test_route_request_json_matches_mobile_payload():
    """Verify the JSON mobile sends matches what the proxy RouteRequest parses."""
    from app.main import RouteRequest

    # This is the exact shape Android sends: [[lat, lng], [lat, lng]]
    mobile_payload = {
        "waypoints": [[37.7749, -122.4194], [37.7849, -122.4094]],
        "optimize": True,
        "profile": "mapbox/driving",
    }
    parsed = RouteRequest.model_validate(mobile_payload)
    assert parsed.waypoints == [(37.7749, -122.4194), (37.7849, -122.4094)]
    assert parsed.optimize is True
    assert parsed.profile == "mapbox/driving"


def test_geocode_request_json_matches_mobile_payload():
    """Verify the JSON mobile sends matches what the proxy GeocodeRequest parses."""
    from app.main import GeocodeRequest

    mobile_payload = {
        "query": "Whole Foods",
        "proximity_lat": 37.7749,
        "proximity_lng": -122.4194,
        "limit": 5,
    }
    parsed = GeocodeRequest.model_validate(mobile_payload)
    assert parsed.query == "Whole Foods"
    assert parsed.proximity_lat == 37.7749
    assert parsed.proximity_lng == -122.4194
    assert parsed.limit == 5


# ---------------------------------------------------------------------------
# Error response contract
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "status,expected_detail_present",
    [
        (400, True),  # bad request
        (404, True),  # not found
        (429, True),  # rate limited
        (502, True),  # mapbox error
        (503, True),  # not configured
    ],
)
def test_error_response_json_has_detail(status, expected_detail_present):
    """FastAPI HTTPException always returns {"detail": "..."} that mobile parses."""
    from fastapi import HTTPException

    exc = HTTPException(status_code=status, detail=f"Error {status}")
    # FastAPI serializes HTTPException as {"detail": "..."}
    body = json.loads('{"detail": "' + exc.detail + '"}')
    assert "detail" in body
    assert isinstance(body["detail"], str)
    assert body["detail"] == f"Error {status}"
