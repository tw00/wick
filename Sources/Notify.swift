import AppKit
import UserNotifications

/// A notification when the timer ends, for when you've walked away from the
/// screen — the border and the chime are no use from another room.
enum Notify {
    private static var asked = false

    /// Asked for when a timer starts rather than at launch, so the permission
    /// prompt lands when it's obvious what it's for.
    static func requestIfNeeded() {
        guard Prefs.shared.notifyOnFinish, !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Wick: notification permission: %@", error.localizedDescription) }
        }
    }

    static func timerFinished(after duration: TimeInterval) {
        guard Prefs.shared.notifyOnFinish else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "\(Format.human(duration)) done."
        let request = UNNotificationRequest(identifier: "wick.finished",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Wick: notification failed: %@", error.localizedDescription) }
        }
    }
}
