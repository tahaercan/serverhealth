import Foundation
import UserNotifications

/// Foreground delegate that tells iOS to surface a banner + sound even when
/// the app is open. Without this, iOS suppresses the visual notification
/// while the app is in foreground (default behavior since iOS 10).
final class NotificationForegroundDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationForegroundDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}

/// Local notification wrapper.
///
/// `requestAuthorization()` is idempotent — if the user already decided,
/// it returns the current status without prompting again. Use it on first
/// launch and again from Settings ("Re-request" link routes to Settings.app
/// if previously denied).
@MainActor
enum NotificationService {

    private static let center = UNUserNotificationCenter.current()

    /// Install the foreground presentation delegate. Call once on app launch.
    static func install() {
        center.delegate = NotificationForegroundDelegate.shared
    }

    /// Ask the user for permission. If already determined, returns the current
    /// status without showing a prompt again.
    @discardableResult
    static func requestAuthorization() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }
        default:
            return settings.authorizationStatus
        }
    }

    /// Current permission status (read-only, no prompt).
    static func currentStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Send a local notification immediately. Silently no-op if permission denied.
    /// - subtitle: shown as a secondary line under the title (used for the
    ///   monitoring CheckType so the user knows which check fired).
    static func send(title: String, subtitle: String? = nil, body: String, badge: Int? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = body
        content.sound = .default
        if let badge = badge {
            content.badge = NSNumber(value: badge)
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        center.add(request) { error in
            if let error = error {
                print("NotificationService: failed to add notification — \(error)")
            }
        }
    }
}
