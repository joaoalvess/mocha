import Foundation
import MochaProtocol

struct LiveActivitySnapshot: Sendable, Equatable {
    static let allDone = LiveActivitySnapshot(working: 0, waiting: 0, highlight: nil, pending: nil)

    var working: Int
    var waiting: Int
    var highlight: LiveActivityContentState.Highlight?
    var pending: LiveActivityContentState.Pending?

    var isBusy: Bool {
        working > 0 || waiting > 0
    }

    var summary: String {
        guard isBusy else { return "Tudo pronto" }
        return [working > 0 ? "\(working) trabalhando" : nil, waiting > 0 ? "\(waiting) esperando você" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    func contentState(at date: Date) -> LiveActivityContentState {
        LiveActivityContentState(working: working, waiting: waiting, highlight: highlight, pending: pending, updatedAt: date)
    }

    func priority(since sent: LiveActivitySnapshot) -> ApnsPriority? {
        guard self != sent else { return nil }
        guard working == sent.working, waiting == sent.waiting, pending?.requestId == sent.pending?.requestId else { return .high }
        switch (sent.highlight, highlight) {
        case (let before?, let after?) where before.agentId == after.agentId && before.status == after.status:
            return .low
        default:
            return .high
        }
    }
}

struct LiveActivityStatusTracker: Sendable {
    private struct Entry: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
    }

    private var entries: [AgentID: Entry] = [:]

    mutating func snapshot(of agents: [AgentSummary], pending requests: [PendingRequest], at now: Date, titleLimit: Int) -> LiveActivitySnapshot {
        let pendingAgents = Set(requests.map(\.agentId))
        var tracked: [AgentID: Entry] = [:]
        var busy: [(agent: AgentSummary, entry: Entry)] = []
        for agent in agents where agent.kind == TreeComposer.claudeKind && tracked[agent.id] == nil {
            guard let status = Self.effectiveStatus(of: agent, hasPending: pendingAgents.contains(agent.id)) else { continue }
            let entry = entries[agent.id].flatMap { $0.status == status ? $0 : nil } ?? Entry(status: status, since: now)
            tracked[agent.id] = entry
            busy.append((agent, entry))
        }
        entries = tracked
        let waiting = busy.filter { $0.entry.status == .blocked }
        let working = busy.filter { $0.entry.status == .working }
        let oldest: ((agent: AgentSummary, entry: Entry), (agent: AgentSummary, entry: Entry)) -> Bool = {
            ($0.entry.since, $0.agent.id) < ($1.entry.since, $1.agent.id)
        }
        let request = requests.filter { tracked[$0.agentId] != nil }.min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let requester = request.flatMap { request in busy.first { $0.agent.id == request.agentId } }
        let chosen = requester ?? waiting.min(by: oldest) ?? working.min(by: oldest)
        let highlight = chosen.map { agent, entry in
            LiveActivityContentState.Highlight(
                agentId: agent.id,
                title: String(agent.title.prefix(titleLimit)),
                workspaceLabel: agent.workspaceLabel,
                status: entry.status.rawValue,
                since: entry.since
            )
        }
        return LiveActivitySnapshot(
            working: working.count,
            waiting: waiting.count,
            highlight: highlight,
            pending: request.map { LiveActivityContentState.Pending($0) }
        )
    }

    private static func effectiveStatus(of agent: AgentSummary, hasPending: Bool) -> AgentStatus? {
        if agent.status == .blocked || agent.pendingCount > 0 || hasPending {
            return .blocked
        }
        return agent.status == .working ? .working : nil
    }
}
