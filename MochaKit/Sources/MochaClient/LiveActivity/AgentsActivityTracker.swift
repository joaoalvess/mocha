import Foundation
import MochaProtocol

public struct AgentsActivityTracker: Sendable, Equatable {
    public static let titleLimit = 60

    private struct Entry: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
        let agent: AgentSummary
    }

    private var entries: [AgentID: Entry] = [:]

    public init() {}

    @discardableResult
    public mutating func update(_ agents: [AgentSummary], at now: Date) -> Set<AgentID> {
        var next: [AgentID: Entry] = [:]
        var becameBusy: Set<AgentID> = []
        for agent in agents where (agent.kind == HomeSections.claudeKind || agent.kind == HomeSections.codexKind) && next[agent.id] == nil {
            guard let status = Self.effectiveStatus(of: agent) else { continue }
            let previous = entries[agent.id]
            if previous == nil {
                becameBusy.insert(agent.id)
            }
            let since = previous.flatMap { $0.status == status ? $0.since : nil } ?? Self.since(of: agent, status: status, now: now)
            next[agent.id] = Entry(status: status, since: since, agent: agent)
        }
        entries = next
        return becameBusy
    }

    public func content(for agentId: AgentID, at now: Date) -> AgentsActivityContent? {
        guard let entry = entries[agentId] else { return nil }
        return AgentsActivityContent(
            status: entry.status.rawValue,
            title: String(entry.agent.title.prefix(Self.titleLimit)),
            workspaceLabel: entry.agent.workspaceLabel,
            since: entry.since,
            model: entry.agent.model,
            contextLeftPercent: entry.agent.contextLeftPercent,
            updatedAt: now
        )
    }

    private static func effectiveStatus(of agent: AgentSummary) -> AgentStatus? {
        if agent.status == .blocked || agent.pendingCount > 0 {
            return .blocked
        }
        return agent.status == .working ? .working : nil
    }

    private static func since(of agent: AgentSummary, status: AgentStatus, now: Date) -> Date {
        guard status == .working, let turnStartedAt = agent.turnStartedAt, turnStartedAt <= now else { return now }
        return turnStartedAt
    }
}

public enum AgentsActivityStartPolicy {
    public static func shouldStart(isForeground: Bool, hasActivityForAgent: Bool, activitiesEnabled: Bool) -> Bool {
        isForeground && !hasActivityForAgent && activitiesEnabled
    }
}
