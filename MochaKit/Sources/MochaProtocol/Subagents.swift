import Foundation

public enum SubagentStatus: String, Codable, Sendable, Hashable {
    case running
    case completed
    case failed
    case stopped
}

public enum WorkflowStatus: String, Codable, Sendable, Hashable {
    case running
    case completed
    case failed
    case stopped
}

public enum WorkflowPhaseStatus: String, Codable, Sendable, Hashable {
    case pending
    case running
    case completed
    case failed
}

public struct SubagentCall: Codable, Sendable, Hashable {
    public var toolUseId: String
    public var agentId: String?
    public var agentType: String
    public var description: String
    public var status: SubagentStatus
    public var activity: ToolActivity?
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?
    public var failureReason: String?

    public init(
        toolUseId: String,
        agentId: String? = nil,
        agentType: String,
        description: String,
        status: SubagentStatus,
        activity: ToolActivity? = nil,
        toolUses: Int = 0,
        startedAt: Date? = nil,
        durationMs: Int? = nil,
        failureReason: String? = nil
    ) {
        self.toolUseId = toolUseId
        self.agentId = agentId
        self.agentType = agentType
        self.description = description
        self.status = status
        self.activity = activity
        self.toolUses = toolUses
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.failureReason = failureReason
    }

    private enum CodingKeys: String, CodingKey {
        case toolUseId, agentId, agentType, description, status, activity, toolUses, startedAt, durationMs, failureReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolUseId = try container.decode(String.self, forKey: .toolUseId)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        agentType = try container.decode(String.self, forKey: .agentType)
        description = try container.decode(String.self, forKey: .description)
        status = try container.decode(SubagentStatus.self, forKey: .status)
        activity = try container.decodeIfPresent(ToolActivity.self, forKey: .activity)
        toolUses = try container.decode(Int.self, forKey: .toolUses)
        startedAt = try container.decodeProtocolDateIfPresent(forKey: .startedAt)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolUseId, forKey: .toolUseId)
        try container.encodeIfPresent(agentId, forKey: .agentId)
        try container.encode(agentType, forKey: .agentType)
        try container.encode(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(activity, forKey: .activity)
        try container.encode(toolUses, forKey: .toolUses)
        try container.encodeProtocolDateIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

public struct WorkflowCall: Codable, Sendable, Hashable {
    public var toolUseId: String
    public var runId: String?
    public var name: String
    public var status: WorkflowStatus
    public var phases: [WorkflowPhase]
    public var agentCount: Int
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?

    public init(
        toolUseId: String,
        runId: String? = nil,
        name: String,
        status: WorkflowStatus,
        phases: [WorkflowPhase] = [],
        agentCount: Int = 0,
        toolUses: Int = 0,
        startedAt: Date? = nil,
        durationMs: Int? = nil
    ) {
        self.toolUseId = toolUseId
        self.runId = runId
        self.name = name
        self.status = status
        self.phases = phases
        self.agentCount = agentCount
        self.toolUses = toolUses
        self.startedAt = startedAt
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey {
        case toolUseId, runId, name, status, phases, agentCount, toolUses, startedAt, durationMs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolUseId = try container.decode(String.self, forKey: .toolUseId)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(WorkflowStatus.self, forKey: .status)
        phases = try container.decode([WorkflowPhase].self, forKey: .phases)
        agentCount = try container.decode(Int.self, forKey: .agentCount)
        toolUses = try container.decode(Int.self, forKey: .toolUses)
        startedAt = try container.decodeProtocolDateIfPresent(forKey: .startedAt)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolUseId, forKey: .toolUseId)
        try container.encodeIfPresent(runId, forKey: .runId)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encode(phases, forKey: .phases)
        try container.encode(agentCount, forKey: .agentCount)
        try container.encode(toolUses, forKey: .toolUses)
        try container.encodeProtocolDateIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
    }
}

public struct WorkflowPhase: Codable, Sendable, Hashable {
    public var title: String
    public var detail: String?
    public var status: WorkflowPhaseStatus
    public var agents: [WorkflowAgent]

    public init(title: String, detail: String? = nil, status: WorkflowPhaseStatus, agents: [WorkflowAgent] = []) {
        self.title = title
        self.detail = detail
        self.status = status
        self.agents = agents
    }
}

public struct WorkflowAgent: Codable, Sendable, Hashable {
    public var agentId: String
    public var label: String
    public var status: SubagentStatus
    public var activity: ToolActivity?
    public var durationMs: Int?

    public init(
        agentId: String,
        label: String,
        status: SubagentStatus,
        activity: ToolActivity? = nil,
        durationMs: Int? = nil
    ) {
        self.agentId = agentId
        self.label = label
        self.status = status
        self.activity = activity
        self.durationMs = durationMs
    }
}

public struct SubagentChatInfo: Codable, Sendable, Hashable {
    public var parentTitle: String
    public var agentType: String
    public var status: SubagentStatus
    public var startedAt: Date?
    public var durationMs: Int?
    public var toolUses: Int
    public var failureReason: String?

    public init(
        parentTitle: String,
        agentType: String,
        status: SubagentStatus,
        startedAt: Date? = nil,
        durationMs: Int? = nil,
        toolUses: Int = 0,
        failureReason: String? = nil
    ) {
        self.parentTitle = parentTitle
        self.agentType = agentType
        self.status = status
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.toolUses = toolUses
        self.failureReason = failureReason
    }

    private enum CodingKeys: String, CodingKey {
        case parentTitle, agentType, status, startedAt, durationMs, toolUses, failureReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parentTitle = try container.decode(String.self, forKey: .parentTitle)
        agentType = try container.decode(String.self, forKey: .agentType)
        status = try container.decode(SubagentStatus.self, forKey: .status)
        startedAt = try container.decodeProtocolDateIfPresent(forKey: .startedAt)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        toolUses = try container.decode(Int.self, forKey: .toolUses)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parentTitle, forKey: .parentTitle)
        try container.encode(agentType, forKey: .agentType)
        try container.encode(status, forKey: .status)
        try container.encodeProtocolDateIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(toolUses, forKey: .toolUses)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

public struct SubagentSummary: Codable, Sendable, Hashable, Identifiable {
    public var agentId: String
    public var parentAgentId: String?
    public var agentType: String
    public var description: String
    public var status: SubagentStatus
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?

    public var id: String { agentId }

    public init(
        agentId: String,
        parentAgentId: String? = nil,
        agentType: String,
        description: String,
        status: SubagentStatus,
        toolUses: Int = 0,
        startedAt: Date? = nil,
        durationMs: Int? = nil
    ) {
        self.agentId = agentId
        self.parentAgentId = parentAgentId
        self.agentType = agentType
        self.description = description
        self.status = status
        self.toolUses = toolUses
        self.startedAt = startedAt
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey {
        case agentId, parentAgentId, agentType, description, status, toolUses, startedAt, durationMs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentId = try container.decode(String.self, forKey: .agentId)
        parentAgentId = try container.decodeIfPresent(String.self, forKey: .parentAgentId)
        agentType = try container.decode(String.self, forKey: .agentType)
        description = try container.decode(String.self, forKey: .description)
        status = try container.decode(SubagentStatus.self, forKey: .status)
        toolUses = try container.decode(Int.self, forKey: .toolUses)
        startedAt = try container.decodeProtocolDateIfPresent(forKey: .startedAt)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentId, forKey: .agentId)
        try container.encodeIfPresent(parentAgentId, forKey: .parentAgentId)
        try container.encode(agentType, forKey: .agentType)
        try container.encode(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(toolUses, forKey: .toolUses)
        try container.encodeProtocolDateIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
    }
}
