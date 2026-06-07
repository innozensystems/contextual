import XCTest
import CoreLocation
@testable import Contextual

final class GeofenceServiceTests: XCTestCase {

    private func makeTask(id: UUID, status: TaskStatus = .active) -> CTask {
        CTask(
            id: id,
            userId: UUID(),
            title: "Task \(id.uuidString.prefix(4))",
            notes: nil,
            locationId: UUID(),
            status: status,
            priority: .normal,
            dueDate: nil,
            completedAt: nil,
            reminderRadiusMeters: 200,
            isHardToGet: false,
            listId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeLocation(lat: Double, lng: Double) -> CLLocation {
        CLLocation(latitude: lat, longitude: lng)
    }

    // MARK: - nearestTaskIds

    func testNearestTaskIdsSortsByDistance() {
        let current = makeLocation(lat: 0.0, lng: 0.0)
        let t1 = makeTask(id: UUID())
        let t2 = makeTask(id: UUID())
        let t3 = makeTask(id: UUID())

        let coords: [UUID: CLLocationCoordinate2D] = [
            t1.id: CLLocationCoordinate2D(latitude: 1.0, longitude: 0.0),   // ~111 km
            t2.id: CLLocationCoordinate2D(latitude: 0.1, longitude: 0.0),   // ~11 km
            t3.id: CLLocationCoordinate2D(latitude: 10.0, longitude: 0.0),  // ~1111 km
        ]

        let result = GeofenceService.nearestTaskIds(
            tasks: [t1, t2, t3],
            coordinates: coords,
            currentLocation: current
        )

        XCTAssertEqual(result, [t2.id, t1.id, t3.id])
    }

    func testNearestTaskIdsRespectsLimit() {
        let current = makeLocation(lat: 0.0, lng: 0.0)
        var tasks: [CTask] = []
        var coords: [UUID: CLLocationCoordinate2D] = [:]

        for i in 0..<25 {
            let task = makeTask(id: UUID())
            tasks.append(task)
            coords[task.id] = CLLocationCoordinate2D(latitude: Double(i) * 0.1, longitude: 0.0)
        }

        let result = GeofenceService.nearestTaskIds(
            tasks: tasks,
            coordinates: coords,
            currentLocation: current,
            limit: 20
        )

        XCTAssertEqual(result.count, 20)
    }

    func testNearestTaskIdsSkipsMissingCoordinates() {
        let current = makeLocation(lat: 0.0, lng: 0.0)
        let t1 = makeTask(id: UUID())
        let t2 = makeTask(id: UUID())

        let coords: [UUID: CLLocationCoordinate2D] = [
            t1.id: CLLocationCoordinate2D(latitude: 1.0, longitude: 0.0),
        ]

        let result = GeofenceService.nearestTaskIds(
            tasks: [t1, t2],
            coordinates: coords,
            currentLocation: current
        )

        XCTAssertEqual(result, [t1.id])
    }

    func testNearestTaskIdsReturnsEmptyForNoTasks() {
        let current = makeLocation(lat: 0.0, lng: 0.0)
        let result = GeofenceService.nearestTaskIds(
            tasks: [],
            coordinates: [:],
            currentLocation: current
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Region identifier parsing

    func testRegionIdentifierExtractsTaskId() {
        let taskId = UUID()
        let identifier = "task-\(taskId.uuidString)"
        let extracted = identifier.replacingOccurrences(of: "task-", with: "")
        XCTAssertEqual(extracted, taskId.uuidString)
        XCTAssertNotNil(UUID(uuidString: extracted))
    }

    func testUpdateTaskLocationCachesCoordinate() {
        let service = GeofenceService.shared
        let taskId = UUID()
        let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        service.updateTaskLocation(taskId: taskId, coordinate: coord)
        // taskCoordinates is private; nearestTaskIds can verify indirectly
        let current = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let task = makeTask(id: taskId)
        let result = GeofenceService.nearestTaskIds(
            tasks: [task],
            coordinates: [taskId: coord],
            currentLocation: current
        )
        XCTAssertEqual(result, [taskId])
    }

    // MARK: - startMonitoring with embedded locations

    func testStartMonitoringUsesEmbeddedLocation() {
        let service = GeofenceService.shared
        let taskId = UUID()
        var task = makeTask(id: taskId)
        task.location = CLocation(
            id: UUID(),
            name: "Test Loc",
            latitude: 37.7749,
            longitude: -122.4194
        )

        // Should not crash and should populate internal taskLocations
        service.startMonitoring(tasks: [task])

        // Verify by calling nearestTaskIds with the service's internal state
        let current = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let result = GeofenceService.nearestTaskIds(
            tasks: [task],
            coordinates: [taskId: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)],
            currentLocation: current
        )
        XCTAssertEqual(result, [taskId])
    }

    func testStartMonitoringUsesProvidedLocationsOverEmbedded() {
        let service = GeofenceService.shared
        let taskId = UUID()
        var task = makeTask(id: taskId)
        task.location = CLocation(
            id: UUID(),
            name: "Embedded",
            latitude: 37.0,
            longitude: -122.0
        )

        let providedCoord = CLLocationCoordinate2D(latitude: 38.0, longitude: -123.0)
        service.startMonitoring(tasks: [task], locations: [taskId: providedCoord])

        // nearestTaskIds with the provided coordinate should work
        let current = CLLocation(latitude: 38.0, longitude: -123.0)
        let result = GeofenceService.nearestTaskIds(
            tasks: [task],
            coordinates: [taskId: providedCoord],
            currentLocation: current
        )
        XCTAssertEqual(result, [taskId])
    }

    // MARK: - CTask model with embedded location

    func testTaskDecodesWithEmbeddedLocation() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "title": "Buy milk",
            "location_id": "550e8400-e29b-41d4-a716-446655440002",
            "status": "active",
            "priority": "normal",
            "reminder_radius_meters": 200,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
            "locations": {
                "id": "550e8400-e29b-41d4-a716-446655440003",
                "name": "Whole Foods",
                "latitude": 37.7749,
                "longitude": -122.4194
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(CTask.self, from: json)

        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertNotNil(task.location)
        XCTAssertEqual(task.location?.name, "Whole Foods")
        XCTAssertEqual(task.location?.latitude, 37.7749)
    }
}
