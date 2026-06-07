import Foundation
import UserNotifications
import UIKit

/// Manages local notifications for context-aware reminders.
/// Uses a single expandable notification per location with multiple tasks.
@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var recentUndoTimers: [UUID: Timer] = [:n]

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error.localizedDescription)")
            }
        }
    }

    /// Schedule a notification for entering a task geofence.
    func scheduleContextNotification(taskId: UUID) {
        // In production, fetch the task and any co-located tasks from local DB.
        let content = UNMutableNotificationContent()
        content.title = "Near: Whole Foods"
        content.body = "Buy almond milk"
        content.sound = .default
        content.categoryIdentifier = "TASK_CONTEXT"
        content.threadIdentifier = "location-group" // groups by location

        // Add action buttons
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_ACTION",
            title: "Got it",
            options: .destructive
        )
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 1h",
            options: []
        )
        let openAction = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Open",
            options: .foreground
        )

        let category = UNNotificationCategory(
            identifier: "TASK_CONTEXT",
            actions: [completeAction, snoozeAction, openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        let request = UNNotificationRequest(
            identifier: "task-\(taskId.uuidString)",
            content: content,
            trigger: nil // immediate
        )

        center.add(request) { error in
            if let error = error {
                print("Notification error: \(error.localizedDescription)")
            }
        }
    }

    /// Handle instant completion from notification with 10-second undo.
    func handleComplete(taskId: UUID) {
        // Mark complete locally first (optimistic)
        // Start undo timer
        let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            Task {
                // Persist completion to Supabase
                try? await SupabaseService.shared.completeTask(id: taskId)
            }
        }
        recentUndoTimers[taskId] = timer

        // Post local notification for undo
        let content = UNMutableNotificationContent()
        content.title = "Task completed"
        content.body = "Tap to undo within 10 seconds"
        content.sound = nil
        content.categoryIdentifier = "UNDO_COMPLETION"

        let undoAction = UNNotificationAction(
            identifier: "UNDO_ACTION",
            title: "Undo",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "UNDO_COMPLETION",
            actions: [undoAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        let request = UNNotificationRequest(
            identifier: "undo-\(taskId.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func undoCompletion(taskId: UUID) {
        recentUndoTimers[taskId]?.invalidate()
        recentUndoTimers.removeValue(forKey: taskId)
        // Revert local status
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is foreground
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier

        if response.actionIdentifier == "COMPLETE_ACTION" {
            let taskIdString = identifier.replacingOccurrences(of: "task-", with: "")
            if let taskId = UUID(uuidString: taskIdString) {
                Task { @MainActor in
                    NotificationService.shared.handleComplete(taskId: taskId)
                }
            }
        } else if response.actionIdentifier == "SNOOZE_ACTION" {
            // Reschedule for 1 hour later
            let newContent = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
            let newTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
            let newRequest = UNNotificationRequest(identifier: identifier + "-snoozed", content: newContent, trigger: newTrigger)
            center.add(newRequest)
        } else if response.actionIdentifier == "UNDO_ACTION" {
            let taskIdString = identifier.replacingOccurrences(of: "undo-", with: "")
            if let taskId = UUID(uuidString: taskIdString) {
                Task { @MainActor in
                    NotificationService.shared.undoCompletion(taskId: taskId)
                }
            }
        } else if response.actionIdentifier == "OPEN_ACTION" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // Deep link to task detail
            let taskIdString = identifier.replacingOccurrences(of: "task-", with: "")
            // Post notification to open task detail
            NotificationCenter.default.post(name: .init("OpenTaskDetail"), object: taskIdString)
        }

        completionHandler()
    }
}
