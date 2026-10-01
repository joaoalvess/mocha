import Foundation
import MochaProtocol
import os

let liveActivityLogger = Logger(subsystem: "com.joaoalves.mocha", category: "liveactivity")

public enum LiveActivityRegistrationError: Error, Sendable, Equatable {
    case invalidToken
}

public actor LiveActivityService: LiveActivityRegistering, LiveActivityCardHolding {
    struct Card: Sendable, Equatable {
        var activityId: String?
        var updateToken: String?
        var environment: ApnsEnvironment
        var startedAt: Date
        var sent: AgentActivitySnapshot?
        var sentAt: Date?
    }

    struct Device: Sendable {
        var pushToStart: ApnsRegistration?
        var card: Card?
        var focus: AgentID?
        var starts: [Date] = []
        var retryAt: Date?
        var isSending = false
        var isDismissed = false
        var retired: [String] = []
        var alerted: [AgentID: Int] = [:]
        var pushedAfter = 0
        var preferences = DevicePreferences()

        var isReady: Bool {
            !isSending && retryAt == nil
        }

        var hasUpdateToken: Bool {
            card?.updateToken != nil
        }

        func isRetired(_ registration: LiveActivityRegistration) -> Bool {
            guard let token = registration.updateToken else { return false }
            return retired.contains(token) || registration.activityId.map { retired.contains($0) } == true
        }

        mutating func retire(_ card: Card) {
            retired.append(contentsOf: [card.updateToken, card.activityId].compactMap { $0 })
            retired = Array(retired.suffix(LiveActivityService.retiredLimit))
        }

        mutating func loseCard(at generation: Int) {
            card = nil
            pushedAfter = generation
        }
    }

    struct Stored: Sendable, Equatable {
        var pushToStart: LiveActivityRegistration?
        var feedActivity: LiveActivityRegistration?
    }

    private struct Update {
        let snapshot: AgentActivitySnapshot
        let alert: AgentFeedAlert?
        let priority: ApnsPriority
        let skipsTheLimit: Bool
    }

    private struct SentAlert: Sendable {
        let agentId: AgentID
        let generation: Int
        let previous: Int?
    }

    private enum Sent {
        case start(AgentActivitySnapshot, environment: ApnsEnvironment, at: Date)
        case update(AgentActivitySnapshot, token: String, at: Date, alert: SentAlert?)
        case end(token: String, activityId: String?)
    }

    private enum Outcome {
        case delivery(LiveActivityDelivery)
        case deviceGone
    }

    private enum Lookup {
        case paired(DevicePreferences?)
        case gone
    }

    private struct Wake {
        let id: UUID
        let deadline: Date
        let task: Task<Void, Never>
    }

    private static let tolerance: TimeInterval = 0.001
    static let retiredLimit = 64

    private let devices: DeviceStore
    private let sender: any LiveActivityPushSending
    private let clock: any GatewayClock
    private let configuration: LiveActivityConfiguration
    private let presence: PresenceMonitor?

    private var tracker: AgentActivityTracker
    private var snapshots: [AgentID: AgentActivitySnapshot] = [:]
    private var lastInput: LiveActivityInput?
    private var foreground: Set<DeviceID> = []
    private var foregroundAgents: [DeviceID: AgentID] = [:]
    private var states: [DeviceID: Device] = [:]
    private var wake: Wake?
    private var sends: [UUID: Task<Void, Never>] = [:]
    private var inputTask: Task<Void, Never>?
    private var alertHandoff: (any LiveActivityAlertHandoff)?
    private var lock: ConsoleLock = .unknown
    private var presenceTask: Task<Void, Never>?
    private var shadowSilenced: [AgentID: AgentFeedAlert] = [:]
    private var isShutDown = false

    public init(
        devices: DeviceStore,
        sender: any LiveActivityPushSending,
        clock: any GatewayClock = SystemGatewayClock(),
        configuration: LiveActivityConfiguration = LiveActivityConfiguration(),
        presence: PresenceMonitor? = nil
    ) {
        self.devices = devices
        self.sender = sender
        self.clock = clock
        self.configuration = configuration
        self.presence = presence
        tracker = AgentActivityTracker(timing: configuration.timing)
    }

    public func start(inputs: AsyncStream<LiveActivityInput>) async {
        guard inputTask == nil, !isShutDown else { return }
        await loadRegistrations()
        if let presence {
            lock = await presence.current()
            let transitions = await presence.transitions()
            presenceTask = Task { [weak self] in
                for await lock in transitions {
                    guard let self else { break }
                    await self.presenceChanged(to: lock)
                }
            }
        }
        inputTask = Task { [weak self] in
            for await input in inputs {
                guard let self else { break }
                await self.apply(input)
            }
        }
    }

    public func shutdown() async {
        isShutDown = true
        inputTask?.cancel()
        inputTask = nil
        presenceTask?.cancel()
        presenceTask = nil
        wake?.task.cancel()
        wake = nil
        let running = Array(sends.values)
        for task in running {
            await task.value
        }
        sends.removeAll()
    }

    public func apply(_ input: LiveActivityInput) {
        guard !isShutDown else { return }
        lastInput = input
        foreground = input.foregroundDevices
        foregroundAgents = input.foregroundAgents
        track(input, at: clock.now())
        evaluate()
    }

    public func cardDevices() -> Set<DeviceID> {
        Set(states.filter { $0.value.hasUpdateToken }.keys)
    }

    public func attachAlertHandoff(_ handoff: any LiveActivityAlertHandoff) {
        alertHandoff = handoff
    }

    public func preferencesChanged(_ preferences: DevicePreferences, for deviceId: DeviceID) {
        guard states[deviceId] != nil else { return }
        states[deviceId]?.preferences = preferences
        evaluate()
    }

    public func register(_ registration: LiveActivityRegistration, from deviceId: DeviceID) async throws {
        let registration = try Self.normalized(registration)
        let storedPreferences = states[deviceId] == nil ? await Self.preferences(of: deviceId, in: devices) : nil
        guard !isShutDown else { return }
        var device = states[deviceId] ?? Device(
            alerted: tracker.alerts.mapValues(\.generation),
            preferences: storedPreferences ?? DevicePreferences()
        )
        var lost: [LiveActivityLostAlert] = []
        if let ended = registration.endedActivityId {
            if let card = device.card, card.activityId == ended {
                liveActivityLogger.info("the card on device \(deviceId, privacy: .public) ended on the iPhone")
                device.retire(card)
                lost = takePendingAlerts(of: &device, id: deviceId)
                device.loseCard(at: tracker.generation)
                device.isDismissed = true
            } else if !device.retired.contains(ended) {
                device.retired = Array((device.retired + [ended]).suffix(Self.retiredLimit))
            }
        }
        if let token = registration.pushToStartToken {
            device.pushToStart = ApnsRegistration(token: token, env: registration.env)
        } else if device.pushToStart?.env != registration.env {
            device.pushToStart = nil
        }
        if let token = registration.updateToken, registration.agentId == nil, !device.isRetired(registration) {
            device.card = adopt(registration, token: token, into: device.card)
            device.isDismissed = false
        }
        for id in Array(states.keys) where id != deviceId {
            release(registration, from: id)
        }
        states[deviceId] = device
        handOff(lost, on: deviceId)
        let stored = Self.stored(device)
        if try await devices.setLiveActivities(pushToStart: stored.pushToStart, feedActivity: stored.feedActivity, for: deviceId) == false {
            liveActivityLogger.error("ignored a live activity registration from unknown device \(deviceId, privacy: .public)")
            states[deviceId] = nil
            return
        }
        evaluate()
    }

    var nextWake: Date? {
        wake?.deadline
    }

    var holder: AgentID? {
        tracker.holder
    }

    func focus(on deviceId: DeviceID) -> AgentID? {
        states[deviceId]?.focus
    }

    func waitForSends() async {
        while let task = sends.values.first {
            await task.value
        }
    }

    private func loadRegistrations() async {
        let records: [DeviceRecord]
        do {
            records = try await devices.devices()
        } catch {
            liveActivityLogger.error("failed to read devices: \(PushService.describe(error), privacy: .public)")
            return
        }
        let now = clock.now()
        for record in records where states[record.id] == nil {
            var device = Device(preferences: record.preferences)
            if let registration = record.liveActivity.flatMap({ try? Self.normalized($0) }) {
                device.pushToStart = registration.pushToStartToken.map { ApnsRegistration(token: $0, env: registration.env) }
            }
            if let registration = record.feedActivity.flatMap({ try? Self.normalized($0) }), registration.agentId == nil, let token = registration.updateToken {
                device.card = Card(activityId: registration.activityId, updateToken: token, environment: registration.env, startedAt: now)
            }
            guard device.pushToStart != nil || device.card != nil else { continue }
            states[record.id] = device
        }
        evaluate()
    }

    private func adopt(_ registration: LiveActivityRegistration, token: String, into current: Card?) -> Card {
        guard var card = current else {
            return Card(activityId: registration.activityId, updateToken: token, environment: registration.env, startedAt: clock.now())
        }
        let sameActivity = card.updateToken == token
            || card.updateToken == nil
            || (registration.activityId != nil && registration.activityId == card.activityId)
        guard sameActivity else {
            return Card(activityId: registration.activityId, updateToken: token, environment: registration.env, startedAt: clock.now())
        }
        card.activityId = registration.activityId ?? card.activityId
        card.updateToken = token
        card.environment = registration.env
        return card
    }

    private func release(_ registration: LiveActivityRegistration, from id: DeviceID) {
        guard var device = states[id] else { return }
        if let token = registration.pushToStartToken, device.pushToStart?.token == token {
            device.pushToStart = nil
        }
        if let token = registration.updateToken, registration.agentId == nil, device.card?.updateToken == token {
            device.loseCard(at: tracker.generation)
        }
        states[id] = device
    }

    private func track(_ input: LiveActivityInput, at now: Date) {
        snapshots = tracker.snapshots(of: input, at: now, titleLimit: configuration.titleLimit)
        logShadowAlerts(at: now)
    }

    private func logShadowAlerts(at now: Date) {
        for agentId in tracker.cancelledTurnsDone {
            liveActivityLogger.notice(
                "shadow alert turnDone of \(agentId, privacy: .public) gen=\(self.tracker.generation, privacy: .public) would=cancelled"
            )
        }
        let channel = states.values.contains { $0.hasUpdateToken } ? "card" : "push"
        for (agentId, alert) in tracker.alerts.sorted(by: { $0.key < $1.key }) where alert.generation == tracker.generation {
            let would = lock.isAtMac ? "silent" : "ring"
            if lock.isAtMac {
                shadowSilenced[agentId] = alert
            }
            liveActivityLogger.notice(
                "shadow alert \(alert.kind.rawValue, privacy: .public) of \(agentId, privacy: .public) gen=\(alert.generation, privacy: .public) channel=\(channel, privacy: .public) lock=\(self.lock.rawValue, privacy: .public) would=\(would, privacy: .public)"
            )
        }
    }

    private func presenceChanged(to newLock: ConsoleLock) {
        let wasAtMac = lock.isAtMac
        lock = newLock
        guard wasAtMac, !newLock.isAtMac else {
            if newLock.isAtMac {
                shadowSilenced.removeAll()
            }
            return
        }
        let candidate = shadowSilenced
            .filter { isUnseen($0.value, of: $0.key) }
            .max { shadowUrgency($0.value, of: $0.key) < shadowUrgency($1.value, of: $1.key) }
        shadowSilenced.removeAll()
        if let candidate {
            liveActivityLogger.notice("shadow lock-ring \(candidate.key, privacy: .public) \(candidate.value.kind.rawValue, privacy: .public)")
        } else {
            liveActivityLogger.notice("shadow lock-ring none")
        }
    }

    private func isUnseen(_ alert: AgentFeedAlert, of agentId: AgentID) -> Bool {
        guard tracker.alerts[agentId]?.generation == alert.generation else { return false }
        switch alert.kind {
        case .needsInput: return snapshots[agentId]?.isBlocked == true
        case .turnDone: return tracker.herdrStatuses[agentId] == .done
        }
    }

    private func shadowUrgency(_ alert: AgentFeedAlert, of agentId: AgentID) -> (Int, Int) {
        let rank = switch alert.kind {
        case .needsInput: alert.requestId == nil ? 1 : 2
        case .turnDone: 0
        }
        return (rank, alert.generation)
    }

    private func rings(_ alert: AgentFeedAlert, of agentId: AgentID, on device: Device, id: DeviceID) -> Bool {
        foregroundAgents[id] != agentId && (alert.kind != .turnDone || device.preferences.turnDoneAlerts)
    }

    private func settle(_ device: inout Device, id: DeviceID) {
        for (agentId, alert) in tracker.alerts where alert.generation > device.alerted[agentId] ?? 0 {
            let isLeftToThePush = !device.hasUpdateToken && alert.generation > device.pushedAfter
            if isLeftToThePush || !rings(alert, of: agentId, on: device, id: id) {
                device.alerted[agentId] = alert.generation
            }
        }
    }

    private func pendingAlerts(of device: Device) -> [(agentId: AgentID, alert: AgentFeedAlert)] {
        tracker.alerts
            .filter { $0.value.generation > device.alerted[$0.key] ?? 0 && snapshots[$0.key] != nil }
            .map { (agentId: $0.key, alert: $0.value) }
            .sorted { ($0.alert.generation, $0.agentId) < ($1.alert.generation, $1.agentId) }
    }

    private func takePendingAlerts(of device: inout Device, id: DeviceID) -> [LiveActivityLostAlert] {
        var lost: [LiveActivityLostAlert] = []
        for (agentId, alert) in pendingAlerts(of: device) {
            device.alerted[agentId] = alert.generation
            guard rings(alert, of: agentId, on: device, id: id), let snapshot = snapshots[agentId] else { continue }
            let content = snapshot.alertContent(alert.kind)
            lost.append(LiveActivityLostAlert(agentId: agentId, kind: alert.kind, requestId: alert.requestId, title: content.title, body: content.body))
        }
        return lost
    }

    private func handOff(_ lost: [LiveActivityLostAlert], on id: DeviceID) {
        guard !lost.isEmpty, let handoff = alertHandoff else { return }
        liveActivityLogger.notice("handed \(lost.count, privacy: .public) alerts of the lost card on device \(id, privacy: .public) to the notifications")
        let taskId = UUID()
        sends[taskId] = Task { [weak self] in
            await handoff.cardLost(lost, on: id)
            await self?.handOffFinished(taskId)
        }
    }

    private func handOffFinished(_ taskId: UUID) {
        sends[taskId] = nil
    }

    private func focus(for device: Device) -> AgentID? {
        if let holder = tracker.holder, snapshots[holder] != nil {
            return holder
        }
        if let queued = pendingAlerts(of: device).first(where: { $0.alert.requestId == nil }) {
            return queued.agentId
        }
        return tracker.focus(among: snapshots, current: device.focus ?? device.card?.sent?.agent.agentId)
    }

    private var anyBusy: Bool {
        snapshots.values.contains { $0.isBusy }
    }

    private func evaluate() {
        guard lastInput != nil, !isShutDown else { return }
        let now = clock.now()
        for id in states.keys.sorted() {
            evaluate(id, at: now)
        }
        scheduleWake(at: now)
    }

    private func evaluate(_ id: DeviceID, at now: Date) {
        guard var device = states[id] else { return }
        device.starts.removeAll { isDue($0.addingTimeInterval(configuration.pushToStartWindow), at: now) }
        if let retryAt = device.retryAt, isDue(retryAt, at: now) {
            device.retryAt = nil
        }
        if !anyBusy {
            device.isDismissed = false
        }
        settle(&device, id: id)
        device.focus = focus(for: device)
        states[id] = device
        guard device.isReady else { return }
        if device.card != nil {
            evaluateCard(on: id, at: now)
        }
        if let device = states[id], device.card == nil, device.isReady {
            startCard(on: id, at: now)
        }
    }

    private func evaluateCard(on id: DeviceID, at now: Date) {
        guard let device = states[id], let card = device.card else { return }
        let shouldEnd = isIdle(card, at: now) || isExpired(card, at: now)
        guard let token = card.updateToken else {
            if shouldEnd {
                liveActivityLogger.info("gave up waiting for the update token of the card on device \(id, privacy: .public)")
                states[id]?.card = nil
            }
            return
        }
        let pending = pendingUpdate(for: device, card: card)
        guard isOpen(card, for: pending, at: now) else { return }
        guard !shouldEnd || pending?.alert != nil else {
            end(token: token, card: card, on: id, at: now)
            return
        }
        guard let update = pending ?? refresh(for: device, card: card, at: now) else { return }
        let snapshot = update.snapshot
        let alertKind = update.alert?.kind
        let push = snapshot.push({ .update(alert: alertKind.map($0.alertContent)) }, at: now, staleDate: now.addingTimeInterval(configuration.staleInterval))
        let focus = snapshot.agent.agentId
        var sentAlert: SentAlert?
        if let alert = update.alert {
            sentAlert = SentAlert(agentId: focus, generation: alert.generation, previous: device.alerted[focus])
            states[id]?.alerted[focus] = alert.generation
        }
        let lag = tracker.eventDates[focus].map { now.timeIntervalSince($0) } ?? 0
        liveActivityLogger.notice(
            "card update of \(focus, privacy: .public) p\(update.priority.rawValue, privacy: .public) alert=\(alertKind?.rawValue ?? "none", privacy: .public) lag=\(String(format: "%.1f", lag), privacy: .public)"
        )
        let sent = Sent.update(snapshot, token: token, at: now, alert: sentAlert)
        send(push, as: sent, alertKind: alertKind, to: token, environment: card.environment, priority: update.priority, device: id)
    }

    private func isOpen(_ card: Card, for update: Update?, at now: Date) -> Bool {
        guard let sentAt = card.sentAt else { return true }
        if isDue(sentAt.addingTimeInterval(configuration.updateInterval), at: now) {
            return true
        }
        return update?.skipsTheLimit == true && isDue(sentAt.addingTimeInterval(configuration.minimumAlertGap), at: now)
    }

    private func pendingUpdate(for device: Device, card: Card) -> Update? {
        guard let focus = device.focus, let snapshot = snapshots[focus] else { return nil }
        if let alert = tracker.alerts[focus], alert.generation > device.alerted[focus] ?? 0 {
            let isHeldRequest = alert.requestId != nil && focus == tracker.holder
            return Update(snapshot: snapshot, alert: alert, priority: .high, skipsTheLimit: isHeldRequest)
        }
        guard let priority = snapshot.priority(since: card.sent) else { return nil }
        return Update(snapshot: snapshot, alert: nil, priority: priority, skipsTheLimit: false)
    }

    private func refresh(for device: Device, card: Card, at now: Date) -> Update? {
        guard anyBusy, let sentAt = card.sentAt, isDue(sentAt.addingTimeInterval(configuration.refreshInterval), at: now),
              let snapshot = device.focus.flatMap({ snapshots[$0] }) ?? card.sent
        else { return nil }
        return Update(snapshot: snapshot, alert: nil, priority: .low, skipsTheLimit: false)
    }

    private func end(token: String, card: Card, on id: DeviceID, at now: Date) {
        let focus = states[id]?.focus
        let snapshot = (focus.flatMap { snapshots[$0] } ?? card.sent ?? .gone(focus ?? "", at: now)).ended
        let dismissalDate = now.addingTimeInterval(configuration.dismissalDelay)
        let push = snapshot.push({ _ in .end(dismissalDate: dismissalDate) }, at: now, staleDate: nil)
        send(push, as: .end(token: token, activityId: card.activityId), alertKind: nil, to: token, environment: card.environment, priority: .high, device: id)
    }

    private func startCard(on id: DeviceID, at now: Date) {
        guard let device = states[id], canStart(device, id: id), hasStartBudget(device), let pushToStart = device.pushToStart,
              let snapshot = device.focus.flatMap({ snapshots[$0] })
        else { return }
        let push = snapshot.push({ .start(alert: $0.startAlert) }, at: now, staleDate: now.addingTimeInterval(configuration.staleInterval))
        send(
            push,
            as: .start(snapshot, environment: pushToStart.env, at: now),
            alertKind: nil,
            to: pushToStart.token,
            environment: pushToStart.env,
            priority: .high,
            device: id
        )
    }

    private func canStart(_ device: Device, id: DeviceID) -> Bool {
        device.card == nil && device.pushToStart != nil && !device.isDismissed && !foreground.contains(id) && anyBusy
    }

    private func isIdle(_ card: Card, at now: Date) -> Bool {
        guard !anyBusy else { return false }
        return isDue(idleDeadline(of: card), at: now)
    }

    private func idleDeadline(of card: Card) -> Date {
        max(tracker.lastBusyAt ?? card.startedAt, card.startedAt).addingTimeInterval(configuration.idleTimeout)
    }

    private func isExpired(_ card: Card, at now: Date) -> Bool {
        isDue(card.startedAt.addingTimeInterval(configuration.renewalAge), at: now)
    }

    private func hasStartBudget(_ device: Device) -> Bool {
        device.starts.count < configuration.pushToStartLimit
    }

    private func send(
        _ push: AgentActivityPush,
        as sent: Sent,
        alertKind: PushAlertKind?,
        to token: String,
        environment: ApnsEnvironment,
        priority: ApnsPriority,
        device id: DeviceID
    ) {
        states[id]?.isSending = true
        let taskId = UUID()
        let sender = sender
        let devices = devices
        sends[taskId] = Task { [weak self] in
            let outcome: Outcome
            switch await Self.lookup(id, in: devices) {
            case .gone:
                outcome = .deviceGone
            case .paired(let preferences):
                var push = push
                if alertKind == .turnDone, preferences?.turnDoneAlerts == false {
                    push.event = .update(alert: nil)
                }
                outcome = .delivery(await sender.sendLiveActivity(push, to: token, environment: environment, priority: priority))
            }
            await self?.finish(sent, outcome: outcome, device: id, taskId: taskId)
        }
    }

    private static func restore(_ alert: SentAlert, on device: inout Device) {
        guard device.alerted[alert.agentId] == alert.generation else { return }
        device.alerted[alert.agentId] = alert.previous
    }

    private static func preferences(of id: DeviceID, in devices: DeviceStore) async -> DevicePreferences? {
        guard case .paired(let preferences) = await lookup(id, in: devices) else { return nil }
        return preferences
    }

    private static func lookup(_ id: DeviceID, in devices: DeviceStore) async -> Lookup {
        do {
            guard let record = try await devices.devices().first(where: { $0.id == id }) else { return .gone }
            return .paired(record.preferences)
        } catch {
            liveActivityLogger.error("failed to read devices: \(PushService.describe(error), privacy: .public)")
            return .paired(nil)
        }
    }

    private func finish(_ sent: Sent, outcome: Outcome, device id: DeviceID, taskId: UUID) async {
        defer { sends[taskId] = nil }
        guard !isShutDown, var device = states[id] else { return }
        device.isSending = false
        guard case .delivery(let delivery) = outcome else {
            liveActivityLogger.info("dropped the live activity of removed device \(id, privacy: .public)")
            states[id] = nil
            evaluate()
            return
        }
        let before = Self.stored(device)
        let now = clock.now()
        var lost: [LiveActivityLostAlert] = []
        switch (sent, delivery) {
        case (_, .failed(let retryable)):
            device.retryAt = now.addingTimeInterval(retryable ? configuration.retryDelay : configuration.configurationRetryDelay)
            if case .update(_, let token, _, let alert?) = sent, device.card?.updateToken == token {
                Self.restore(alert, on: &device)
            }
        case (.start(let snapshot, let environment, let at), .delivered):
            liveActivityLogger.info("started the card of \(snapshot.agent.agentId, privacy: .public) on device \(id, privacy: .public) by push-to-start")
            device.starts.append(at)
            if device.card == nil {
                device.card = Card(environment: environment, startedAt: at, sent: snapshot, sentAt: at)
            }
        case (.start, .invalidToken):
            liveActivityLogger.info("APNs refused the push-to-start token of device \(id, privacy: .public)")
            device.pushToStart = nil
        case (.update(let snapshot, let token, let at, _), .delivered):
            if var card = device.card, card.updateToken == token {
                card.sent = snapshot
                card.sentAt = at
                device.card = card
            }
        case (.update(_, let token, _, let alert), .invalidToken):
            liveActivityLogger.info("APNs refused the update token of the card on device \(id, privacy: .public)")
            if device.card?.updateToken == token {
                if let alert {
                    Self.restore(alert, on: &device)
                }
                lost = takePendingAlerts(of: &device, id: id)
                device.loseCard(at: tracker.generation)
                device.isDismissed = true
            }
        case (.end(let token, let activityId), .delivered), (.end(let token, let activityId), .invalidToken):
            liveActivityLogger.info("ended the card on device \(id, privacy: .public)")
            device.retired.append(contentsOf: [token] + (activityId.map { [$0] } ?? []))
            device.retired = Array(device.retired.suffix(Self.retiredLimit))
            if device.card?.updateToken == token {
                device.loseCard(at: tracker.generation)
            }
        }
        states[id] = device
        let after = Self.stored(device)
        if after != before {
            do {
                _ = try await devices.setLiveActivities(pushToStart: after.pushToStart, feedActivity: after.feedActivity, for: id)
            } catch {
                liveActivityLogger.error("failed to save the live activity of device \(id, privacy: .public): \(PushService.describe(error), privacy: .public)")
            }
        }
        handOff(lost, on: id)
        evaluate()
    }

    private func scheduleWake(at now: Date) {
        let deadlines = states.compactMap { nextDeadline(for: $0.value, id: $0.key, at: now) } + [tracker.holdDeadline].compactMap { $0 }
        let deadline = deadlines.min()
        if let wake, let deadline, abs(wake.deadline.timeIntervalSince(deadline)) < Self.tolerance {
            return
        }
        wake?.task.cancel()
        wake = nil
        guard let deadline else { return }
        let milliseconds = Int64((max(0, deadline.timeIntervalSince(now)) * 1000).rounded())
        let id = UUID()
        let clock = clock
        let task = Task { [weak self] in
            guard (try? await clock.sleep(for: .milliseconds(milliseconds))) != nil else { return }
            await self?.wakeFired(id)
        }
        wake = Wake(id: id, deadline: deadline, task: task)
    }

    private func wakeFired(_ id: UUID) {
        guard wake?.id == id else { return }
        wake = nil
        let now = clock.now()
        if let lastInput, let hold = tracker.holdDeadline, isDue(hold, at: now) {
            track(lastInput, at: now)
        }
        evaluate()
    }

    private func nextDeadline(for device: Device, id: DeviceID, at now: Date) -> Date? {
        guard !device.isSending else { return nil }
        let deadline: Date?
        if let card = device.card {
            deadline = nextDeadline(for: card, of: device, at: now)
        } else if canStart(device, id: id), device.focus != nil {
            deadline = hasStartBudget(device) ? now : device.starts.min()?.addingTimeInterval(configuration.pushToStartWindow) ?? now
        } else {
            deadline = nil
        }
        guard let deadline else { return nil }
        return device.retryAt.map { max($0, deadline) } ?? deadline
    }

    private func nextDeadline(for card: Card, of device: Device, at now: Date) -> Date? {
        var candidates = [card.startedAt.addingTimeInterval(configuration.renewalAge)]
        if !anyBusy {
            candidates.append(idleDeadline(of: card))
        }
        guard card.updateToken != nil else { return candidates.min() }
        let gate = card.sentAt.map { $0.addingTimeInterval(configuration.updateInterval) } ?? now
        let update = pendingUpdate(for: device, card: card)
        if update != nil {
            candidates.append(gate)
        }
        if anyBusy, let sentAt = card.sentAt {
            candidates.append(sentAt.addingTimeInterval(configuration.refreshInterval))
        }
        let limited = candidates.min().map { max($0, gate) }
        guard update?.skipsTheLimit == true else { return limited }
        let early = card.sentAt.map { $0.addingTimeInterval(configuration.minimumAlertGap) } ?? now
        return limited.map { min($0, early) } ?? early
    }

    private func isDue(_ deadline: Date, at now: Date) -> Bool {
        deadline.timeIntervalSince(now) <= Self.tolerance
    }

    private static func normalized(_ registration: LiveActivityRegistration) throws -> LiveActivityRegistration {
        let pushToStart = try registration.pushToStartToken.map(validToken)
        let update = try registration.updateToken.map(validToken)
        let activityId = registration.activityId.flatMap { $0.isEmpty ? nil : $0 }
        let agentId = registration.agentId.flatMap { $0.isEmpty ? nil : $0 }
        let endedActivityId = registration.endedActivityId.flatMap { $0.isEmpty ? nil : $0 }
        return LiveActivityRegistration(
            pushToStartToken: pushToStart,
            activityId: activityId,
            updateToken: update,
            agentId: agentId,
            env: registration.env,
            endedActivityId: endedActivityId
        )
    }

    private static func validToken(_ token: String) throws -> String {
        guard ApnsRequest.isValidDeviceToken(token) else { throw LiveActivityRegistrationError.invalidToken }
        return token.lowercased()
    }

    static func stored(_ device: Device) -> Stored {
        Stored(
            pushToStart: device.pushToStart.map { LiveActivityRegistration(pushToStartToken: $0.token, env: $0.env) },
            feedActivity: device.card.flatMap { card in
                card.updateToken.map { LiveActivityRegistration(activityId: card.activityId, updateToken: $0, env: card.environment) }
            }
        )
    }
}

