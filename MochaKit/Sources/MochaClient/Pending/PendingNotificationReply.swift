import Foundation
import MochaProtocol

public enum PendingNotificationCategory {
    public static let permission = "PERMISSION"
    public static let question = "QUESTION"
    public static let plan = "PLAN"
    public static let all = [permission, question, plan]
}

public enum PendingNotificationAction {
    public static let allow = "ALLOW"
    public static let deny = "DENY"
    public static let answer = "ANSWER"
}

public struct PendingNotificationReply: Sendable, Equatable {
    public var requestId: RequestID
    public var agentId: AgentID?
    public var response: PendingResponse

    public init(requestId: RequestID, agentId: AgentID?, response: PendingResponse) {
        self.requestId = requestId
        self.agentId = agentId
        self.response = response
    }

    public init?(actionIdentifier: String, userInfo: [AnyHashable: Any], body: String, text: String?) {
        guard let requestId = userInfo[Self.requestIdKey] as? String, !requestId.isEmpty else { return nil }
        let agentId = (userInfo[AlertPayload.agentIdKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch actionIdentifier {
        case PendingNotificationAction.allow:
            self.init(requestId: requestId, agentId: agentId, response: .allow)
        case PendingNotificationAction.deny:
            self.init(requestId: requestId, agentId: agentId, response: .deny(reason: nil))
        case PendingNotificationAction.answer:
            let answer = PendingAnswerMatching.trimmed(text ?? "")
            guard !answer.isEmpty, !body.isEmpty else { return nil }
            self.init(requestId: requestId, agentId: agentId, response: .answers([body: [answer]]))
        default:
            return nil
        }
    }

    public static let requestIdKey = "requestId"
}
