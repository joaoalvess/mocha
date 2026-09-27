import MochaProtocol

struct ToolResultWatch: Sendable {
    let toolName: String
    private var latestToolUseId: String?

    init(toolName: String, items: [ChatItem] = []) {
        self.toolName = toolName
        if let latest = items.compactMap({ Self.toolCall($0, named: toolName) }).last, latest.status == .running {
            latestToolUseId = latest.toolUseId
        }
    }

    mutating func observe(_ delta: TranscriptDelta) -> Bool {
        switch delta {
        case .append(let items):
            for call in items.compactMap({ Self.toolCall($0, named: toolName) }) {
                latestToolUseId = call.toolUseId
                if call.status != .running {
                    return true
                }
            }
            return false
        case .update(let items):
            guard let latestToolUseId else { return false }
            return items.contains { item in
                guard let call = Self.toolCall(item, named: toolName) else { return false }
                return call.toolUseId == latestToolUseId && call.status != .running
            }
        case .meta:
            return false
        }
    }

    private static func toolCall(_ item: ChatItem, named name: String) -> ToolCall? {
        guard case .toolCall(let call) = item.kind, call.name == name else { return nil }
        return call
    }
}
