import Foundation
import CoreLocation

/// Thin proxy client for Mapbox geocoding and routing.
/// API keys are protected server-side; mobile never sees them.
actor ProxyService {
    static let shared = ProxyService()

    private let baseURL: URL
    private let session: URLSession

    private init() {
        let proxyURL = Bundle.main.object(forInfoDictionaryKey: "PROXY_BASE_URL") as? String ?? "http://localhost:8000"
        guard let url = URL(string: proxyURL) else {
            fatalError("Invalid PROXY_BASE_URL in Info.plist: \(proxyURL)")
        }
        #if !DEBUG
        guard url.scheme == "https" else {
            fatalError("PROXY_BASE_URL must use HTTPS in release builds: \(proxyURL)")
        }
        #endif
        self.baseURL = url

        // Use pinned session in release builds when certificate pins are configured.
        let pins = Bundle.main.object(forInfoDictionaryKey: "PROXY_CERTIFICATE_PINS") as? String ?? ""
        if !pins.isEmpty {
            self.session = URLSession(configuration: .default, delegate: CertificatePinning.shared, delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: .default)
        }
    }

    // MARK: - Geocode

    struct GeocodeRequest: Codable {
        let query: String
        let proximityLat: Double?
        let proximityLng: Double?
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case query
            case proximityLat = "proximity_lat"
            case proximityLng = "proximity_lng"
            case limit
        }
    }

    struct GeocodeResult: Codable {
        let name: String
        let address: String?
        let latitude: Double
        let longitude: Double
        let placeId: String?

        enum CodingKeys: String, CodingKey {
            case name
            case address
            case latitude
            case longitude
            case placeId = "place_id"
        }
    }

    struct GeocodeResponse: Codable {
        let results: [GeocodeResult]
        let source: String
        let cached: Bool
    }

    // MARK: - Response validation

    private struct ErrorBody: Codable {
        let detail: String?
    }

    private func checkResponse(_ response: URLResponse, data: Data, accepted: ClosedRange<Int> = 200...299) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.invalidResponse
        }
        guard accepted.contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            switch http.statusCode {
            case 429:
                throw ProxyError.rateLimited(body?.detail)
            case 502:
                throw ProxyError.mapboxUnavailable(body?.detail)
            case 503:
                throw ProxyError.notConfigured(body?.detail)
            case 404:
                throw ProxyError.notFound(body?.detail)
            case 400, 422:
                throw ProxyError.badRequest(body?.detail)
            default:
                throw ProxyError.httpError(status: http.statusCode, detail: body?.detail)
            }
        }
    }

    // MARK: - Geocode

    func geocode(query: String, proximity: CLLocationCoordinate2D? = nil, limit: Int = 5) async throws -> [GeocodeResult] {
        let request = GeocodeRequest(
            query: query,
            proximityLat: proximity?.latitude,
            proximityLng: proximity?.longitude,
            limit: limit
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("geocode"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try checkResponse(response, data: data)

        let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
        return decoded.results
    }

    // MARK: - Reverse Geocode

    func reverseGeocode(lat: Double, lng: Double) async throws -> GeocodeResult {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("reverse-geocode"), resolvingAgainstBaseURL: true) else {
            throw ProxyError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng))
        ]
        guard let url = components.url else {
            throw ProxyError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        try checkResponse(response, data: data)

        struct ReverseResponse: Codable {
            let result: GeocodeResult
            let cached: Bool
        }

        let decoded = try JSONDecoder().decode(ReverseResponse.self, from: data)
        return decoded.result
    }

    // MARK: - Route

    struct RouteRequest: Codable {
        let waypoints: [[Double]] // [[lat, lng], ...]
        let optimize: Bool
        let profile: String
    }

    struct RouteLeg: Codable {
        let distanceMeters: Double
        let durationSeconds: Double
        let summary: String
    }

    struct RouteResponse: Codable {
        let distanceMeters: Double
        let durationSeconds: Double
        let legs: [RouteLeg]
        let waypointsOrder: [Int]
        let geometry: String?

        enum CodingKeys: String, CodingKey {
            case distanceMeters = "distance_meters"
            case durationSeconds = "duration_seconds"
            case legs
            case waypointsOrder = "waypoints_order"
            case geometry
        }
    }

    func route(waypoints: [CLLocationCoordinate2D], optimize: Bool = true) async throws -> RouteResponse {
        let request = RouteRequest(
            waypoints: waypoints.map { [$0.latitude, $0.longitude] },
            optimize: optimize,
            profile: "mapbox/driving"
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("route"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try checkResponse(response, data: data)

        return try JSONDecoder().decode(RouteResponse.self, from: data)
    }

    enum ProxyError: Error, Equatable {
        case invalidResponse
        case rateLimited(String?)
        case mapboxUnavailable(String?)
        case notConfigured(String?)
        case notFound(String?)
        case badRequest(String?)
        case httpError(status: Int, detail: String?)
        case certificatePinningFailed

        var userMessage: String {
            switch self {
            case .invalidResponse:
                return "Invalid server response."
            case .rateLimited(let detail):
                return detail ?? "Too many requests. Please try again later."
            case .mapboxUnavailable(let detail):
                return detail ?? "Routing service is unavailable. Please try again later."
            case .notConfigured(let detail):
                return detail ?? "Service is not configured. Contact support."
            case .notFound(let detail):
                return detail ?? "No results found."
            case .badRequest(let detail):
                return detail ?? "Invalid request."
            case .httpError(let status, let detail):
                return detail ?? "Server error \(status)."
            case .certificatePinningFailed:
                return "Secure connection could not be established. Contact support."
            }
        }
    }
}
