#if DEBUG
import Foundation
import UserNotifications

struct PushProbeReceivedNotification: Sendable {
    let identifier: String
    let title: String
    let body: String
    let kind: String?
    let sentAtMilliseconds: Double?
    let receivedAt: Date
    let interruptionLevel: String
}

final class PushProbeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let onPresent: @Sendable @MainActor (PushProbeReceivedNotification) -> Void

    init(onPresent: @escaping @Sendable @MainActor (PushProbeReceivedNotification) -> Void) {
        self.onPresent = onPresent
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let received = PushProbeReceivedNotification(
            identifier: notification.request.identifier,
            title: content.title,
            body: content.body,
            kind: content.userInfo["kind"] as? String,
            sentAtMilliseconds: (content.userInfo["sentAt"] as? NSNumber)?.doubleValue,
            receivedAt: Date(),
            interruptionLevel: Self.describe(content.interruptionLevel)
        )
        let onPresent = onPresent
        Task { @MainActor in onPresent(received) }
        completionHandler([.banner, .list, .sound])
    }

    private static func describe(_ level: UNNotificationInterruptionLevel) -> String {
        switch level {
        case .passive: "passive"
        case .active: "active"
        case .timeSensitive: "time-sensitive"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
#endif
