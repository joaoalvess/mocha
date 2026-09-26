import Foundation
import MochaProtocol

public struct ToolGroup: Sendable, Hashable, Identifiable {
    public let itemIds: [String]
    public let toolName: String
    public let calls: [ToolCall]

    public var id: String { itemIds.first ?? toolName }
    public var displayName: String { ToolPresentation.displayName(for: toolName) }
    public var icon: ToolIcon { ToolPresentation.icon(for: toolName) }
    public var count: Int { calls.count }
    public var summary: String { calls.first?.summary ?? "" }

    public var status: ToolStatus {
        if calls.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if calls.contains(where: { $0.status == .running }) {
            return .running
        }
        return .succeeded
    }
}

public struct ThinkingRun: Sendable, Hashable, Identifiable {
    public let itemIds: [String]
    public let texts: [String]

    public var id: String { itemIds.first ?? "" }
    public var text: String? { texts.isEmpty ? nil : texts.joined(separator: "\n\n") }
}

public enum ChatEntry: Sendable, Hashable, Identifiable {
    case item(ChatItem)
    case tools(ToolGroup)
    case thinking(ThinkingRun)

    public var id: String {
        switch self {
        case .item(let item): item.id
        case .tools(let group): group.id
        case .thinking(let run): run.id
        }
    }

    public var itemIds: [String] {
        switch self {
        case .item(let item): [item.id]
        case .tools(let group): group.itemIds
        case .thinking(let run): run.itemIds
        }
    }
}

public struct ToolInput: Sendable, Hashable {
    public let text: String
    public let isShellCommand: Bool
}

public enum ToolGrouping {
    public static func entries(from items: [ChatItem]) -> [ChatEntry] {
        var entries: [ChatEntry] = []
        entries.reserveCapacity(items.count)
        for item in items {
            switch item.kind {
            case .unsupported:
                continue
            case .toolCall(let call):
                if case .tools(let group) = entries.last, group.toolName == call.name {
                    entries[entries.count - 1] = .tools(
                        ToolGroup(itemIds: group.itemIds + [item.id], toolName: group.toolName, calls: group.calls + [call])
                    )
                } else {
                    entries.append(.tools(ToolGroup(itemIds: [item.id], toolName: call.name, calls: [call])))
                }
            case .thinking(let text):
                let texts = text.map(trimmed).flatMap { $0.isEmpty ? nil : [$0] } ?? []
                if case .thinking(let run) = entries.last {
                    entries[entries.count - 1] = .thinking(ThinkingRun(itemIds: run.itemIds + [item.id], texts: run.texts + texts))
                } else {
                    entries.append(.thinking(ThinkingRun(itemIds: [item.id], texts: texts)))
                }
            default:
                entries.append(.item(item))
            }
        }
        return entries
    }

    public static func input(for call: ToolCall) -> ToolInput {
        let fields = stringFields(of: call.inputJSON)
        let isShell = ToolPresentation.icon(for: call.name) == .shell
        if isShell, let command = fields["command"], !command.isEmpty {
            return ToolInput(text: command, isShellCommand: true)
        }
        for key in inputKeys {
            if let value = fields[key], !trimmed(value).isEmpty {
                return ToolInput(text: value, isShellCommand: false)
            }
        }
        return ToolInput(text: call.summary.isEmpty ? call.inputJSON : call.summary, isShellCommand: false)
    }

    private static let inputKeys = ["file_path", "notebook_path", "pattern", "url", "query", "description", "command", "path", "prompt"]

    private static func stringFields(of json: String) -> [String: String] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object.compactMapValues { $0 as? String }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
