import Foundation
import MochaClient
import UserNotifications

final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Self.open(userInfo: response.notification.request.content.userInfo)
        }
        completionHandler()
    }

    static func open(userInfo: [AnyHashable: Any]) {
        guard let payload = AlertPayload(userInfo: userInfo) else { return }
        Task { @MainActor in
            AppNotifications.taps.deliver(payload.deepLink)
        }
    }
}
