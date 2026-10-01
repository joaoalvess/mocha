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
    let at: Date
    var requestId: RequestID?

    func isValid(for status: AgentStatus) -> Bool {
        switch kind {
        case .needsInput: status == .blocked
        case .turnDone: !status.isBusy
        }
    }
}

struct AgentActivityTiming: Sendable, Equatable {
    var turnDoneCooldown: TimeInterval = 0
    var blockedGrace: TimeInterval = 0
    var blockedAlertWindow: TimeInterval = 0
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

    private struct Hold: Sendable, Equatable {
        let status: AgentStatus
        let since: Date
        let delay: TimeInterval

        var deadline: Date {
            since.addingTimeInterval(delay)
        }
    }

    private struct ShownOutcome: Sendable, Equatable {
        let requestId: RequestID
        let outcome: PendingOutcome
        let preview: String?
        var isActive = true
    }

    private static let tolerance: TimeInterval = 0.001

    private let timing: AgentActivityTiming
    private var entries: [AgentID: Entry] = [:]
    private var holds: [AgentID: Hold] = [:]
    private var lastBlockedAlerts: [AgentID: Date] = [:]
    private var observations: [AgentID: Observation] = [:]
    private var outcomes: [AgentID: ShownOutcome] = [:]
    private(set) var generation = 0
    private(set) var eventGenerations: [AgentID: Int] = [:]
    private(set) var eventDates: [AgentID: Date] = [:]
    private(set) var herdrStatuses: [AgentID: AgentStatus] = [:]
    private(set) var alerts: [AgentID: AgentFeedAlert] = [:]
    private(set) var cancelledTurnsDone: [AgentID] = []
    private(set) var holder: AgentID?
    private(set) var lastBusyAt: Date?

    init(timing: AgentActivityTiming = AgentActivityTiming()) {
        self.timing = timing
    }

    var holdDeadline: Date? {
        holds.values.map(\.deadline).min()
    }

    mutating func snapshots(of input: LiveActivityInput, at now: Date, titleLimit: Int) -> [AgentID: AgentActivitySnapshot] {
        generation += 1
        cancelledTurnsDone = []
        let pendingAgents = Set(input.pending.map(\.agentId))
        let wasBusy = observations.values.contains { $0.status.isBusy }
        var tracked: [AgentID: Entry] = [:]
        var observed: [AgentID: Observation] = [:]
        var snapshots: [AgentID: AgentActivitySnapshot] = [:]
        for agent in input.agents where (agent.kind == TreeComposer.claudeKind || agent.kind == AgentProvider.codex.rawValue) && tracked[agent.id] == nil {
            let status = publishedStatus(
                of: agent.id,
                current: Self.effectiveStatus(of: agent, hasPending: pendingAgents.contains(agent.id)),
                hasPending: pendingAgents.contains(agent.id),
                at: now
            )
            let entry = entries[agent.id].flatMap { $0.status == status ? $0 : nil } ?? Entry(status: status, since: now)
            tracked[agent.id] = entry
            let request = input.pending.filter { $0.agentId == agent.id }.min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            let preview = LiveActivityContentState.Highlight.preview(of: agent.preview)
            var highlight = LiveActivityContentState.Highlight(
                agent,
                status: status,
                since: entry.since,
                prompt: input.prompts[agent.id],
                titleLimit: titleLimit,
                showsProgress: request == nil
            )
            highlight.outcome = outcome(of: agent.id, decision: input.decisions[agent.id], preview: preview, hasRequest: request != nil)?.rawValue
            snapshots[agent.id] = AgentActivitySnapshot(
                agent: highlight,
                pending: request.map { LiveActivityContentState.Pending($0) },
                status: status
            )
            let observation = Observation(status: status, preview: preview, requestId: request?.id)
            observed[agent.id] = observation
            record(observation, since: observations[agent.id], of: agent.id, at: now)
        }
        herdrStatuses = Dictionary(uniqueKeysWithValues: tracked.keys.map { ($0, input.herdrStatuses[$0] ?? Self.agentStatus(of: $0, in: input)) })
        entries = tracked
        observations = observed
        outcomes = outcomes.filter { tracked[$0.key] != nil }
        eventGenerations = eventGenerations.filter { tracked[$0.key] != nil }
        eventDates = eventDates.filter { tracked[$0.key] != nil }
        holds = holds.filter { tracked[$0.key] != nil }
        lastBlockedAlerts = lastBlockedAlerts.filter { tracked[$0.key] != nil && now.timeIntervalSince($0.value) < timing.blockedAlertWindow }
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

    private mutating func publishedStatus(of agentId: AgentID, current: AgentStatus, hasPending: Bool, at now: Date) -> AgentStatus {
        guard let previous = observations[agentId]?.status else {
            holds[agentId] = nil
            return current
        }
        let delay: TimeInterval
        if previous.isBusy, !current.isBusy {
            delay = timing.turnDoneCooldown
        } else if current == .blocked, !hasPending, previous != .blocked {
            delay = timing.blockedGrace
        } else {
            if let held = holds.removeValue(forKey: agentId), !held.status.isBusy, current.isBusy {
                cancelledTurnsDone.append(agentId)
            }
            return current
        }
        if holds[agentId]?.status != current {
            holds[agentId] = Hold(status: current, since: now, delay: delay)
        }
        guard let hold = holds[agentId], hold.deadline.timeIntervalSince(now) <= Self.tolerance else { return previous }
        holds[agentId] = nil
        return current
    }

    private mutating func outcome(of agentId: AgentID, decision: PendingDecision?, preview: String?, hasRequest: Bool) -> PendingOutcome? {
        if let decision, decision.requestId != outcomes[agentId]?.requestId {
            outcomes[agentId] = ShownOutcome(requestId: decision.requestId, outcome: decision.outcome, preview: preview)
        }
        guard let shown = outcomes[agentId], shown.isActive else { return nil }
        guard !hasRequest, shown.preview == preview else {
            outcomes[agentId]?.isActive = false
            return nil
        }
        return shown.outcome
    }

    private mutating func record(_ observation: Observation, since previous: Observation?, of agentId: AgentID, at now: Date) {
        if observation != previous, previous != nil || observation.status.isBusy {
            eventGenerations[agentId] = generation
            eventDates[agentId] = now
        }
        if let kind = Self.alert(observation, since: previous), !isRepeatedBlock(kind, of: agentId, observation: observation, at: now) {
            alerts[agentId] = AgentFeedAlert(generation: generation, kind: kind, at: now, requestId: kind == .needsInput ? observation.requestId : nil)
        } else if let alert = alerts[agentId], !alert.isValid(for: observation.status) {
            alerts[agentId] = nil
        }
    }

    private mutating func isRepeatedBlock(_ kind: PushAlertKind, of agentId: AgentID, observation: Observation, at now: Date) -> Bool {
        guard kind == .needsInput, observation.requestId == nil else { return false }
        if let last = lastBlockedAlerts[agentId], now.timeIntervalSince(last) < timing.blockedAlertWindow {
            return true
        }
        lastBlockedAlerts[agentId] = now
        return false
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

    private static func agentStatus(of agentId: AgentID, in input: LiveActivityInput) -> AgentStatus {
        input.agents.first { $0.id == agentId }?.status ?? .unknown
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
