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
        status.isBusy
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
        guard agent.agentId == sent.agent.agentId else { return .high }
        return status == sent.status && pending?.requestId == sent.pending?.requestId ? .low : .high
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

struct AgentFeedAlert: Sendable, Equatable {
    let generation: Int
    let kind: PushAlertKind

    func isValid(for status: AgentStatus) -> Bool {
        switch kind {
        case .needsInput: status == .blocked
        case .turnDone: !status.isBusy
        }
    }
}

struct DroppedFeedAlert: Sendable, Equatable {
    let agentId: AgentID
    let alert: AgentFeedAlert
}

struct AgentActivityTracker: Sendable {
    private struct Entry: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
    }

    private struct Observation: Sendable, Equatable {
        let status: AgentStatus
        let preview: String?
        let requestId: RequestID?
    }

    private var entries: [AgentID: Entry] = [:]
    private var observations: [AgentID: Observation] = [:]
    private var generation = 0
    private(set) var eventGenerations: [AgentID: Int] = [:]
    private(set) var alerts: [AgentID: AgentFeedAlert] = [:]
    private(set) var droppedAlerts: [DroppedFeedAlert] = []
    private(set) var holder: AgentID?
    private(set) var lastBusyAt: Date?

    mutating func snapshots(of input: LiveActivityInput, at now: Date, titleLimit: Int) -> [AgentID: AgentActivitySnapshot] {
        generation += 1
        droppedAlerts = []
        let pendingAgents = Set(input.pending.map(\.agentId))
        let wasBusy = observations.values.contains { $0.status.isBusy }
        var tracked: [AgentID: Entry] = [:]
        var observed: [AgentID: Observation] = [:]
        var snapshots: [AgentID: AgentActivitySnapshot] = [:]
        for agent in input.agents where (agent.kind == TreeComposer.claudeKind || agent.kind == AgentProvider.codex.rawValue) && tracked[agent.id] == nil {
            let status = Self.effectiveStatus(of: agent, hasPending: pendingAgents.contains(agent.id))
            let entry = entries[agent.id].flatMap { $0.status == status ? $0 : nil } ?? Entry(status: status, since: now)
            tracked[agent.id] = entry
            let request = input.pending.filter { $0.agentId == agent.id }.min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            snapshots[agent.id] = AgentActivitySnapshot(
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
            let observation = Observation(status: status, preview: LiveActivityContentState.Highlight.preview(of: agent.preview), requestId: request?.id)
            observed[agent.id] = observation
            record(observation, since: observations[agent.id], of: agent.id)
        }
        entries = tracked
        observations = observed
        eventGenerations = eventGenerations.filter { tracked[$0.key] != nil }
        for (agentId, alert) in alerts where tracked[agentId] == nil {
            droppedAlerts.append(DroppedFeedAlert(agentId: agentId, alert: alert))
        }
        alerts = alerts.filter { tracked[$0.key] != nil }
        holder = input.pending
            .filter { snapshots[$0.agentId] != nil }
            .min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }?
            .agentId
        if wasBusy || snapshots.values.contains(where: \.isBusy) || lastBusyAt == nil {
            lastBusyAt = now
        }
        return snapshots
    }

    func focus(among snapshots: [AgentID: AgentActivitySnapshot], current: AgentID?) -> AgentID? {
        if let holder, snapshots[holder] != nil {
            return holder
        }
        guard let latest = snapshots.keys.map({ eventGenerations[$0] ?? 0 }).max() else { return nil }
        let tied = snapshots.keys.filter { (eventGenerations[$0] ?? 0) == latest }
        if let current, tied.contains(current) {
            return current
        }
        return tied.min()
    }

    private mutating func record(_ observation: Observation, since previous: Observation?, of agentId: AgentID) {
        if observation != previous, previous != nil || observation.status.isBusy {
            eventGenerations[agentId] = generation
        }
        if let kind = Self.alert(observation, since: previous) {
            if let replaced = alerts[agentId] {
                droppedAlerts.append(DroppedFeedAlert(agentId: agentId, alert: replaced))
            }
            alerts[agentId] = AgentFeedAlert(generation: generation, kind: kind)
        } else if let alert = alerts[agentId], !alert.isValid(for: observation.status) {
            droppedAlerts.append(DroppedFeedAlert(agentId: agentId, alert: alert))
            alerts[agentId] = nil
        }
    }

    private static func alert(_ observation: Observation, since previous: Observation?) -> PushAlertKind? {
        if let requestId = observation.requestId, requestId != previous?.requestId {
            return .needsInput
        }
        guard let previous else { return nil }
        if observation.requestId == nil, observation.status == .blocked, previous.status != .blocked {
            return .needsInput
        }
        if previous.status.isBusy, !observation.status.isBusy {
            return .turnDone
        }
        return nil
    }

    private static func effectiveStatus(of agent: AgentSummary, hasPending: Bool) -> AgentStatus {
        if agent.status == .blocked || agent.pendingCount > 0 || hasPending {
            return .blocked
        }
        return agent.status == .working ? .working : .idle
    }
}

extension AgentStatus {
    var isBusy: Bool {
        self == .working || self == .blocked
    }
}
