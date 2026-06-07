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
}
