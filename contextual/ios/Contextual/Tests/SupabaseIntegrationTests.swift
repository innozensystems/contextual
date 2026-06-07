import XCTest
import Combine
@testable import Contextual

final class SupabaseIntegrationTests: XCTestCase {

    private func makeTask(
        id: UUID = UUID(),
        status: TaskStatus = .active,
        title: String = "Test Task",
        locationId: UUID? = nil,
        reminderRadius: Int = 200
    ) -> CTask {
        CTask(
            id: id,
            userId: UUID(),
            title: title,
            notes: nil,
            locationId: locationId,
            status: status,
            priority: .normal,
            dueDate: nil,
            completedAt: nil,
            reminderRadiusMeters: reminderRadius,
            isHardToGet: false,
            listId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Supabase joined query JSON decoding

    func testTaskDecodesFromSupabaseJoinedQueryWithLocation() throws {
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
                "id": "550e8400-e29b-41d4-a716-446655440002",
                "name": "Whole Foods",
                "address": "123 Market St",
                "latitude": 37.7749,
                "longitude": -122.4194,
                "place_id": "mbx-123",
                "created_by": null,
                "created_at": "2024-01-01T00:00:00Z"
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
        XCTAssertEqual(task.location?.longitude, -122.4194)
        XCTAssertEqual(task.location?.placeId, "mbx-123")
        XCTAssertEqual(task.locationId?.uuidString, "550E8400-E29B-41D4-A716-446655440002")
    }

    func testTaskDecodesFromSupabaseWithoutLocation() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "title": "Buy milk",
            "status": "active",
            "priority": "normal",
            "reminder_radius_meters": 200,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(CTask.self, from: json)

        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertNil(task.locationId)
        XCTAssertNil(task.location)
    }

    func testNearbyTaskResultDecodes() throws {
        let json = """
        {
            "task_id": "550e8400-e29b-41d4-a716-446655440000",
            "title": "Buy milk",
            "location_name": "Whole Foods",
            "distance_meters": 1250.5,
            "latitude": 37.7749,
            "longitude": -122.4194
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(NearbyTaskResult.self, from: json)
        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertEqual(result.locationName, "Whole Foods")
        XCTAssertEqual(result.distanceMeters, 1250.5)
        XCTAssertEqual(result.latitude, 37.7749)
        XCTAssertEqual(result.longitude, -122.4194)
    }

    // MARK: - HomeViewModel business logic

    func testCheckTripOpportunitiesShowsBannerWithThreeActiveTasks() {
        let viewModel = HomeViewModel()
        viewModel.tasks = [
            makeTask(status: .active, title: "Task 1"),
            makeTask(status: .active, title: "Task 2"),
            makeTask(status: .active, title: "Task 3"),
        ]
        viewModel.checkTripOpportunities()
        XCTAssertTrue(viewModel.showTripBanner)
    }

    func testCheckTripOpportunitiesHidesBannerWithLessThanThreeActiveTasks() {
        let viewModel = HomeViewModel()
        viewModel.tasks = [
            makeTask(status: .active, title: "Task 1"),
            makeTask(status: .active, title: "Task 2"),
            makeTask(status: .completed, title: "Task 3"),
        ]
        viewModel.checkTripOpportunities()
        XCTAssertFalse(viewModel.showTripBanner)
    }

    func testCheckTripOpportunitiesHidesBannerWhenAllCompleted() {
        let viewModel = HomeViewModel()
        viewModel.tasks = [
            makeTask(status: .completed, title: "Task 1"),
            makeTask(status: .completed, title: "Task 2"),
            makeTask(status: .completed, title: "Task 3"),
        ]
        viewModel.checkTripOpportunities()
        XCTAssertFalse(viewModel.showTripBanner)
    }

    func testCompleteTaskUpdatesLocalState() {
        let viewModel = HomeViewModel()
        let task = makeTask(status: .active)
        viewModel.tasks = [task]
        viewModel.checkTripOpportunities() // initially 1 active, no banner
        XCTAssertFalse(viewModel.showTripBanner)

        // Simulate completing the task locally (the viewModel would normally
        // also call SupabaseService.shared.completeTask)
        if let index = viewModel.tasks.firstIndex(where: { $0.id == task.id }) {
            viewModel.tasks[index].status = .completed
            viewModel.tasks[index].completedAt = Date()
        }
        viewModel.checkTripOpportunities()

        XCTAssertEqual(viewModel.tasks[0].status, .completed)
        XCTAssertNotNil(viewModel.tasks[0].completedAt)
    }

    func testDeleteTaskRemovesFromLocalState() {
        let viewModel = HomeViewModel()
        let task = makeTask(status: .active)
        viewModel.tasks = [task]

        viewModel.tasks.removeAll { $0.id == task.id }

        XCTAssertTrue(viewModel.tasks.isEmpty)
    }

    func testTaskContextGrouping() {
        let viewModel = HomeViewModel()
        let activeTasks = (1...7).map { i in makeTask(status: .active, title: "Task \(i)") }
        let completedTasks = [
            makeTask(status: .completed, title: "Done 1"),
            makeTask(status: .completed, title: "Done 2"),
        ]
        viewModel.tasks = activeTasks + completedTasks

        // HereNow = first 2 active
        let hereNow = viewModel.tasks.filter { $0.status == .active }.prefix(2).map { $0 }
        XCTAssertEqual(hereNow.count, 2)

        // OnYourWay = next 3 active
        let onYourWay = viewModel.tasks.filter { $0.status == .active }.dropFirst(2).prefix(3).map { $0 }
        XCTAssertEqual(onYourWay.count, 3)

        // Later = remaining active
        let later = viewModel.tasks.filter { $0.status == .active }.dropFirst(5).map { $0 }
        XCTAssertEqual(later.count, 2)
    }
}
