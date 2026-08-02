import Foundation
import UserNotifications

/// Local notifications for clip reminders.
///
/// `UNUserNotificationCenter` schedules these entirely on-device — the system
/// holds the pending notification and fires it even if SupaClip isn't running.
/// Nothing leaves the machine, so this stays inside the no-network rule.
@MainActor
enum ReminderService {
    /// Ask once, the first time a reminder is actually set, rather than
    /// prompting on launch for a feature the user may never touch.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("SupaClip: notification authorization failed — \(error.localizedDescription)")
            return false
        }
    }

    static func schedule(for clip: Clip) async {
        guard let fireDate = clip.reminderAt else { return }

        // A date in the past would never fire; drop it instead of scheduling.
        guard fireDate > Date() else {
            cancel(for: clip)
            return
        }

        guard await requestAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = clip.title ?? "Clip reminder"
        content.body = String(clip.sortableText.prefix(120))
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Keying the request on the clip's own id means re-scheduling replaces
        // the pending notification rather than stacking a second one.
        let request = UNNotificationRequest(
            identifier: clip.id.uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            NSLog("SupaClip: could not schedule reminder — \(error.localizedDescription)")
        }
    }

    static func cancel(for clip: Clip) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [clip.id.uuidString])
    }
}
