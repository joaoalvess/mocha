import Foundation

public enum AgentStatus: String, Codable, Sendable, Hashable {
    case idle
    case working
    case blocked
    case done
    case unknown

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = AgentStatus(rawValue: rawValue) ?? .unknown
    }
}

public struct WorkspaceNode: Codable, Sendable, Hashable, Identifiable {
    public var id: WorkspaceID
    public var label: String
    public var number: Int
    public var repoName: String?
    public var branch: String?
    public var isDirty: Bool
    public var agentStatus: AgentStatus
    public var tabs: [TabNode]
    public var children: [WorkspaceNode]

    public init(
        id: WorkspaceID,
        label: String,
        number: Int,
        repoName: String? = nil,
        branch: String? = nil,
        isDirty: Bool,
        agentStatus: AgentStatus,
        tabs: [TabNode],
        children: [WorkspaceNode] = []
    ) {
        self.id = id
        self.label = label
        self.number = number
        self.repoName = repoName
        self.branch = branch
        self.isDirty = isDirty
        self.agentStatus = agentStatus
        self.tabs = tabs
        self.children = children
    }
}

public struct TabNode: Codable, Sendable, Hashable, Identifiable {
    public var id: TabID
    public var title: String
    public var agents: [AgentSummary]

    public init(id: TabID, title: String, agents: [AgentSummary] = []) {
        self.id = id
        self.title = title
        self.agents = agents
    }
}

public struct AgentSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: AgentID
    public var kind: String
    public var status: AgentStatus
    public var title: String
    public var workspaceLabel: String
    public var model: String?
    public var branch: String?
    public var sessionId: String?
    public var lastActivityAt: Date?
    public var pendingCount: Int

    public init(
        id: AgentID,
        kind: String,
        status: AgentStatus,
        title: String,
        workspaceLabel: String,
        model: String? = nil,
        branch: String? = nil,
        sessionId: String? = nil,
        lastActivityAt: Date? = nil,
        pendingCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.workspaceLabel = workspaceLabel
        self.model = model
        self.branch = branch
        self.sessionId = sessionId
        self.lastActivityAt = lastActivityAt
        self.pendingCount = pendingCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, title, workspaceLabel, model, branch, sessionId, lastActivityAt, pendingCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AgentID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        status = try container.decode(AgentStatus.self, forKey: .status)
        title = try container.decode(String.self, forKey: .title)
        workspaceLabel = try container.decode(String.self, forKey: .workspaceLabel)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        lastActivityAt = try container.decodeProtocolDateIfPresent(forKey: .lastActivityAt)
        pendingCount = try container.decode(Int.self, forKey: .pendingCount)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(status, forKey: .status)
        try container.encode(title, forKey: .title)
        try container.encode(workspaceLabel, forKey: .workspaceLabel)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeProtocolDateIfPresent(lastActivityAt, forKey: .lastActivityAt)
        try container.encode(pendingCount, forKey: .pendingCount)
    }
}
