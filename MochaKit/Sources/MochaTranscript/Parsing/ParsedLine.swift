import Foundation
import MochaProtocol

struct ToolResultOutcome: Sendable, Equatable {
    let toolUseId: String
    let isError: Bool
    let preview: String?
    let answersPreview: String?
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

    var producesItem: Bool {
        switch self {
        case .item, .slashCommand: true
        default: false
        }
    }
}

struct ParsedLine: Sendable, Equatable {
    var version: String?
    var effects: [LineEffect]

    static let empty = ParsedLine(version: nil, effects: [])
    static let dropped = ParsedLine(version: nil, effects: [.dropped])

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
