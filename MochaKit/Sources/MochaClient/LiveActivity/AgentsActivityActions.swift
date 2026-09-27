import Foundation
import MochaProtocol

public enum AgentsActivityChoice: Sendable, Hashable {
    case allow
    case deny
    case answer(question: String, label: String)

    public var response: PendingResponse {
        switch self {
        case .allow: .allow
        case .deny: .deny(reason: nil)
        case .answer(let question, let label): .answers([question: [label]])
        }
    }
}

public struct AgentsActivityAction: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        case deny
        case allow
        case option
    }

    public var requestId: String
    public var agentId: String
    public var role: Role
    public var title: String
    public var choice: AgentsActivityChoice

    public init(requestId: String, agentId: String, role: Role, title: String, choice: AgentsActivityChoice) {
        self.requestId = requestId
        self.agentId = agentId
        self.role = role
        self.title = title
        self.choice = choice
    }
}

public enum AgentsActivityActions {
    public static let optionLimit = 4

    public static func actions(for pending: AgentsActivityContent.Pending, agentId: String) -> [AgentsActivityAction] {
        switch pending.kind {
        case .permission:
            return [
                AgentsActivityAction(requestId: pending.requestId, agentId: agentId, role: .deny, title: PendingText.deny, choice: .deny),
                AgentsActivityAction(
                    requestId: pending.requestId,
                    agentId: agentId,
                    role: .allow,
                    title: pending.toolName == PendingText.planToolName ? PendingText.approve : PendingText.allow,
                    choice: .allow
                ),
            ]
        case .question:
            guard !pending.text.isEmpty, (1...optionLimit).contains(pending.options.count) else { return [] }
            return pending.options.map {
                AgentsActivityAction(
                    requestId: pending.requestId,
                    agentId: agentId,
                    role: .option,
                    title: $0,
                    choice: .answer(question: pending.text, label: $0)
                )
            }
        }
    }
}

public enum AgentsActivityReply {
    public static func clearsPending(after result: PendingRespondResult) -> Bool {
        switch result {
        case .accepted, .gone:
            true
        case .refused, .unauthorized, .notPaired, .unreachable, .unexpectedStatus:
            false
        }
    }
}
