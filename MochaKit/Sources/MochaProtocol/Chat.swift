import Foundation

public enum ToolStatus: String, Codable, Sendable, Hashable {
    case running
    case succeeded
    case failed
}

public struct ToolCall: Codable, Sendable, Hashable {
    public var toolUseId: String
    public var name: String
    public var summary: String
    public var inputJSON: String
    public var status: ToolStatus
    public var resultPreview: String?

    public init(
        toolUseId: String,
        name: String,
        summary: String,
        inputJSON: String,
        status: ToolStatus,
        resultPreview: String? = nil
    ) {
        self.toolUseId = toolUseId
        self.name = name
        self.summary = summary
        self.inputJSON = inputJSON
        self.status = status
        self.resultPreview = resultPreview
    }
}

public enum ChatItemKind: Codable, Sendable, Hashable {
    case userPrompt(text: String, imageCount: Int)
    case slashCommand(name: String, args: String, output: String?)
    case assistantText(markdown: String)
    case thinking(text: String?)
    case toolCall(ToolCall)
    case turnFooter(durationMs: Int)
    case recap(text: String)
    case notice(text: String)
    case unsupported(type: String)

    public var type: String {
        switch self {
        case .userPrompt: "userPrompt"
        case .slashCommand: "slashCommand"
        case .assistantText: "assistantText"
        case .thinking: "thinking"
        case .toolCall: "toolCall"
        case .turnFooter: "turnFooter"
        case .recap: "recap"
        case .notice: "notice"
        case .unsupported(let type): type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, imageCount, name, args, output, markdown, durationMs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "userPrompt":
            self = .userPrompt(
                text: try container.decode(String.self, forKey: .text),
                imageCount: try container.decode(Int.self, forKey: .imageCount)
            )
        case "slashCommand":
            self = .slashCommand(
                name: try container.decode(String.self, forKey: .name),
                args: try container.decode(String.self, forKey: .args),
                output: try container.decodeIfPresent(String.self, forKey: .output)
            )
        case "assistantText":
            self = .assistantText(markdown: try container.decode(String.self, forKey: .markdown))
        case "thinking":
            self = .thinking(text: try container.decodeIfPresent(String.self, forKey: .text))
        case "toolCall":
            self = .toolCall(try ToolCall(from: decoder))
        case "turnFooter":
            self = .turnFooter(durationMs: try container.decode(Int.self, forKey: .durationMs))
        case "recap":
            self = .recap(text: try container.decode(String.self, forKey: .text))
        case "notice":
            self = .notice(text: try container.decode(String.self, forKey: .text))
        default:
            self = .unsupported(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .userPrompt(let text, let imageCount):
            try container.encode(text, forKey: .text)
            try container.encode(imageCount, forKey: .imageCount)
        case .slashCommand(let name, let args, let output):
            try container.encode(name, forKey: .name)
            try container.encode(args, forKey: .args)
            try container.encodeIfPresent(output, forKey: .output)
        case .assistantText(let markdown):
            try container.encode(markdown, forKey: .markdown)
        case .thinking(let text):
            try container.encodeIfPresent(text, forKey: .text)
        case .toolCall(let toolCall):
            try toolCall.encode(to: encoder)
        case .turnFooter(let durationMs):
            try container.encode(durationMs, forKey: .durationMs)
        case .recap(let text), .notice(let text):
            try container.encode(text, forKey: .text)
        case .unsupported:
            break
        }
    }
}

public struct ChatItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var at: Date
    public var kind: ChatItemKind

    public init(id: String, at: Date, kind: ChatItemKind) {
        self.id = id
        self.at = at
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, at
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        at = try container.decodeProtocolDate(forKey: .at)
        kind = try ChatItemKind(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeProtocolDate(at, forKey: .at)
        try kind.encode(to: encoder)
    }
}

public struct ChatMeta: Codable, Sendable, Hashable {
    public var title: String
    public var workspaceLabel: String
    public var model: String?
    public var branch: String?
    public var status: AgentStatus
    public var permissionMode: String?

    public init(
        title: String,
        workspaceLabel: String,
        model: String? = nil,
        branch: String? = nil,
        status: AgentStatus,
        permissionMode: String? = nil
    ) {
        self.title = title
        self.workspaceLabel = workspaceLabel
        self.model = model
        self.branch = branch
        self.status = status
        self.permissionMode = permissionMode
    }
}

public struct ChatPage: Codable, Sendable, Hashable {
    public var target: ChatTarget
    public var meta: ChatMeta
    public var items: [ChatItem]
    public var before: String?
    public var hasMore: Bool

    public init(target: ChatTarget, meta: ChatMeta, items: [ChatItem], before: String?, hasMore: Bool) {
        self.target = target
        self.meta = meta
        self.items = items
        self.before = before
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey {
        case agentId, sessionId, meta, items, before, hasMore
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decodeChatTarget(agentIdKey: .agentId, sessionIdKey: .sessionId)
        meta = try container.decode(ChatMeta.self, forKey: .meta)
        items = try container.decodeLossyArray(of: ChatItem.self, forKey: .items)
        before = try container.decodeIfPresent(String.self, forKey: .before)
        hasMore = try container.decode(Bool.self, forKey: .hasMore)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeChatTarget(target, agentIdKey: .agentId, sessionIdKey: .sessionId)
        try container.encode(meta, forKey: .meta)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(before, forKey: .before)
        try container.encode(hasMore, forKey: .hasMore)
    }
}
