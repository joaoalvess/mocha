import Foundation

public enum ArchiveReason: String, Codable, Sendable, Hashable {
    case cleared
    case ended
    case unknown

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ArchiveReason(rawValue: rawValue) ?? .unknown
    }
}

public struct ArchivedSession: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: AgentProvider
    public var agentId: AgentID?
    public var title: String
    public var workspaceLabel: String
    public var model: String?
    public var branch: String?
    public var preview: MessagePreview?
    public var contextLeftPercent: Int?
    public var reason: ArchiveReason
    public var endedAt: Date
    public var sessionStartedAt: Date?
    public var lastActivityAt: Date?

    public init(
        id: String,
        provider: AgentProvider = .claude,
        agentId: AgentID? = nil,
        title: String,
        workspaceLabel: String,
        model: String? = nil,
        branch: String? = nil,
        preview: MessagePreview? = nil,
        contextLeftPercent: Int? = nil,
        reason: ArchiveReason,
        endedAt: Date,
        sessionStartedAt: Date? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.agentId = agentId
        self.title = title
        self.workspaceLabel = workspaceLabel
        self.model = model
        self.branch = branch
        self.preview = preview
        self.contextLeftPercent = contextLeftPercent
        self.reason = reason
        self.endedAt = endedAt
        self.sessionStartedAt = sessionStartedAt
        self.lastActivityAt = lastActivityAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, agentId, title, workspaceLabel, model, branch, preview, contextLeftPercent, reason, endedAt
        case sessionStartedAt, lastActivityAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .claude
        agentId = try container.decodeIfPresent(AgentID.self, forKey: .agentId)
        title = try container.decode(String.self, forKey: .title)
        workspaceLabel = try container.decode(String.self, forKey: .workspaceLabel)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        preview = try container.decodeIfPresent(MessagePreview.self, forKey: .preview)
        contextLeftPercent = try container.decodeIfPresent(Int.self, forKey: .contextLeftPercent)
        reason = try container.decode(ArchiveReason.self, forKey: .reason)
        endedAt = try container.decodeProtocolDate(forKey: .endedAt)
        sessionStartedAt = try container.decodeProtocolDateIfPresent(forKey: .sessionStartedAt)
        lastActivityAt = try container.decodeProtocolDateIfPresent(forKey: .lastActivityAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if provider != .claude {
            try container.encode(provider, forKey: .provider)
        }
        try container.encodeIfPresent(agentId, forKey: .agentId)
        try container.encode(title, forKey: .title)
        try container.encode(workspaceLabel, forKey: .workspaceLabel)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(contextLeftPercent, forKey: .contextLeftPercent)
        try container.encode(reason, forKey: .reason)
        try container.encodeProtocolDate(endedAt, forKey: .endedAt)
        try container.encodeProtocolDateIfPresent(sessionStartedAt, forKey: .sessionStartedAt)
        try container.encodeProtocolDateIfPresent(lastActivityAt, forKey: .lastActivityAt)
    }
}
