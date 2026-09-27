import Foundation
import MochaProtocol

public struct AgentsActivityTracker: Sendable, Equatable {
    public static let titleLimit = 60

    private struct Entry: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
        let title: String
        let workspaceLabel: String
    }

    private var entries: [AgentID: Entry] = [:]

    public init() {}

    @discardableResult
    public mutating func update(_ agents: [AgentSummary], at now: Date) -> Bool {
        var next: [AgentID: Entry] = [:]
        var agentBecameWorking = false
        for agent in agents where agent.kind == HomeSections.claudeKind && next[agent.id] == nil {
            guard let status = Self.effectiveStatus(of: agent) else { continue }
            let previous = entries[agent.id]
            if status == .working, previous?.status != .working {
                agentBecameWorking = true
            }
            let since = previous.flatMap { $0.status == status ? $0.since : nil } ?? Self.since(of: agent, status: status, now: now)
            next[agent.id] = Entry(status: status, since: since, title: agent.title, workspaceLabel: agent.workspaceLabel)
        }
        entries = next
        return agentBecameWorking
    }

    public func content(at now: Date) -> AgentsActivityContent {
        let busy = entries.sorted { ($0.value.since, $0.key) < ($1.value.since, $1.key) }
        let waiting = busy.filter { $0.value.status == .blocked }
        let working = busy.filter { $0.value.status == .working }
        let highlight = (waiting.first ?? working.first).map { agentId, entry in
            AgentsActivityContent.Highlight(
                agentId: agentId,
                title: String(entry.title.prefix(Self.titleLimit)),
                workspaceLabel: entry.workspaceLabel,
                status: entry.status.rawValue,
                since: entry.since
            )
        }
        return AgentsActivityContent(working: working.count, waiting: waiting.count, highlight: highlight, updatedAt: now)
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
    public static func shouldStart(agentBecameWorking: Bool, isForeground: Bool, hasOngoingActivity: Bool, activitiesEnabled: Bool) -> Bool {
        agentBecameWorking && isForeground && !hasOngoingActivity && activitiesEnabled
    }
}
