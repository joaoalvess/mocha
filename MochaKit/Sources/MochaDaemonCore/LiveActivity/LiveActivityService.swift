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
        var sent: LiveActivitySnapshot?
        var sentAt: Date?
    }

    struct Device: Sendable {
        var pushToStart: ApnsRegistration?
        var activity: Activity?
        var starts: [Date] = []
        var retryAt: Date?
        var isSending = false
        var restartAfterEnd = false
        var retired: [String] = []

        func isRetired(_ registration: LiveActivityRegistration) -> Bool {
            guard let token = registration.updateToken else { return false }
            return retired.contains(token) || registration.activityId.map { retired.contains($0) } == true
        }
    }

    private enum Action {
        case start(token: String, environment: ApnsEnvironment)
        case update(token: String, environment: ApnsEnvironment, priority: ApnsPriority)
        case end(token: String, environment: ApnsEnvironment, restart: Bool)
        case abandon(restart: Bool)
    }

    private enum Sent {
        case start(LiveActivitySnapshot, environment: ApnsEnvironment, at: Date)
        case update(LiveActivitySnapshot, token: String, at: Date)
        case end(token: String, activityId: String?, restart: Bool)
    }

    private enum Outcome {
        case delivery(LiveActivityDelivery)
        case deviceGone
    }

    private struct Wake {
        let id: UUID
        let deadline: Date
        let task: Task<Void, Never>
    }

    private static let tolerance: TimeInterval = 0.001
    private static let retiredLimit = 16

    private let devices: DeviceStore
    private let sender: any LiveActivityPushSending
    private let clock: any GatewayClock
    private let configuration: LiveActivityConfiguration

    private var tracker = LiveActivityStatusTracker()
    private var snapshot = LiveActivitySnapshot.allDone
    private var hasInput = false
    private var idleSince: Date?
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
        idleSince = idleSince ?? clock.now()
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
        let now = clock.now()
        hasInput = true
        foreground = input.foregroundDevices
        snapshot = tracker.snapshot(of: input, at: now, titleLimit: configuration.titleLimit)
        if snapshot.isBusy {
            idleSince = nil
        } else {
            idleSince = idleSince ?? now
            for id in Array(states.keys) {
                states[id]?.restartAfterEnd = false
            }
        }
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
        if let token = registration.updateToken, !device.isRetired(registration) {
            device.activity = adopt(registration, token: token, into: device.activity)
        }
        for id in Array(states.keys) where id != deviceId {
            release(registration, from: id)
        }
        states[deviceId] = device
        let stored = Self.stored(device)
        if try await devices.setLiveActivity(stored, for: deviceId) == false {
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
        for record in records {
            guard let registration = record.liveActivity, let normalized = try? Self.normalized(registration), states[record.id] == nil else {
                continue
            }
            var device = Device()
            device.pushToStart = normalized.pushToStartToken.map { ApnsRegistration(token: $0, env: normalized.env) }
            if let token = normalized.updateToken {
                device.activity = Activity(activityId: normalized.activityId, updateToken: token, environment: normalized.env, startedAt: now)
            }
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
        if let token = registration.updateToken, device.activity?.updateToken == token {
            device.activity = nil
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
        guard var device = states[id], !device.isSending else { return }
        if let retryAt = device.retryAt {
            guard isDue(retryAt, at: now) else { return }
            device.retryAt = nil
        }
        device.starts.removeAll { isDue($0.addingTimeInterval(configuration.pushToStartWindow), at: now) }
        states[id] = device
        guard let action = action(for: device, id: id, at: now) else { return }
        switch action {
        case .abandon(let restart):
            liveActivityLogger.info("gave up waiting for the update token of device \(id, privacy: .public)")
            states[id]?.activity = nil
            states[id]?.restartAfterEnd = restart
            evaluate(id, at: now)
        case .start(let token, let environment):
            let sent = snapshot
            let push = LiveActivityPush(
                event: .start(alert: LiveActivityStartAlert(title: configuration.alertTitle, body: sent.summary)),
                contentState: sent.contentState(at: now),
                timestamp: now
            )
            send(push, as: .start(sent, environment: environment, at: now), to: token, environment: environment, priority: .high, device: id)
        case .update(let token, let environment, let priority):
            let sent = snapshot
            let push = LiveActivityPush(
                event: .update,
                contentState: sent.contentState(at: now),
                timestamp: now,
                staleDate: now.addingTimeInterval(configuration.staleInterval)
            )
            send(push, as: .update(sent, token: token, at: now), to: token, environment: environment, priority: priority, device: id)
        case .end(let token, let environment, let restart):
            let push = LiveActivityPush(
                event: .end(dismissalDate: now.addingTimeInterval(configuration.dismissalDelay)),
                contentState: LiveActivitySnapshot.allDone.contentState(at: now),
                timestamp: now
            )
            let activityId = device.activity?.activityId
            send(push, as: .end(token: token, activityId: activityId, restart: restart), to: token, environment: environment, priority: .high, device: id)
        }
    }

    private func action(for device: Device, id: DeviceID, at now: Date) -> Action? {
        guard let activity = device.activity else {
            guard wantsStart(device, id: id), let pushToStart = device.pushToStart, hasStartBudget(device) else { return nil }
            return .start(token: pushToStart.token, environment: pushToStart.env)
        }
        let isIdle = idleSince.map { isDue($0.addingTimeInterval(configuration.idleTimeout), at: now) } ?? false
        let isExpired = isDue(activity.startedAt.addingTimeInterval(configuration.renewalAge), at: now)
        guard let token = activity.updateToken else {
            if isExpired {
                return .abandon(restart: true)
            }
            return isIdle ? .abandon(restart: false) : nil
        }
        if let sentAt = activity.sentAt, !isDue(sentAt.addingTimeInterval(configuration.updateInterval), at: now) {
            return nil
        }
        if isIdle {
            return .end(token: token, environment: activity.environment, restart: false)
        }
        if isExpired {
            return .end(token: token, environment: activity.environment, restart: true)
        }
        if let priority = pendingPriority(of: activity) {
            return .update(token: token, environment: activity.environment, priority: priority)
        }
        if snapshot.isBusy, let sentAt = activity.sentAt, isDue(sentAt.addingTimeInterval(configuration.refreshInterval), at: now) {
            return .update(token: token, environment: activity.environment, priority: .low)
        }
        return nil
    }

    private func wantsStart(_ device: Device, id: DeviceID) -> Bool {
        guard !foreground.contains(id) else { return false }
        return snapshot.working > 0 || (device.restartAfterEnd && snapshot.isBusy)
    }

    private func hasStartBudget(_ device: Device) -> Bool {
        device.starts.count < configuration.pushToStartLimit
    }

    private func pendingPriority(of activity: Activity) -> ApnsPriority? {
        guard let sent = activity.sent else { return .high }
        return snapshot.priority(since: sent)
    }

    private func send(_ push: LiveActivityPush, as sent: Sent, to token: String, environment: ApnsEnvironment, priority: ApnsPriority, device id: DeviceID) {
        states[id]?.isSending = true
        let taskId = UUID()
        let sender = sender
        let devices = devices
        sends[taskId] = Task { [weak self] in
            let outcome: Outcome
            if await Self.isPaired(id, in: devices) {
                outcome = .delivery(await sender.sendLiveActivity(push, to: token, environment: environment, priority: priority))
            } else {
                outcome = .deviceGone
            }
            await self?.finish(sent, outcome: outcome, device: id, taskId: taskId)
        }
    }

    private static func isPaired(_ id: DeviceID, in devices: DeviceStore) async -> Bool {
        do {
            return try await devices.devices().contains { $0.id == id }
        } catch {
            liveActivityLogger.error("failed to read devices: \(PushService.describe(error), privacy: .public)")
            return true
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
        case (.start(let snapshot, let environment, let at), .delivered):
            liveActivityLogger.info("started a live activity on device \(id, privacy: .public) by push-to-start")
            device.starts.append(at)
            device.restartAfterEnd = false
            if device.activity == nil {
                device.activity = Activity(environment: environment, startedAt: at, sent: snapshot, sentAt: at)
            }
        case (.start, .invalidToken):
            liveActivityLogger.info("APNs refused the push-to-start token of device \(id, privacy: .public)")
            device.pushToStart = nil
        case (.update(let snapshot, let token, let at), .delivered):
            if device.activity?.updateToken == token {
                device.activity?.sent = snapshot
                device.activity?.sentAt = at
            }
        case (.update(_, let token, _), .invalidToken):
            liveActivityLogger.info("APNs refused the update token of device \(id, privacy: .public)")
            if device.activity?.updateToken == token {
                device.activity = nil
            }
        case (.end(let token, let activityId, let restart), .delivered), (.end(let token, let activityId, let restart), .invalidToken):
            liveActivityLogger.info("ended the live activity of device \(id, privacy: .public)")
            device.retired.append(contentsOf: [token] + (activityId.map { [$0] } ?? []))
            device.retired = Array(device.retired.suffix(Self.retiredLimit))
            if device.activity?.updateToken == token {
                device.activity = nil
                device.restartAfterEnd = restart && snapshot.isBusy
            }
        }
        states[id] = device
        let after = Self.stored(device)
        if after != before {
            do {
                _ = try await devices.setLiveActivity(after, for: id)
            } catch {
                liveActivityLogger.error("failed to save the live activity of device \(id, privacy: .public): \(PushService.describe(error), privacy: .public)")
            }
        }
        evaluate()
    }

    private func scheduleWake(at now: Date) {
        let deadline = states.compactMap { nextDeadline(for: $0.value, id: $0.key) }.min()
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

    private func nextDeadline(for device: Device, id: DeviceID) -> Date? {
        guard !device.isSending else { return nil }
        let deadline: Date?
        if let activity = device.activity {
            deadline = nextDeadline(for: activity)
        } else if wantsStart(device, id: id), device.pushToStart != nil {
            deadline = hasStartBudget(device) ? clock.now() : device.starts.min()?.addingTimeInterval(configuration.pushToStartWindow)
        } else {
            deadline = nil
        }
        guard let deadline else { return nil }
        return device.retryAt.map { max($0, deadline) } ?? deadline
    }

    private func nextDeadline(for activity: Activity) -> Date? {
        var candidates = [activity.startedAt.addingTimeInterval(configuration.renewalAge)]
        if let idleSince {
            candidates.append(idleSince.addingTimeInterval(configuration.idleTimeout))
        }
        guard activity.updateToken != nil else { return candidates.min() }
        guard let sentAt = activity.sentAt else { return clock.now() }
        let gate = sentAt.addingTimeInterval(configuration.updateInterval)
        if snapshot.isBusy {
            candidates.append(sentAt.addingTimeInterval(configuration.refreshInterval))
        }
        if pendingPriority(of: activity) != nil {
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
        return LiveActivityRegistration(pushToStartToken: pushToStart, activityId: activityId, updateToken: update, env: registration.env)
    }

    private static func validToken(_ token: String) throws -> String {
        guard ApnsRequest.isValidDeviceToken(token) else { throw LiveActivityRegistrationError.invalidToken }
        return token.lowercased()
    }

    private static func stored(_ device: Device) -> LiveActivityRegistration? {
        let activity = device.activity.flatMap { $0.updateToken == nil ? nil : $0 }
        guard let environment = activity?.environment ?? device.pushToStart?.env else { return nil }
        return LiveActivityRegistration(
            pushToStartToken: device.pushToStart?.env == environment ? device.pushToStart?.token : nil,
            activityId: activity?.activityId,
            updateToken: activity?.updateToken,
            env: environment
        )
    }
}
