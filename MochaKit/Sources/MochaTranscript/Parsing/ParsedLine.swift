import Foundation
import MochaProtocol

struct ToolUseResultSummary: Sendable, Equatable {
    var status: String?
    var agentId: String?
    var totalToolUseCount: Int?
    var totalDurationMs: Int?
    var runId: String?
    var taskId: String?
    var workflowName: String?

    static let asyncLaunched = "async_launched"

    var isAsyncLaunch: Bool {
        status == Self.asyncLaunched
    }
}

struct ToolResultOutcome: Sendable, Equatable {
    let toolUseId: String
    let isError: Bool
    let preview: String?
    let answersPreview: String?
    var toolUseResult: ToolUseResultSummary?
}

enum LineEffect: Sendable, Equatable {
    case dropped
    case unknown(String)
    case title(String)
    case permissionMode(String)
    case modelAndBranch(model: String?, branch: String?)
    case item(ChatItem)
    case slashCommand(ChatItem, promptId: String?)
    case commandOutput(String)
    case toolResult(ToolResultOutcome)
    case taskNotification(TaskNotification)
    case contextTokens(Int)
    case turnStarted
    case turnEnded

    var producesItem: Bool {
        switch self {
        case .item, .slashCommand: true
        default: false
        }
    }

    var isUserPrompt: Bool {
        guard case .item(let item) = self, case .userPrompt = item.kind else { return false }
        return true
    }
}

struct ParsedLine: Sendable, Equatable {
    var version: String?
    var timestamp: String?
    var effects: [LineEffect]
    var crossesForkBoundary: Bool

    init(version: String? = nil, timestamp: String? = nil, effects: [LineEffect], crossesForkBoundary: Bool = false) {
        self.version = version
        self.timestamp = timestamp
        self.effects = effects
        self.crossesForkBoundary = crossesForkBoundary
    }

    static let empty = ParsedLine(effects: [])
    static let dropped = ParsedLine(effects: [.dropped])

    var date: Date? {
        timestamp.flatMap(ProtocolDate.date(from:))
    }

    var itemCount: Int {
        effects.reduce(0) { $0 + ($1.producesItem ? 1 : 0) }
    }

    var unknownNames: [String] {
        effects.compactMap {
            if case .unknown(let name) = $0 { return name }
            return nil
        }
    }
}
