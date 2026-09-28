import Foundation
import MochaProtocol

public struct AgentsActivityTracker: Sendable, Equatable {
    public static let titleLimit = 60

    private struct Entry: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
        let changedAt: Date
        let pendingSince: Date?
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
            let unchanged = previous.flatMap { $0.status == status ? $0 : nil }
            next[agent.id] = Entry(
                status: status,
                since: unchanged?.since ?? Self.since(of: agent, status: status, now: now),
                changedAt: unchanged?.changedAt ?? now,
                pendingSince: agent.pendingCount > 0 ? previous?.pendingSince ?? now : nil,
                agent: agent
            )
        }
        entries = next
        return becameBusy
    }

    public var focus: AgentID? {
        let pending = entries.compactMap { id, entry in entry.pendingSince.map { (id: id, at: $0) } }
        if let oldest = pending.min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            return oldest.id
        }
        return entries.min { ($1.value.changedAt, $0.key) < ($0.value.changedAt, $1.key) }?.key
    }

    public func content(for agentId: AgentID, at now: Date) -> AgentsActivityContent? {
        guard let entry = entries[agentId] else { return nil }
        return AgentsActivityContent(
            agentId: agentId,
            status: entry.status.rawValue,
            title: String(entry.agent.title.prefix(Self.titleLimit)),
            workspaceLabel: entry.agent.workspaceLabel,
            since: entry.since,
            model: entry.agent.model,
            provider: entry.agent.kind == HomeSections.codexKind ? .codex : nil,
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
    public static func shouldStart(becameBusy: Bool, isForeground: Bool, hasActivity: Bool, activitiesEnabled: Bool) -> Bool {
        becameBusy && isForeground && !hasActivity && activitiesEnabled
    }
}
