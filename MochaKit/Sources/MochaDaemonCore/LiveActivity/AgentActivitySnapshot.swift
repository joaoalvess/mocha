import Foundation
import MochaProtocol

struct AgentActivitySnapshot: Sendable, Equatable {
    static let startTitle = "Claude trabalhando"
    static let shortLabelLimit = 20

    static let shrunkToFitPayload: [@Sendable (inout Self) -> Void] = LiveActivityContentState.Highlight.droppedToFitBudget.map { drop in
        { drop(&$0.agent) }
    } + [
        { $0.pending = $0.pending?.withoutOptions },
        {
            $0.agent.title = String($0.agent.title.prefix(shortLabelLimit))
            $0.agent.workspaceLabel = String($0.agent.workspaceLabel.prefix(shortLabelLimit))
        },
    ]

    var agent: LiveActivityContentState.Highlight
    var pending: LiveActivityContentState.Pending?
    var status: AgentStatus

    static func gone(_ agentId: AgentID, at date: Date) -> AgentActivitySnapshot {
        AgentActivitySnapshot(
            agent: LiveActivityContentState.Highlight(agentId: agentId, title: "", workspaceLabel: "", status: AgentStatus.idle.rawValue, since: date),
            pending: nil,
            status: .idle
        )
    }

    var isBusy: Bool {
        status == .working || status == .blocked
    }

    var isBlocked: Bool {
        status == .blocked
    }

    var relevanceScore: Double {
        switch status {
        case .blocked: 100
        case .working: 50
        default: 10
        }
    }

    var ended: AgentActivitySnapshot {
        var ended = self
        ended.pending = nil
        return ended
    }

    func contentState(at date: Date) -> AgentActivityContentState {
        AgentActivityContentState(agent: agent, pending: pending, updatedAt: date)
    }

    func push(_ event: (AgentActivitySnapshot) -> AgentActivityEvent, at date: Date, staleDate: Date?) -> AgentActivityPush {
        var fitted = self
        var push = fitted.makePush(event(fitted), at: date, staleDate: staleDate)
        for shrink in Self.shrunkToFitPayload where !push.fitsPayloadLimit {
            shrink(&fitted)
            push = fitted.makePush(event(fitted), at: date, staleDate: staleDate)
        }
        return push
    }

    func priority(since sent: AgentActivitySnapshot?) -> ApnsPriority? {
        guard let sent else { return .high }
        guard self != sent else { return nil }
        return status == sent.status && pending?.requestId == sent.pending?.requestId ? .low : .high
    }

    func alert(since sent: AgentActivitySnapshot?) -> PushAlertKind? {
        if let pending, pending.requestId != sent?.pending?.requestId {
            return .needsInput
        }
        if pending == nil, isBlocked, sent?.isBlocked == false {
            return .needsInput
        }
        if let sent, sent.isBusy, !isBusy {
            return .turnDone
        }
        return nil
    }

    func alertContent(_ kind: PushAlertKind) -> AgentActivityAlert {
        let body = switch kind {
        case .needsInput: pendingBody ?? PushAlertText.secondaryBody
        case .turnDone: agent.preview ?? PushAlertText.turnDoneFallback
        }
        return AgentActivityAlert(title: PushAlertText.title(kind, workspaceLabel: agent.workspaceLabel, provider: agent.provider), body: String(body.prefix(PushAlertText.bodyLimit)))
    }

    var startAlert: AgentActivityAlert {
        let title = agent.title.allSatisfy(\.isWhitespace) ? agent.workspaceLabel : agent.title
        let startTitle = agent.provider == .codex ? "Codex trabalhando" : Self.startTitle
        return AgentActivityAlert(title: PushAlertText.title(startTitle, workspaceLabel: agent.workspaceLabel), body: title, sound: nil)
    }

    private var pendingBody: String? {
        guard let pending else { return nil }
        guard pending.text.allSatisfy(\.isWhitespace) else { return pending.text }
        return pending.toolName
    }

    private func makePush(_ event: AgentActivityEvent, at date: Date, staleDate: Date?) -> AgentActivityPush {
        AgentActivityPush(
            agentId: agent.agentId,
            event: event,
            contentState: contentState(at: date),
            timestamp: date,
            staleDate: staleDate,
            relevanceScore: relevanceScore
        )
    }
}

struct AgentActivityTracker: Sendable {
    private struct Entry: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
    }

    private var entries: [AgentID: Entry] = [:]
    private(set) var lastBusyAt: [AgentID: Date] = [:]

    mutating func snapshots(of input: LiveActivityInput, at now: Date, titleLimit: Int) -> [AgentID: AgentActivitySnapshot] {
        let pendingAgents = Set(input.pending.map(\.agentId))
        var tracked: [AgentID: Entry] = [:]
        var snapshots: [AgentID: AgentActivitySnapshot] = [:]
        for agent in input.agents where (agent.kind == TreeComposer.claudeKind || agent.kind == AgentProvider.codex.rawValue) && tracked[agent.id] == nil {
            let status = Self.effectiveStatus(of: agent, hasPending: pendingAgents.contains(agent.id))
            let wasBusy = entries[agent.id].map { $0.status == .working || $0.status == .blocked } ?? false
            let entry = entries[agent.id].flatMap { $0.status == status ? $0 : nil } ?? Entry(status: status, since: now)
            tracked[agent.id] = entry
            let request = input.pending.filter { $0.agentId == agent.id }.min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            let snapshot = AgentActivitySnapshot(
                agent: LiveActivityContentState.Highlight(
                    agent,
                    status: status,
                    since: entry.since,
                    prompt: input.prompts[agent.id],
                    titleLimit: titleLimit,
                    showsProgress: request == nil
                ),
                pending: request.map { LiveActivityContentState.Pending($0) },
                status: status
            )
            snapshots[agent.id] = snapshot
            if snapshot.isBusy || wasBusy || lastBusyAt[agent.id] == nil {
                lastBusyAt[agent.id] = now
            }
        }
        entries = tracked
        lastBusyAt = lastBusyAt.filter { tracked[$0.key] != nil }
        return snapshots
    }

    private static func effectiveStatus(of agent: AgentSummary, hasPending: Bool) -> AgentStatus {
        if agent.status == .blocked || agent.pendingCount > 0 || hasPending {
            return .blocked
        }
        return agent.status == .working ? .working : .idle
    }
}
