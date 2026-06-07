import Foundation
import CoreLocation
import Combine

/// Manages the iOS 20-region geofence limit by dynamically registering
/// the nearest 20 task locations and swapping as the user moves.
@MainActor
final class GeofenceService: NSObject, ObservableObject {
    static let shared = GeofenceService()

    private let locationManager = CLLocationManager()
    private let maxGeofences = 20

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Currently monitored task IDs and their region identifiers.
    private var monitoredTaskIds: Set<UUID> = []

    /// All active tasks with locations (synced from Supabase).
    private var allTasks: [CTask] = []
    private var taskLocations: [UUID: CLLocationCoordinate2D] = [:]

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100 // update every 100m
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func startMonitoring(tasks: [CTask]) {
        allTasks = tasks.filter { $0.status == .active && $0.locationId != nil }
        rebuildTaskLocations()
        refreshGeofences()
    }

    private func rebuildTaskLocations() {
        taskLocations.removeAll()
        // In production, fetch actual location coordinates from Supabase or local cache.
        // Here we store the lat/lng as part of the task model for simplicity.
        for task in allTasks {
            // Placeholder: lat/lng would come from CLocation object.
            // Using stored property on task for demo; in production fetch from DB.
        }
    }

    /// Recompute the nearest 20 geofences based on current location.
    func refreshGeofences() {
        guard let current = currentLocation else { return }

        // Sort tasks by distance to current location
        let sorted = allTasks
            .compactMap { task -> (task: CTask, distance: CLLocationDistance)? in
                guard let coord = taskCoordinates(for: task) else { return nil }
                let dist = current.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                return (task, dist)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(maxGeofences)

        let nearestIds = Set(sorted.map { $0.task.id })

        // Remove regions no longer in top 20
        for id in monitoredTaskIds.subtracting(nearestIds) {
            let identifier = "task-\(id.uuidString)"
            for region in locationManager.monitoredRegions where region.identifier == identifier {
                locationManager.stopMonitoring(for: region)
            }
        }

        // Add new regions
        for (task, _) in sorted {
            let identifier = "task-\(task.id.uuidString)"
            if !monitoredTaskIds.contains(task.id) {
                guard let coord = taskCoordinates(for: task) else { continue }
                let region = CLCircularRegion(
                    center: coord,
                    radius: CLLocationDistance(task.reminderRadiusMeters),
                    identifier: identifier
                )
                region.notifyOnEntry = true
                region.notifyOnExit = false
                locationManager.startMonitoring(for: region)
            }
        }

        monitoredTaskIds = nearestIds
    }

    private func taskCoordinates(for task: CTask) -> CLLocationCoordinate2D? {
        // In production, fetch from local cache or Supabase.
        // Placeholder implementation using a stored dictionary.
        taskLocations[task.id]
    }

    func updateTaskLocation(taskId: UUID, coordinate: CLLocationCoordinate2D) {
        taskLocations[taskId] = coordinate
    }
}

extension GeofenceService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.refreshGeofences()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region is CLCircularRegion else { return }
        let taskIdString = region.identifier.replacingOccurrences(of: "task-", with: "")
        guard let taskId = UUID(uuidString: taskIdString) else { return }

        Task { @MainActor in
            NotificationService.shared.scheduleContextNotification(taskId: taskId)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Geofence monitoring failed: \(error.localizedDescription)")
    }
}
