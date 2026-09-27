import Foundation
import MochaProtocol

public protocol SubagentProviding: Sendable {
    func events() -> AsyncStream<SubagentEvent>
    func observe(sessions: Set<String>) async
    func runningCount(session sessionId: String) async -> Int
    func subagents(session sessionId: String) async -> [SubagentSummary]
    func state(_ agentId: String) async -> SubagentState?
    func workflow(_ runId: String) async -> WorkflowState?
    func transcript(session sessionId: String, agentId: String) async -> SubagentTranscript?
}

public struct SubagentTranscript: Sendable, Hashable {
    public var agentId: String
    public var path: String
    public var forkToolUseId: String?

    public init(agentId: String, path: String, forkToolUseId: String? = nil) {
        self.agentId = agentId
        self.path = path
        self.forkToolUseId = forkToolUseId
    }
}

public struct SubagentState: Sendable, Equatable {
    public var agentId: String
    public var sessionId: String
    public var toolUseId: String?
    public var parentAgentId: String?
    public var runId: String?
    public var agentType: String
    public var description: String
    public var status: SubagentStatus
    public var activity: ToolActivity?
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?
    public var failureReason: String?

    public init(
        agentId: String,
        sessionId: String,
        toolUseId: String? = nil,
        parentAgentId: String? = nil,
        runId: String? = nil,
        agentType: String,
        description: String,
        status: SubagentStatus,
        activity: ToolActivity? = nil,
        toolUses: Int = 0,
        startedAt: Date? = nil,
        durationMs: Int? = nil,
        failureReason: String? = nil
    ) {
        self.agentId = agentId
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.parentAgentId = parentAgentId
        self.runId = runId
        self.agentType = agentType
        self.description = description
        self.status = status
        self.activity = activity
        self.toolUses = toolUses
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.failureReason = failureReason
    }

    public var summary: SubagentSummary {
        SubagentSummary(
            agentId: agentId,
            parentAgentId: parentAgentId,
            agentType: agentType,
            description: description,
            status: status,
            toolUses: toolUses,
            startedAt: startedAt,
            durationMs: durationMs
        )
    }
}

public struct WorkflowState: Sendable, Equatable {
    public var runId: String
    public var sessionId: String
    public var toolUseId: String?
    public var name: String?
    public var status: WorkflowStatus
    public var phases: [WorkflowPhase]
    public var agentCount: Int
    public var toolUses: Int
    public var durationMs: Int?

    public init(
        runId: String,
        sessionId: String,
        toolUseId: String? = nil,
        name: String? = nil,
        status: WorkflowStatus,
        phases: [WorkflowPhase] = [],
        agentCount: Int = 0,
        toolUses: Int = 0,
        durationMs: Int? = nil
    ) {
        self.runId = runId
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.name = name
        self.status = status
        self.phases = phases
        self.agentCount = agentCount
        self.toolUses = toolUses
        self.durationMs = durationMs
    }
}

public enum SubagentEvent: Sendable, Equatable {
    case subagent(SubagentState)
    case workflow(WorkflowState)
    case runningCount(sessionId: String, count: Int)
}

enum SubagentOrdering {
    static func listed(_ states: [SubagentState]) -> [SubagentSummary] {
        let ids = Set(states.map(\.agentId))
        let children = Dictionary(grouping: states.filter { $0.parentAgentId.map(ids.contains) ?? false }) { $0.parentAgentId ?? "" }
        let roots = states.filter { !($0.parentAgentId.map(ids.contains) ?? false) }
        var result: [SubagentSummary] = []
        func append(_ siblings: [SubagentState]) {
            for state in sorted(siblings) {
                result.append(state.summary)
                append(children[state.agentId] ?? [])
            }
        }
        append(roots)
        return result
    }

    private static func sorted(_ states: [SubagentState]) -> [SubagentState] {
        let running = states.filter { $0.status == .running }
            .sorted { key($0.startedAt, $0.agentId) > key($1.startedAt, $1.agentId) }
        let finished = states.filter { $0.status != .running }
            .sorted { key(end(of: $0), $0.agentId) > key(end(of: $1), $1.agentId) }
        return running + finished
    }

    private static func end(of state: SubagentState) -> Date? {
        guard let startedAt = state.startedAt else { return nil }
        return startedAt.addingTimeInterval(Double(state.durationMs ?? 0) / 1000)
    }

    private static func key(_ date: Date?, _ id: String) -> (Double, String) {
        (date?.timeIntervalSinceReferenceDate ?? -.infinity, id)
    }
}
