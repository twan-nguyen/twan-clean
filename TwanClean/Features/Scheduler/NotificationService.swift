import UserNotifications

/// Tells the user what a scheduled run did.
enum NotificationService {
    /// Asks once; macOS remembers the answer.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    static let post: @Sendable (ScheduledRunSummary, ScheduleSettings.Action) async -> Void = { summary, action in
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Scheduled scan finished")
        if action == .clean, summary.cleanedBytes > 0 {
            content.body = String(localized: "Freed \(summary.cleanedBytes.formattedBytes) of \(summary.foundBytes.formattedBytes) found.")
        } else {
            content.body = String(localized: "Found \(summary.foundBytes.formattedBytes) you can clean. Open Twan Clean to review it.")
        }
        if summary.lockedCount > 0 {
            content.body += " " + String(localized: "Some folders were skipped: Full Disk Access is off.")
        }
        let request = UNNotificationRequest(identifier: "scheduled-run", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
