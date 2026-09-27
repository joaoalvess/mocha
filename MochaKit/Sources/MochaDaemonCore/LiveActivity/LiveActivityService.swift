import Foundation
import MochaProtocol
import os

let liveActivityLogger = Logger(subsystem: "com.joaoalves.mocha", category: "liveactivity")

public enum LiveActivityRegistrationError: Error, Sendable, Equatable {
    case invalidToken
}

public actor LiveActivityService: LiveActivityRegistering {
    struct Activity: Sendable, Equatable {
        var activityId: String?
        var updateToken: String?
        var environment: ApnsEnvironment
        var startedAt: Date
        var sent: AgentActivitySnapshot?
        var sentAt: Date?
    }

    struct Device: Sendable {
        var pushToStart: ApnsRegistration?
        var activities: [AgentID: Activity] = [:]
        var starts: [Date] = []
        var retryAt: [AgentID: Date] = [:]
        var sending: Set<AgentID> = []
        var ending: Set<AgentID> = []
        var dismissed: Set<AgentID> = []
        var retired: [String] = []

        var startsInFlight: Int {
            sending.filter { activities[$0] == nil }.count
        }

        var occupied: Int {
            activities.count + startsInFlight
        }

        func isReady(_ agentId: AgentID) -> Bool {
            !sending.contains(agentId) && retryAt[agentId] == nil
        }

        func isRetired(_ registration: LiveActivityRegistration) -> Bool {
            guard let token = registration.updateToken else { return false }
            return retired.contains(token) || registration.activityId.map { retired.contains($0) } == true
        }
    }

    struct Stored: Sendable, Equatable {
        var pushToStart: LiveActivityRegistration?
        var agentActivities: [LiveActivityRegistration]
    }

    private enum Sent {
        case start(AgentActivitySnapshot, environment: ApnsEnvironment, at: Date)
        case update(AgentActivitySnapshot, token: String, at: Date)
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
        evaluate()
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
        if let token = registration.updateToken, let agentId = registration.agentId, !device.isRetired(registration) {
            device.activities[agentId] = adopt(registration, token: token, into: device.activities[agentId])
            device.dismissed.remove(agentId)
        }
        for id in Array(states.keys) where id != deviceId {
            release(registration, from: id)
        }
        states[deviceId] = device
        let stored = Self.stored(device)
        if try await devices.setLiveActivities(pushToStart: stored.pushToStart, agentActivities: stored.agentActivities, for: deviceId) == false {
            liveActivityLogger.error("ignored a live activity registration from unknown device \(deviceId, privacy: .public)")
            states[deviceId] = nil
        }
        evaluate()
    }

    var nextWake: Date? {
        wake?.deadline
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
            for registration in record.agentActivities.compactMap({ try? Self.normalized($0) }) {
                guard let agentId = registration.agentId, let token = registration.updateToken else { continue }
                device.activities[agentId] = Activity(activityId: registration.activityId, updateToken: token, environment: registration.env, startedAt: now)
            }
            guard device.pushToStart != nil || !device.activities.isEmpty else { continue }
            states[record.id] = device
        }
        evaluate()
    }

    private func adopt(_ registration: LiveActivityRegistration, token: String, into current: Activity?) -> Activity {
        guard var activity = current else {
            return Activity(activityId: registration.activityId, updateToken: token, environment: registration.env, startedAt: clock.now())
        }
        let sameActivity = activity.updateToken == token
            || activity.updateToken == nil
            || (registration.activityId != nil && registration.activityId == activity.activityId)
        guard sameActivity else {
            return Activity(activityId: registration.activityId, updateToken: token, environment: registration.env, startedAt: clock.now())
        }
        activity.activityId = registration.activityId ?? activity.activityId
        activity.updateToken = token
        activity.environment = registration.env
        return activity
    }

    private func release(_ registration: LiveActivityRegistration, from id: DeviceID) {
        guard var device = states[id] else { return }
        if let token = registration.pushToStartToken, device.pushToStart?.token == token {
            device.pushToStart = nil
        }
        if let token = registration.updateToken {
            device.activities = device.activities.filter { $0.value.updateToken != token }
        }
        states[id] = device
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
        device.retryAt = device.retryAt.filter { !isDue($0.value, at: now) }
        device.dismissed = device.dismissed.filter { snapshots[$0]?.isBusy == true }
        states[id] = device
        for agentId in device.activities.keys.sorted() where device.isReady(agentId) {
            evaluateActivity(of: agentId, on: id, at: now)
        }
        startActivities(on: id, at: now)
    }

    private func evaluateActivity(of agentId: AgentID, on id: DeviceID, at now: Date) {
        guard let activity = states[id]?.activities[agentId] else { return }
        let snapshot = snapshots[agentId]
        let isGoneOrIdle = snapshot.map { !$0.isBusy && isIdle(agentId, activity: activity, at: now) } ?? true
        let shouldEnd = isGoneOrIdle || isExpired(activity, at: now)
        guard let token = activity.updateToken else {
            if shouldEnd {
                liveActivityLogger.info("gave up waiting for the update token of \(agentId, privacy: .public) on device \(id, privacy: .public)")
                states[id]?.activities[agentId] = nil
            }
            return
        }
        if let sentAt = activity.sentAt, !isDue(sentAt.addingTimeInterval(configuration.updateInterval), at: now) {
            return
        }
        guard let snapshot, !shouldEnd else {
            end(agentId, token: token, activity: activity, on: id, at: now)
            return
        }
        guard let priority = updatePriority(of: snapshot, for: activity, at: now) else { return }
        let alertKind = foreground.contains(id) ? nil : snapshot.alert(since: activity.sent)
        let push = snapshot.push({ .update(alert: alertKind.map($0.alertContent)) }, at: now, staleDate: now.addingTimeInterval(configuration.staleInterval))
        let effective = alertKind == nil ? priority : .high
        send(push, as: .update(snapshot, token: token, at: now), alertKind: alertKind, to: token, environment: activity.environment, priority: effective, agent: agentId, device: id)
    }

    private func end(_ agentId: AgentID, token: String, activity: Activity, on id: DeviceID, at now: Date) {
        let snapshot = (snapshots[agentId] ?? activity.sent ?? .gone(agentId, at: now)).ended
        let dismissalDate = now.addingTimeInterval(configuration.dismissalDelay)
        let push = snapshot.push({ _ in .end(dismissalDate: dismissalDate) }, at: now, staleDate: nil)
        states[id]?.ending.insert(agentId)
        send(push, as: .end(token: token, activityId: activity.activityId), alertKind: nil, to: token, environment: activity.environment, priority: .high, agent: agentId, device: id)
    }

    private func startActivities(on id: DeviceID, at now: Date) {
        guard !foreground.contains(id), let pushToStart = states[id]?.pushToStart else { return }
        for (agentId, snapshot) in startCandidates(on: id) {
            guard let device = states[id], hasStartBudget(device) else { return }
            if device.occupied >= configuration.activityLimit {
                guard snapshot.isBlocked, device.ending.isEmpty else { continue }
                evict(on: id, at: now)
                return
            }
            let push = snapshot.push({ .start(alert: $0.startAlert) }, at: now, staleDate: now.addingTimeInterval(configuration.staleInterval))
            send(
                push,
                as: .start(snapshot, environment: pushToStart.env, at: now),
                alertKind: nil,
                to: pushToStart.token,
                environment: pushToStart.env,
                priority: .high,
                agent: agentId,
                device: id
            )
        }
    }

    private func startCandidates(on id: DeviceID) -> [(AgentID, AgentActivitySnapshot)] {
        guard let device = states[id] else { return [] }
        return snapshots
            .filter { agentId, snapshot in
                snapshot.isBusy && device.activities[agentId] == nil && device.isReady(agentId) && !device.dismissed.contains(agentId)
            }
            .sorted { ($0.value.isBlocked ? 0 : 1, $0.value.agent.since, $0.key) < ($1.value.isBlocked ? 0 : 1, $1.value.agent.since, $1.key) }
    }

    private func evict(on id: DeviceID, at now: Date) {
        guard let device = states[id] else { return }
        let idle = device.activities.filter { agentId, _ in snapshots[agentId]?.isBusy != true && device.isReady(agentId) }
        guard let (agentId, activity) = idle.min(by: { lastBusy($0.key, $0.value) < lastBusy($1.key, $1.value) }) else { return }
        liveActivityLogger.info("evicting the live activity of \(agentId, privacy: .public) on device \(id, privacy: .public)")
        guard let token = activity.updateToken else {
            states[id]?.activities[agentId] = nil
            startActivities(on: id, at: now)
            return
        }
        end(agentId, token: token, activity: activity, on: id, at: now)
    }

    private func lastBusy(_ agentId: AgentID, _ activity: Activity) -> Date {
        tracker.lastBusyAt[agentId] ?? activity.startedAt
    }

    private func isIdle(_ agentId: AgentID, activity: Activity, at now: Date) -> Bool {
        isDue(lastBusy(agentId, activity).addingTimeInterval(configuration.idleTimeout), at: now)
    }

    private func isExpired(_ activity: Activity, at now: Date) -> Bool {
        isDue(activity.startedAt.addingTimeInterval(configuration.renewalAge), at: now)
    }

    private func hasStartBudget(_ device: Device) -> Bool {
        device.starts.count + device.startsInFlight < configuration.pushToStartLimit
    }

    private func updatePriority(of snapshot: AgentActivitySnapshot, for activity: Activity, at now: Date) -> ApnsPriority? {
        if let priority = snapshot.priority(since: activity.sent) {
            return priority
        }
        guard snapshot.isBusy, let sentAt = activity.sentAt, isDue(sentAt.addingTimeInterval(configuration.refreshInterval), at: now) else { return nil }
        return .low
    }

    private func send(
        _ push: AgentActivityPush,
        as sent: Sent,
        alertKind: PushAlertKind?,
        to token: String,
        environment: ApnsEnvironment,
        priority: ApnsPriority,
        agent agentId: AgentID,
        device id: DeviceID
    ) {
        states[id]?.sending.insert(agentId)
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
            await self?.finish(sent, outcome: outcome, agent: agentId, device: id, taskId: taskId)
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

    private func finish(_ sent: Sent, outcome: Outcome, agent agentId: AgentID, device id: DeviceID, taskId: UUID) async {
        defer { sends[taskId] = nil }
        guard !isShutDown, var device = states[id] else { return }
        device.sending.remove(agentId)
        device.ending.remove(agentId)
        guard case .delivery(let delivery) = outcome else {
            liveActivityLogger.info("dropped the live activities of removed device \(id, privacy: .public)")
            states[id] = nil
            evaluate()
            return
        }
        let before = Self.stored(device)
        let now = clock.now()
        switch (sent, delivery) {
        case (_, .failed(let retryable)):
            device.retryAt[agentId] = now.addingTimeInterval(retryable ? configuration.retryDelay : configuration.configurationRetryDelay)
        case (.start(let snapshot, let environment, let at), .delivered):
            liveActivityLogger.info("started the live activity of \(agentId, privacy: .public) on device \(id, privacy: .public) by push-to-start")
            device.starts.append(at)
            if device.activities[agentId] == nil {
                device.activities[agentId] = Activity(environment: environment, startedAt: at, sent: snapshot, sentAt: at)
            }
        case (.start, .invalidToken):
            liveActivityLogger.info("APNs refused the push-to-start token of device \(id, privacy: .public)")
            device.pushToStart = nil
        case (.update(let snapshot, let token, let at), .delivered):
            if device.activities[agentId]?.updateToken == token {
                device.activities[agentId]?.sent = snapshot
                device.activities[agentId]?.sentAt = at
            }
        case (.update(_, let token, _), .invalidToken):
            liveActivityLogger.info("APNs refused the update token of \(agentId, privacy: .public) on device \(id, privacy: .public)")
            if device.activities[agentId]?.updateToken == token {
                device.activities[agentId] = nil
                device.dismissed.insert(agentId)
            }
        case (.end(let token, let activityId), .delivered), (.end(let token, let activityId), .invalidToken):
            liveActivityLogger.info("ended the live activity of \(agentId, privacy: .public) on device \(id, privacy: .public)")
            device.retired.append(contentsOf: [token] + (activityId.map { [$0] } ?? []))
            device.retired = Array(device.retired.suffix(Self.retiredLimit))
            if device.activities[agentId]?.updateToken == token {
                device.activities[agentId] = nil
            }
        }
        states[id] = device
        let after = Self.stored(device)
        if after != before {
            do {
                _ = try await devices.setLiveActivities(pushToStart: after.pushToStart, agentActivities: after.agentActivities, for: id)
            } catch {
                liveActivityLogger.error("failed to save the live activities of device \(id, privacy: .public): \(PushService.describe(error), privacy: .public)")
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
        var deadlines: [Date] = []
        for (agentId, activity) in device.activities where !device.sending.contains(agentId) {
            guard let deadline = nextDeadline(for: activity, of: agentId, at: now) else { continue }
            deadlines.append(device.retryAt[agentId].map { max($0, deadline) } ?? deadline)
        }
        if !foreground.contains(id), device.pushToStart != nil, device.occupied < configuration.activityLimit {
            let pending = snapshots.keys.filter { agentId in
                snapshots[agentId]?.isBusy == true && device.activities[agentId] == nil && !device.sending.contains(agentId) && !device.dismissed.contains(agentId)
            }
            for agentId in pending {
                let start = hasStartBudget(device) ? now : device.starts.min()?.addingTimeInterval(configuration.pushToStartWindow) ?? now
                deadlines.append(device.retryAt[agentId].map { max($0, start) } ?? start)
            }
        }
        return deadlines.min()
    }

    private func nextDeadline(for activity: Activity, of agentId: AgentID, at now: Date) -> Date? {
        let gate = activity.updateToken == nil ? nil : activity.sentAt.map { $0.addingTimeInterval(configuration.updateInterval) }
        guard let snapshot = snapshots[agentId] else { return max(gate ?? now, now) }
        var candidates = [activity.startedAt.addingTimeInterval(configuration.renewalAge)]
        if !snapshot.isBusy {
            candidates.append(lastBusy(agentId, activity).addingTimeInterval(configuration.idleTimeout))
        }
        guard activity.updateToken != nil else { return candidates.min() }
        guard let gate, let sentAt = activity.sentAt else { return now }
        if snapshot.isBusy {
            candidates.append(sentAt.addingTimeInterval(configuration.refreshInterval))
        }
        if snapshot.priority(since: activity.sent) != nil {
            candidates.append(gate)
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
            agentActivities: device.activities.keys.sorted().compactMap { agentId in
                guard let activity = device.activities[agentId], let token = activity.updateToken else { return nil }
                return LiveActivityRegistration(activityId: activity.activityId, updateToken: token, agentId: agentId, env: activity.environment)
            }
        )
    }
}
