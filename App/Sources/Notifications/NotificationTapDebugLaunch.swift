#if DEBUG
import Foundation
import MochaClient

enum NotificationTapDebugLaunch {
    static let agentKey = "notification-tap"
    static let delayKey = "notification-tap-delay"

    static func schedule(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) {
        guard let agentId = argumentDomain[agentKey] as? String, !agentId.isEmpty else { return }
        let delay = (argumentDomain[delayKey] as? String).flatMap(Double.init) ?? 0
        Task {
            try? await Task.sleep(for: .seconds(delay))
            AlertNotificationDelegate.open(userInfo: turnDonePayload(agentId: agentId))
        }
    }

    private static func turnDonePayload(agentId: String) -> [AnyHashable: Any] {
        [
            "aps": [
                "alert": ["title": "Claude terminou", "body": "Turno concluído."],
                "sound": "default",
                "thread-id": agentId,
                "category": AlertCategory.turnDone,
            ],
            AlertPayload.agentIdKey: agentId,
            "kind": "turnDone",
            "sentAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
    }
}
#endif
