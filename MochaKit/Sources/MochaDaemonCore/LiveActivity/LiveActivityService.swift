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
        var alerted: [AgentID: Int] = [:]
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

        var isReady: Bool {
            !isSending && retryAt == nil
        }

        func isRetired(_ registration: LiveActivityRegistration) -> Bool {
            guard let token = registration.updateToken else { return false }
            return retired.contains(token) || registration.activityId.map { retired.contains($0) } == true
        }
    }

    struct Stored: Sendable, Equatable {
        var pushToStart: LiveActivityRegistration?
        var feedActivity: LiveActivityRegistration?
    }

    private struct Update {
        let snapshot: AgentActivitySnapshot
        let alertKind: PushAlertKind?
        let priority: ApnsPriority
    }

    private struct RetriedAlert: Sendable {
        let agentId: AgentID
        let generation: Int?
    }

    private enum Sent {
        case start(AgentActivitySnapshot, environment: ApnsEnvironment, at: Date)
        case update(AgentActivitySnapshot, token: String, at: Date, retriedAlert: RetriedAlert?)
        case end(token: String, activityId: String?)
    }

    private enum Outcome {
        case delivery(LiveActivityDelivery)
        case deviceGone
    }

    private enum Lookup {
        case paired(DevicePreferences)
        case gone
    }

    private struct Wake {
        let id: UUID
        let deadline: Date
        let task: Task<Void, Never>
    }

    private static let tolerance: TimeInterval = 0.001
    private static let retiredLimit = 64

    private let devices: DeviceStore
    private let sender: any LiveActivityPushSending
    private let clock: any GatewayClock
    private let configuration: LiveActivityConfiguration

    private var tracker = AgentActivityTracker()
    private var snapshots: [AgentID: AgentActivitySnapshot] = [:]
    private var hasInput = false
    private var foreground: Set<DeviceID> = []
    private var states: [DeviceID: Device] = [:]
    private var wake: Wake?
    private var sends: [UUID: Task<Void, Never>] = [:]
    private var inputTask: Task<Void, Never>?
    private var alertFallback: (any LiveActivityAlertFallback)?
    private var isShutDown = false

    public init(
        devices: DeviceStore,
        sender: any LiveActivityPushSending,
        clock: any GatewayClock = SystemGatewayClock(),
        configuration: LiveActivityConfiguration = LiveActivityConfiguration()
    ) {
        self.devices = devices
        self.sender = sender
        self.clock = clock
        self.configuration = configuration
    }

    public func start(inputs: AsyncStream<LiveActivityInput>) async {
        guard inputTask == nil, !isShutDown else { return }
        await loadRegistrations()
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
        hasInput = true
        foreground = input.foregroundDevices
        snapshots = tracker.snapshots(of: input, at: clock.now(), titleLimit: configuration.titleLimit)
        settleAlertsOutsideTheCard()
        evaluate()
    }

    public func cardHolder() -> AgentID? {
        tracker.holder
    }

    public func attachAlertFallback(_ fallback: any LiveActivityAlertFallback) {
        alertFallback = fallback
    }

    public func register(_ registration: LiveActivityRegistration, from deviceId: DeviceID) async throws {
        let registration = try Self.normalized(registration)
        guard !isShutDown else { return }
        var device = states[deviceId] ?? Device()
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
        let stored = Self.stored(device)
        if try await devices.setLiveActivities(pushToStart: stored.pushToStart, feedActivity: stored.feedActivity, for: deviceId) == false {
            liveActivityLogger.error("ignored a live activity registration from unknown device \(deviceId, privacy: .public)")
            states[deviceId] = nil
        }
        evaluate()
    }

    var nextWake: Date? {
        wake?.deadline
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
            var device = Device()
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
            device.card = nil
        }
        states[id] = device
    }

    private func settleAlertsOutsideTheCard() {
        for id in states.keys.sorted() {
            guard var card = states[id]?.card else { continue }
            guard card.updateToken != nil else {
                for (agentId, alert) in tracker.alerts {
                    card.alerted[agentId] = max(card.alerted[agentId] ?? 0, alert.generation)
                }
                states[id]?.card = card
                continue
            }
            for dropped in tracker.droppedAlerts {
                report(dropped.alert, of: dropped.agentId, on: id, card: &card, wasShown: false)
            }
            if let holder = tracker.holder {
                for (agentId, alert) in tracker.alerts where agentId != holder {
                    report(alert, of: agentId, on: id, card: &card, wasShown: false)
                }
            }
            states[id]?.card = card
        }
    }

    private func reportUnshownAlerts(on id: DeviceID, card: inout Card, except shown: AgentID?) {
        for (agentId, alert) in tracker.alerts.sorted(by: { $0.key < $1.key }) where agentId != shown {
            report(alert, of: agentId, on: id, card: &card, wasShown: false)
        }
    }

    private func report(_ alert: AgentFeedAlert, of agentId: AgentID, on id: DeviceID, card: inout Card, wasShown: Bool) {
        guard alert.generation > card.alerted[agentId] ?? 0 else { return }
        card.alerted[agentId] = alert.generation
        guard let fallback = alertFallback else { return }
        let taskId = UUID()
        sends[taskId] = Task { [weak self] in
            await fallback.cardAlert(alert.kind, of: agentId, on: id, wasShown: wasShown)
            await self?.reportFinished(taskId)
        }
    }

    private func reportFinished(_ taskId: UUID) {
        sends[taskId] = nil
    }

    private var anyBusy: Bool {
        snapshots.values.contains { $0.isBusy }
    }

    private func evaluate() {
        guard hasInput, !isShutDown else { return }
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
        device.focus = tracker.focus(among: snapshots, current: device.focus ?? device.card?.sent?.agent.agentId)
        states[id] = device
        if var card = device.card, card.updateToken != nil, let focus = device.focus, let alert = tracker.alerts[focus], snapshots[focus] == card.sent {
            report(alert, of: focus, on: id, card: &card, wasShown: true)
            states[id]?.card = card
        }
        guard let device = states[id] else { return }
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
        if let sentAt = card.sentAt, !isDue(sentAt.addingTimeInterval(configuration.updateInterval), at: now) {
            return
        }
        guard !shouldEnd else {
            end(token: token, card: card, on: id, at: now)
            return
        }
        guard let update = pendingUpdate(for: device, id: id, card: card) ?? refresh(for: device, card: card, at: now) else { return }
        let snapshot = update.snapshot
        let alertKind = update.alertKind
        let push = snapshot.push({ .update(alert: alertKind.map($0.alertContent)) }, at: now, staleDate: now.addingTimeInterval(configuration.staleInterval))
        let focus = snapshot.agent.agentId
        let retriedAlert = alertKind.map { _ in RetriedAlert(agentId: focus, generation: card.alerted[focus]) }
        var reported = card
        if let alert = tracker.alerts[focus] {
            report(alert, of: focus, on: id, card: &reported, wasShown: alertKind != nil)
        }
        reportUnshownAlerts(on: id, card: &reported, except: focus)
        states[id]?.card = reported
        let sent = Sent.update(snapshot, token: token, at: now, retriedAlert: retriedAlert)
        send(push, as: sent, alertKind: alertKind, to: token, environment: card.environment, priority: update.priority, device: id)
    }

    private func pendingUpdate(for device: Device, id: DeviceID, card: Card) -> Update? {
        guard let snapshot = device.focus.flatMap({ snapshots[$0] }), snapshot != card.sent else { return nil }
        if let alert = tracker.alerts[snapshot.agent.agentId], alert.generation > card.alerted[snapshot.agent.agentId] ?? 0 {
            return Update(snapshot: snapshot, alertKind: foreground.contains(id) ? nil : alert.kind, priority: .high)
        }
        guard let priority = snapshot.priority(since: card.sent) else { return nil }
        return Update(snapshot: snapshot, alertKind: nil, priority: priority)
    }

    private func refresh(for device: Device, card: Card, at now: Date) -> Update? {
        guard anyBusy, let sentAt = card.sentAt, isDue(sentAt.addingTimeInterval(configuration.refreshInterval), at: now),
              let snapshot = device.focus.flatMap({ snapshots[$0] }) ?? card.sent
        else { return nil }
        return Update(snapshot: snapshot, alertKind: nil, priority: .low)
    }

    private func end(token: String, card: Card, on id: DeviceID, at now: Date) {
        let focus = states[id]?.focus
        let snapshot = (focus.flatMap { snapshots[$0] } ?? card.sent ?? .gone(focus ?? "", at: now)).ended
        let dismissalDate = now.addingTimeInterval(configuration.dismissalDelay)
        let push = snapshot.push({ _ in .end(dismissalDate: dismissalDate) }, at: now, staleDate: nil)
        var reported = card
        reportUnshownAlerts(on: id, card: &reported, except: nil)
        states[id]?.card = reported
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
                if alertKind == .turnDone, !preferences.turnDoneAlerts {
                    push.event = .update(alert: nil)
                }
                outcome = .delivery(await sender.sendLiveActivity(push, to: token, environment: environment, priority: priority))
            }
            await self?.finish(sent, outcome: outcome, device: id, taskId: taskId)
        }
    }

    private static func lookup(_ id: DeviceID, in devices: DeviceStore) async -> Lookup {
        do {
            guard let record = try await devices.devices().first(where: { $0.id == id }) else { return .gone }
            return .paired(record.preferences)
        } catch {
            liveActivityLogger.error("failed to read devices: \(PushService.describe(error), privacy: .public)")
            return .paired(DevicePreferences())
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
        switch (sent, delivery) {
        case (_, .failed(let retryable)):
            device.retryAt = now.addingTimeInterval(retryable ? configuration.retryDelay : configuration.configurationRetryDelay)
            if case .update(_, let token, _, let retriedAlert?) = sent, device.card?.updateToken == token {
                device.card?.alerted[retriedAlert.agentId] = retriedAlert.generation
            }
        case (.start(let snapshot, let environment, let at), .delivered):
            liveActivityLogger.info("started the card of \(snapshot.agent.agentId, privacy: .public) on device \(id, privacy: .public) by push-to-start")
            device.starts.append(at)
            if device.card == nil {
                device.card = Card(environment: environment, startedAt: at, sent: snapshot, sentAt: at, alerted: tracker.alerts.mapValues(\.generation))
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
        case (.update(_, let token, _, _), .invalidToken):
            liveActivityLogger.info("APNs refused the update token of the card on device \(id, privacy: .public)")
            if var card = device.card, card.updateToken == token {
                reportUnshownAlerts(on: id, card: &card, except: nil)
                device.card = nil
                device.isDismissed = true
            }
        case (.end(let token, let activityId), .delivered), (.end(let token, let activityId), .invalidToken):
            liveActivityLogger.info("ended the card on device \(id, privacy: .public)")
            device.retired.append(contentsOf: [token] + (activityId.map { [$0] } ?? []))
            device.retired = Array(device.retired.suffix(Self.retiredLimit))
            if device.card?.updateToken == token {
                device.card = nil
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
        evaluate()
    }

    private func scheduleWake(at now: Date) {
        let deadline = states.compactMap { nextDeadline(for: $0.value, id: $0.key, at: now) }.min()
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
        evaluate()
    }

    private func nextDeadline(for device: Device, id: DeviceID, at now: Date) -> Date? {
        guard !device.isSending else { return nil }
        let deadline: Date?
        if let card = device.card {
            deadline = nextDeadline(for: card, of: device, id: id, at: now)
        } else if canStart(device, id: id), device.focus != nil {
            deadline = hasStartBudget(device) ? now : device.starts.min()?.addingTimeInterval(configuration.pushToStartWindow) ?? now
        } else {
            deadline = nil
        }
        guard let deadline else { return nil }
        return device.retryAt.map { max($0, deadline) } ?? deadline
    }

    private func nextDeadline(for card: Card, of device: Device, id: DeviceID, at now: Date) -> Date? {
        var candidates = [card.startedAt.addingTimeInterval(configuration.renewalAge)]
        if !anyBusy {
            candidates.append(idleDeadline(of: card))
        }
        guard card.updateToken != nil else { return candidates.min() }
        let gate = card.sentAt.map { $0.addingTimeInterval(configuration.updateInterval) } ?? now
        if pendingUpdate(for: device, id: id, card: card) != nil {
            candidates.append(gate)
        }
        if anyBusy, let sentAt = card.sentAt {
            candidates.append(sentAt.addingTimeInterval(configuration.refreshInterval))
        }
        return candidates.min().map { max($0, gate) }
    }

    private func isDue(_ deadline: Date, at now: Date) -> Bool {
        deadline.timeIntervalSince(now) <= Self.tolerance
    }

    private static func normalized(_ registration: LiveActivityRegistration) throws -> LiveActivityRegistration {
        let pushToStart = try registration.pushToStartToken.map(validToken)
        let update = try registration.updateToken.map(validToken)
        let activityId = registration.activityId.flatMap { $0.isEmpty ? nil : $0 }
        let agentId = registration.agentId.flatMap { $0.isEmpty ? nil : $0 }
        return LiveActivityRegistration(pushToStartToken: pushToStart, activityId: activityId, updateToken: update, agentId: agentId, env: registration.env)
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
