import XCTest
@testable import Contextual

final class ProxyServiceTests: XCTestCase {

    // MARK: - GeocodeRequest encoding

    func testGeocodeRequestEncodesSnakeCase() throws {
        let request = ProxyService.GeocodeRequest(
            query: "Whole Foods",
            proximityLat: 37.7749,
            proximityLng: -122.4194,
            limit: 5
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["query"] as? String, "Whole Foods")
        XCTAssertEqual(json?["proximity_lat"] as? Double, 37.7749)
        XCTAssertEqual(json?["proximity_lng"] as? Double, -122.4194)
        XCTAssertEqual(json?["limit"] as? Int, 5)
    }

    func testGeocodeResponseDecodes() throws {
        let json = """
        {
            "results": [
                {
                    "name": "Whole Foods",
                    "address": "123 Market St",
                    "latitude": 37.7749,
                    "longitude": -122.4194,
                    "place_id": "mbx-123"
                }
            ],
            "source": "mapbox",
            "cached": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProxyService.GeocodeResponse.self, from: json)
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results[0].name, "Whole Foods")
        XCTAssertEqual(response.results[0].latitude, 37.7749)
        XCTAssertEqual(response.results[0].longitude, -122.4194)
        XCTAssertEqual(response.results[0].placeId, "mbx-123")
        XCTAssertFalse(response.cached)
    }

    func testGeocodeResponseHandlesMissingOptionalFields() throws {
        let json = """
        {
            "results": [
                {
                    "name": "NoAddress",
                    "latitude": 37.0,
                    "longitude": -122.0
                }
            ],
            "source": "mapbox",
            "cached": true
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProxyService.GeocodeResponse.self, from: json)
        XCTAssertEqual(response.results[0].name, "NoAddress")
        XCTAssertNil(response.results[0].address)
        XCTAssertNil(response.results[0].placeId)
        XCTAssertTrue(response.cached)
    }

    // MARK: - RouteRequest / Response

    func testRouteRequestEncodesWaypoints() throws {
        let request = ProxyService.RouteRequest(
            waypoints: [[37.7749, -122.4194], [37.7849, -122.4094]],
            optimize: true,
            profile: "mapbox/driving"
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["optimize"] as? Bool, true)
        XCTAssertEqual(json?["profile"] as? String, "mapbox/driving")
        let waypoints = json?["waypoints"] as? [[Double]]
        XCTAssertEqual(waypoints?.count, 2)
        XCTAssertEqual(waypoints?[0], [37.7749, -122.4194])
    }

    func testRouteResponseDecodesWithWaypointsOrder() throws {
        let json = """
        {
            "distance_meters": 2100.0,
            "duration_seconds": 450.0,
            "legs": [
                { "distance_meters": 1000.0, "duration_seconds": 200.0, "summary": "A to B" }
            ],
            "waypoints_order": [0, 2, 1],
            "geometry": "opt-polyline"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProxyService.RouteResponse.self, from: json)
        XCTAssertEqual(response.distanceMeters, 2100.0)
        XCTAssertEqual(response.durationSeconds, 450.0)
        XCTAssertEqual(response.waypointsOrder, [0, 2, 1])
        XCTAssertEqual(response.legs.count, 1)
        XCTAssertEqual(response.legs[0].summary, "A to B")
        XCTAssertEqual(response.geometry, "opt-polyline")
    }

    func testRouteResponseHandlesNullGeometry() throws {
        let json = """
        {
            "distance_meters": 500.0,
            "duration_seconds": 100.0,
            "legs": [],
            "waypoints_order": [0, 1]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ProxyService.RouteResponse.self, from: json)
        XCTAssertNil(response.geometry)
    }

    // MARK: - Error handling

    func testProxyErrorUserMessages() {
        XCTAssertEqual(ProxyService.ProxyError.rateLimited(nil).userMessage, "Too many requests. Please try again later.")
        XCTAssertEqual(ProxyService.ProxyError.mapboxUnavailable(nil).userMessage, "Routing service is unavailable. Please try again later.")
        XCTAssertEqual(ProxyService.ProxyError.notConfigured(nil).userMessage, "Service is not configured. Contact support.")
        XCTAssertEqual(ProxyService.ProxyError.notFound(nil).userMessage, "No results found.")
        XCTAssertEqual(ProxyService.ProxyError.badRequest(nil).userMessage, "Invalid request.")
        XCTAssertEqual(ProxyService.ProxyError.httpError(status: 500, detail: nil).userMessage, "Server error 500.")
    }

    func testProxyErrorUsesDetailWhenProvided() {
        XCTAssertEqual(
            ProxyService.ProxyError.rateLimited("Slow down").userMessage,
            "Slow down"
        )
        XCTAssertEqual(
            ProxyService.ProxyError.mapboxUnavailable("Mapbox timeout").userMessage,
            "Mapbox timeout"
        )
    }

    func testErrorBodyDecodesDetail() throws {
        let json = """
        {"detail": "Rate limit exceeded"}
        """.data(using: .utf8)!
        let body = try JSONDecoder().decode(ProxyService.ErrorBody.self, from: json)
        XCTAssertEqual(body.detail, "Rate limit exceeded")
    }
}
