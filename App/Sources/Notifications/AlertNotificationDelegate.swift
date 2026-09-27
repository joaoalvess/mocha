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

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Self.open(userInfo: content.userInfo)
            return
        }
        guard let reply = PendingNotificationReply(
            actionIdentifier: response.actionIdentifier,
            userInfo: content.userInfo,
            body: content.body,
            text: (response as? UNTextInputNotificationResponse)?.userText
        ) else { return }
        await PendingNotificationResponder.send(reply)
    }

    static func open(userInfo: [AnyHashable: Any]) {
        guard let payload = AlertPayload(userInfo: userInfo) else { return }
        Task { @MainActor in
            AppNotifications.taps.deliver(payload.deepLink)
        }
    }
}
