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
    public var preview: MessagePreview?
    public var activity: ToolActivity?
    public var contextLeftPercent: Int?
    public var sessionStartedAt: Date?
    public var turnStartedAt: Date?
    public var turnEndedAt: Date?
    public var archivedAt: Date?
    public var runningSubagents: Int?
    public var controlAvailable: Bool?
    public var permissionMode: String?
    public var effort: String?

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
        pendingCount: Int = 0,
        preview: MessagePreview? = nil,
        activity: ToolActivity? = nil,
        contextLeftPercent: Int? = nil,
        sessionStartedAt: Date? = nil,
        turnStartedAt: Date? = nil,
        turnEndedAt: Date? = nil,
        archivedAt: Date? = nil,
        runningSubagents: Int? = nil,
        controlAvailable: Bool? = nil,
        permissionMode: String? = nil,
        effort: String? = nil
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
        self.preview = preview
        self.activity = activity
        self.contextLeftPercent = contextLeftPercent
        self.sessionStartedAt = sessionStartedAt
        self.turnStartedAt = turnStartedAt
        self.turnEndedAt = turnEndedAt
        self.archivedAt = archivedAt
        self.runningSubagents = runningSubagents
        self.controlAvailable = controlAvailable
        self.permissionMode = permissionMode
        self.effort = effort
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, title, workspaceLabel, model, branch, sessionId, lastActivityAt, pendingCount
        case preview, activity, contextLeftPercent, sessionStartedAt, turnStartedAt, turnEndedAt, archivedAt
        case runningSubagents, controlAvailable, permissionMode, effort
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
        preview = (try? container.decodeIfPresent(MessagePreview.self, forKey: .preview)) ?? nil
        activity = (try? container.decodeIfPresent(ToolActivity.self, forKey: .activity)) ?? nil
        contextLeftPercent = try container.decodeIfPresent(Int.self, forKey: .contextLeftPercent)
        sessionStartedAt = try container.decodeProtocolDateIfPresent(forKey: .sessionStartedAt)
        turnStartedAt = try container.decodeProtocolDateIfPresent(forKey: .turnStartedAt)
        turnEndedAt = try container.decodeProtocolDateIfPresent(forKey: .turnEndedAt)
        archivedAt = try container.decodeProtocolDateIfPresent(forKey: .archivedAt)
        runningSubagents = try container.decodeIfPresent(Int.self, forKey: .runningSubagents)
        controlAvailable = try container.decodeIfPresent(Bool.self, forKey: .controlAvailable)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        effort = try container.decodeIfPresent(String.self, forKey: .effort)
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
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(activity, forKey: .activity)
        try container.encodeIfPresent(contextLeftPercent, forKey: .contextLeftPercent)
        try container.encodeProtocolDateIfPresent(sessionStartedAt, forKey: .sessionStartedAt)
        try container.encodeProtocolDateIfPresent(turnStartedAt, forKey: .turnStartedAt)
        try container.encodeProtocolDateIfPresent(turnEndedAt, forKey: .turnEndedAt)
        try container.encodeProtocolDateIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(runningSubagents, forKey: .runningSubagents)
        try container.encodeIfPresent(controlAvailable, forKey: .controlAvailable)
        try container.encodeIfPresent(permissionMode, forKey: .permissionMode)
        try container.encodeIfPresent(effort, forKey: .effort)
    }
}

public enum MessageAuthor: String, Codable, Sendable, Hashable {
    case user
    case assistant
}

public struct MessagePreview: Codable, Sendable, Hashable {
    public var author: MessageAuthor
    public var text: String

    public init(author: MessageAuthor, text: String) {
        self.author = author
        self.text = text
    }
}

public struct ToolActivity: Codable, Sendable, Hashable {
    public var toolName: String
    public var summary: String
    public var status: ToolStatus

    public init(toolName: String, summary: String, status: ToolStatus) {
        self.toolName = toolName
        self.summary = summary
        self.status = status
    }
}
