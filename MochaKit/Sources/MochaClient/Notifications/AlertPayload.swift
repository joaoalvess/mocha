import Foundation
import MochaProtocol

public enum AlertCategory {
    public static let turnDone = "TURN_DONE"
    public static let needsInput = "NEEDS_INPUT"
    public static let all = [turnDone, needsInput]
}

public struct AlertPayload: Sendable, Equatable {
    public var agentId: AgentID

    public init(agentId: AgentID) {
        self.agentId = agentId
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let agentId = userInfo[Self.agentIdKey] as? String, !agentId.isEmpty else { return nil }
        self.agentId = agentId
    }

    public var deepLink: DeepLink {
        .agent(agentId)
    }

    public static let agentIdKey = "agentId"
}
