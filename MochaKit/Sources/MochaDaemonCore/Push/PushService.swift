import Foundation
import MochaProtocol
import os

let pushLogger = Logger(subsystem: "com.joaoalves.mocha", category: "push")

public struct ApnsCredentials: Sendable {
    public typealias Loader = @Sendable () throws -> ApnsCredentials

    public var config: ApnsConfig
    public var key: ApnsSigningKey

    public init(config: ApnsConfig, key: ApnsSigningKey) {
        self.config = config
        self.key = key
    }

    public static func loader(configFile: URL, keyStore: any ApnsKeyStoring = KeychainApnsKeyStore()) -> Loader {
        {
            let loaded = try ApnsKeyImporter(keyStore: keyStore, configStore: ApnsConfigStore(url: configFile)).loadSigningKey()
            return ApnsCredentials(config: loaded.config, key: loaded.key)
        }
    }
}

public struct ApnsConfigurationIssue: Codable, Sendable, Equatable {
    public var environment: ApnsEnvironment
    public var status: Int
    public var reason: String
    public var at: Date

    public init(environment: ApnsEnvironment, status: Int, reason: String, at: Date) {
        self.environment = environment
        self.status = status
        self.reason = reason
        self.at = at
    }
}

public protocol PushAudience: Sendable {
    func agentSummary(_ id: AgentID) async -> AgentSummary?
    func foregroundDevices(for agentId: AgentID) async -> Set<DeviceID>
    func herdrStatus(of agentId: AgentID) async -> AgentStatus?
}

public struct PushServiceConfiguration: Sendable {
    public var needsInputWindow: Duration
    public var blockedGrace: Duration
    public var retryDelays: [Duration]
    public var turnDoneLifetime: TimeInterval
    public var needsInputLifetime: TimeInterval
    public var turnDoneCooldown: Duration

    public init(
        needsInputWindow: Duration = .seconds(10),
        blockedGrace: Duration = .seconds(1),
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)],
        turnDoneLifetime: TimeInterval = 60 * 60,
        needsInputLifetime: TimeInterval = 10 * 60,
        turnDoneCooldown: Duration = .seconds(5)
    ) {
        self.needsInputWindow = needsInputWindow
        self.blockedGrace = blockedGrace
        self.retryDelays = retryDelays
        self.turnDoneLifetime = turnDoneLifetime
        self.needsInputLifetime = needsInputLifetime
        self.turnDoneCooldown = turnDoneCooldown
    }
}

public actor PushService {
    private struct Sender {
        let config: ApnsConfig
        let client: ApnsClient
    }

    private struct Recipient {
        let device: DeviceID
        let apns: ApnsRegistration
        let silencesAtMac: Bool
    }

    private struct SilencedAlert {
        let kind: PushAlertKind
        let requestId: RequestID?
        let title: String
        let body: String
        let category: String
        let at: Date
        let isFallback: Bool
    }

    private struct BlockedCheck {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct TurnDoneCheck {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct HandedOffAlert: Hashable {
        let device: DeviceID
        let agentId: AgentID
        let kind: PushAlertKind
    }

    private static let handoffWindow: TimeInterval = 10

    private let devices: DeviceStore
    private let audience: any PushAudience
    private let credentials: ApnsCredentials.Loader
    private let transport: any ApnsTransport
    private let clock: any GatewayClock
    private let configuration: PushServiceConfiguration

    private var sender: Sender?
    private var lastNeedsInput: [AgentID: Date] = [:]
    private var blockedAgents: Set<AgentID> = []
    private var blockedChecks: [AgentID: BlockedCheck] = [:]
    private var turnDoneChecks: [AgentID: TurnDoneCheck] = [:]
    private var deliveries: [UUID: Task<Void, Never>] = [:]
    private var issues: [ApnsEnvironment: ApnsConfigurationIssue] = [:]
    private var liveActivityCards: (any LiveActivityCardHolding)?
    private var handedOff: [HandedOffAlert: Date] = [:]
    private var presence: PresenceMonitor?
    private var presenceTask: Task<Void, Never>?
    private var lock: ConsoleLock = .unknown
    private var silenced: [DeviceID: [AgentID: SilencedAlert]] = [:]
    private var isShutDown = false

    public init(
        devices: DeviceStore,
        audience: any PushAudience,
        credentials: @escaping ApnsCredentials.Loader,
        transport: any ApnsTransport = URLSessionApnsTransport(),
        clock: any GatewayClock = SystemGatewayClock(),
        configuration: PushServiceConfiguration = PushServiceConfiguration()
    ) {
        self.devices = devices
        self.audience = audience
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.configuration = configuration
    }

    public func attachLiveActivity(_ cards: any LiveActivityCardHolding) async {
        liveActivityCards = cards
        await cards.attachAlertHandoff(self)
    }

    public func attachPresence(_ presence: PresenceMonitor) async {
        self.presence = presence
        lock = await presence.current()
        let transitions = await presence.transitions()
        presenceTask = Task { [weak self] in
            for await lock in transitions {
                guard let self else { break }
                await self.presenceChanged(to: lock)
            }
        }
    }

    func presenceChanged(to newLock: ConsoleLock) async {
        let wasAtMac = lock.isAtMac
        lock = newLock
        guard wasAtMac, !newLock.isAtMac, !silenced.isEmpty else { return }
        let pending = silenced
        silenced = [:]
        guard let sender = loadSender() else { return }
        let records: [DeviceRecord]
        do {
            records = try await devices.devices()
        } catch {
            pushLogger.error("failed to read devices: \(Self.describe(error), privacy: .public)")
            return
        }
        let cards = await liveActivityCards?.cardDevices() ?? []
        for (device, alerts) in pending.sorted(by: { $0.key < $1.key }) {
            let record = records.first { $0.id == device }
            var unseen: [(agentId: AgentID, alert: SilencedAlert)] = []
            if let record, record.preferences.silenceWhileAtMac, !cards.contains(device) {
                for (agentId, alert) in alerts where alert.kind != .turnDone || record.preferences.turnDoneAlerts {
                    guard await !audience.foregroundDevices(for: agentId).contains(device), await isUnseen(alert, of: agentId) else { continue }
                    unseen.append((agentId, alert))
                }
            }
            guard !isShutDown,
                  let chosen = unseen.max(by: { Self.urgency($0.alert) < Self.urgency($1.alert) }),
                  let apns = record?.apns,
                  ApnsRequest.isValidDeviceToken(apns.token)
            else {
                pushLogger.notice("lock-ring none device \(device, privacy: .public)")
                continue
            }
            pushLogger.notice("lock-ring \(chosen.agentId, privacy: .public) \(chosen.alert.kind.rawValue, privacy: .public) device \(device, privacy: .public)")
            let alert = chosen.alert
            send(
                alert.kind,
                agentId: chosen.agentId,
                title: alert.title,
                body: alert.body,
                category: alert.category,
                requestId: alert.requestId,
                to: [Recipient(device: device, apns: apns, silencesAtMac: false)],
                isFallback: alert.isFallback,
                sender: sender
            )
        }
    }

    private func isUnseen(_ alert: SilencedAlert, of agentId: AgentID) async -> Bool {
        switch alert.kind {
        case .needsInput:
            guard let agent = await audience.agentSummary(agentId) else { return false }
            return agent.status == .blocked || agent.pendingCount > 0
        case .turnDone:
            return await audience.herdrStatus(of: agentId) == .done
        }
    }

    private static func urgency(_ alert: SilencedAlert) -> (Int, Date) {
        let rank = switch alert.kind {
        case .needsInput: alert.requestId == nil ? 1 : 2
        case .turnDone: 0
        }
        return (rank, alert.at)
    }

    public func cardLost(_ alerts: [LiveActivityLostAlert], on device: DeviceID) async {
        guard !isShutDown, !alerts.isEmpty else { return }
        let record: DeviceRecord?
        do {
            record = try await devices.devices().first { $0.id == device }
        } catch {
            pushLogger.error("failed to read devices: \(Self.describe(error), privacy: .public)")
            return
        }
        guard let record, let apns = record.apns, ApnsRequest.isValidDeviceToken(apns.token), let sender = loadSender() else { return }
        let recipient = Recipient(device: device, apns: apns, silencesAtMac: record.preferences.silenceWhileAtMac)
        for alert in alerts where alert.kind != .turnDone || record.preferences.turnDoneAlerts {
            guard !isShutDown, await !audience.foregroundDevices(for: alert.agentId).contains(device) else { continue }
            handedOff[HandedOffAlert(device: device, agentId: alert.agentId, kind: alert.kind)] = clock.now()
            send(
                alert.kind,
                agentId: alert.agentId,
                title: alert.title,
                body: alert.body,
                category: alert.kind.category,
                requestId: alert.requestId,
                to: [recipient],
                isFallback: true,
                sender: sender
            )
        }
    }

    public func handle(_ hook: ReceivedHook) async {
        guard !isShutDown else { return }
        switch hook.event {
        case .stop(let stop):
            await turnDone(hook.agentId, body: PushAlertText.turnDoneBody(stop.lastAssistantMessage))
        case .permissionRequest(let request):
            rememberNeedsInput(hook.agentId, at: clock.now())
            await alert(
                .needsInput,
                agentId: hook.agentId,
                body: PushAlertText.needsInputBody(request),
                category: hook.requestId.map { _ in PushAlertText.pendingCategory(request) },
                requestId: hook.requestId
            )
        case .notification(let notification) where notification.kind == .permissionPrompt:
            await secondaryNeedsInput(hook.agentId, agent: await audience.agentSummary(hook.agentId))
        case .sessionStart, .userPromptSubmit, .notification, .preModelSwitch, .postModelSwitch:
            break
        }
    }

    func handle(_ alert: CodexAlert) async {
        guard !isShutDown else { return }
        switch alert {
        case .turnDone(let agentId, let lastMessage):
            await turnDone(agentId, body: PushAlertText.turnDoneBody(lastMessage))
        case .needsInput(let request):
            rememberNeedsInput(request.agentId, at: clock.now())
            await self.alert(
                .needsInput,
                agentId: request.agentId,
                body: PushAlertText.codexNeedsInputBody(request.kind),
                category: PushAlertText.codexCategory(request.kind),
                requestId: request.id
            )
        }
    }

    public func agentStatusChanged(_ agentId: AgentID, to status: AgentStatus) {
        guard !isShutDown else { return }
        guard status == .blocked else {
            blockedAgents.remove(agentId)
            blockedChecks.removeValue(forKey: agentId)?.task.cancel()
            return
        }
        guard blockedAgents.insert(agentId).inserted else { return }
        let token = UUID()
        let clock = clock
        let grace = configuration.blockedGrace
        let task = Task { [weak self] in
            guard (try? await clock.sleep(for: grace)) != nil else { return }
            await self?.blockedGraceElapsed(agentId, token: token)
        }
        blockedChecks[agentId] = BlockedCheck(token: token, task: task)
    }

    public func configurationIssues() -> [ApnsConfigurationIssue] {
        issues.values.sorted { $0.environment.rawValue < $1.environment.rawValue }
    }

    public func sendLiveActivity(
        _ push: AgentActivityPush,
        to token: String,
        environment: ApnsEnvironment,
        priority: ApnsPriority
    ) async -> LiveActivityDelivery {
        guard !isShutDown, let sender = loadSender() else { return .failed(retryable: false) }
        let event = push.event.name
        let request: ApnsRequest
        do {
            request = ApnsRequest(
                deviceToken: token,
                environment: environment,
                pushType: .liveactivity,
                topic: ApnsTopic.liveActivity(bundleId: sender.config.bundleId),
                priority: priority,
                payload: try push.payload()
            )
        } catch {
            pushLogger.error("failed to encode a live activity \(event, privacy: .public): \(Self.describe(error), privacy: .public)")
            return .failed(retryable: false)
        }
        let apnsId = request.apnsId.uuidString.lowercased()
        let label = "live activity \(event) of \(push.agentId) p\(priority.rawValue) apns-id \(apnsId) (\(environment.rawValue))"
        let response: ApnsResponse
        do {
            response = try await sender.client.send(request)
        } catch {
            pushLogger.error("\(label, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
            return .failed(retryable: !(error is ApnsError))
        }
        guard !response.isSuccess else {
            issues[environment] = nil
            pushLogger.info("\(label, privacy: .public) delivered, unique-id \(response.uniqueId ?? "-", privacy: .public)")
            return .delivered
        }
        let reason = response.reason ?? ""
        pushLogger.error("\(label, privacy: .public) refused: \(response.status, privacy: .public) \(reason, privacy: .public)")
        if response.deviceTokenIsInvalid {
            return .invalidToken
        }
        if ApnsReason.configuration.contains(reason) {
            issues[environment] = ApnsConfigurationIssue(environment: environment, status: response.status, reason: reason, at: clock.now())
            self.sender = nil
            return .failed(retryable: false)
        }
        return .failed(retryable: response.status == 429 || response.status >= 500)
    }

    public func shutdown() async {
        isShutDown = true
        for check in blockedChecks.values {
            check.task.cancel()
        }
        blockedChecks.removeAll()
        for check in turnDoneChecks.values {
            check.task.cancel()
        }
        turnDoneChecks.removeAll()
        presenceTask?.cancel()
        presenceTask = nil
        let running = Array(deliveries.values)
        deliveries.removeAll()
        for task in running {
            task.cancel()
        }
        for task in running {
            await task.value
        }
    }

    var pendingBlockedChecks: Int {
        blockedChecks.count
    }

    var pendingTurnDoneChecks: Int {
        turnDoneChecks.count
    }

    func waitForDeliveries() async {
        while let task = deliveries.values.first {
            await task.value
        }
    }

    private func blockedGraceElapsed(_ agentId: AgentID, token: UUID) async {
        guard blockedChecks[agentId]?.token == token else { return }
        defer {
            if blockedChecks[agentId]?.token == token {
                blockedChecks[agentId] = nil
            }
        }
        guard blockedAgents.contains(agentId) else { return }
        guard let agent = await audience.agentSummary(agentId), agent.kind == TreeComposer.claudeKind else { return }
        await secondaryNeedsInput(agentId, agent: agent)
    }

    private func turnDone(_ agentId: AgentID, body: String) async {
        let cooldown = configuration.turnDoneCooldown
        guard cooldown > .zero else {
            await alert(.turnDone, agentId: agentId, body: body)
            return
        }
        turnDoneChecks.removeValue(forKey: agentId)?.task.cancel()
        let token = UUID()
        let clock = clock
        let task = Task { [weak self] in
            guard (try? await clock.sleep(for: cooldown)) != nil else { return }
            await self?.turnDoneCooldownElapsed(agentId, body: body, token: token)
        }
        turnDoneChecks[agentId] = TurnDoneCheck(token: token, task: task)
    }

    private func turnDoneCooldownElapsed(_ agentId: AgentID, body: String, token: UUID) async {
        guard turnDoneChecks[agentId]?.token == token else { return }
        defer {
            if turnDoneChecks[agentId]?.token == token {
                turnDoneChecks[agentId] = nil
            }
        }
        guard !isShutDown else { return }
        let agent = await audience.agentSummary(agentId)
        guard turnDoneChecks[agentId]?.token == token else { return }
        if let agent, agent.status.isBusy || agent.pendingCount > 0 {
            pushLogger.notice("push turnDone of \(agentId, privacy: .public) cancelled: the agent is busy again")
            return
        }
        await alert(.turnDone, agentId: agentId, body: body)
    }

    private func secondaryNeedsInput(_ agentId: AgentID, agent: AgentSummary?) async {
        if let agent, agent.pendingCount > 0 {
            pushLogger.debug("needsInput for \(agentId, privacy: .public) already alerted by its pending request")
            return
        }
        let now = clock.now()
        if let last = lastNeedsInput[agentId], now.timeIntervalSince(last) < Self.seconds(configuration.needsInputWindow) {
            pushLogger.debug("needsInput for \(agentId, privacy: .public) already alerted")
            return
        }
        rememberNeedsInput(agentId, at: now)
        await alert(.needsInput, agentId: agentId, body: PushAlertText.secondaryBody)
    }

    private func rememberNeedsInput(_ agentId: AgentID, at date: Date) {
        let window = Self.seconds(configuration.needsInputWindow)
        lastNeedsInput = lastNeedsInput.filter { date.timeIntervalSince($0.value) < window }
        lastNeedsInput[agentId] = date
    }

    private func alert(_ kind: PushAlertKind, agentId: AgentID, body: String, category: String? = nil, requestId: RequestID? = nil) async {
        let recipients = await recipients(for: kind, agentId: agentId)
        guard !recipients.isEmpty, let sender = loadSender() else { return }
        let summary = await audience.agentSummary(agentId)
        let provider: AgentProvider? = summary?.kind == TreeComposer.codexKind ? .codex : nil
        send(
            kind,
            agentId: agentId,
            title: PushAlertText.title(kind, workspaceLabel: summary?.workspaceLabel, provider: provider),
            body: body,
            category: category ?? kind.category,
            requestId: requestId,
            to: recipients,
            isFallback: false,
            sender: sender
        )
    }

    private func send(
        _ kind: PushAlertKind,
        agentId: AgentID,
        title: String,
        body: String,
        category: String,
        requestId: RequestID?,
        to recipients: [Recipient],
        isFallback: Bool,
        sender: Sender
    ) {
        let now = clock.now()
        var recipients = recipients
        if lock.isAtMac {
            for recipient in recipients where recipient.silencesAtMac {
                silenced[recipient.device, default: [:]][agentId] = SilencedAlert(
                    kind: kind,
                    requestId: requestId,
                    title: title,
                    body: body,
                    category: category,
                    at: now,
                    isFallback: isFallback
                )
                pushLogger.notice(
                    "alert \(kind.rawValue, privacy: .public) of \(agentId, privacy: .public) device \(recipient.device, privacy: .public) silent reason=atMac"
                )
            }
            recipients.removeAll { $0.silencesAtMac }
        }
        guard !recipients.isEmpty else { return }
        let payload: Data
        do {
            payload = try ApnsAlertPush(
                title: title,
                body: body,
                threadId: agentId,
                category: category,
                interruptionLevel: kind.interruptionLevel,
                agentId: agentId,
                kind: kind.rawValue,
                requestId: requestId,
                sentAt: now
            ).payload()
        } catch {
            pushLogger.error("failed to encode a \(kind.rawValue, privacy: .public) alert: \(Self.describe(error), privacy: .public)")
            return
        }
        let lifetime = kind == .turnDone ? configuration.turnDoneLifetime : configuration.needsInputLifetime
        let collapseId = agentId.utf8.count <= ApnsRequest.maxCollapseIdBytes ? agentId : nil
        for recipient in recipients {
            let request = ApnsRequest(
                deviceToken: recipient.apns.token,
                environment: recipient.apns.env,
                pushType: .alert,
                topic: ApnsTopic.alert(bundleId: sender.config.bundleId),
                priority: .high,
                expiration: .at(now.addingTimeInterval(lifetime)),
                collapseId: collapseId,
                payload: payload
            )
            deliver(request, to: recipient.device, kind: kind, agentId: agentId, isFallback: isFallback, client: sender.client)
        }
    }

    private func recipients(for kind: PushAlertKind, agentId: AgentID) async -> [Recipient] {
        let records: [DeviceRecord]
        do {
            records = try await devices.devices()
        } catch {
            pushLogger.error("failed to read devices: \(Self.describe(error), privacy: .public)")
            return []
        }
        let candidates = records.filter { record in
            record.apns != nil && (kind != .turnDone || record.preferences.turnDoneAlerts)
        }
        guard !candidates.isEmpty else { return [] }
        let cards = await liveActivityCards?.cardDevices() ?? []
        let foreground = await audience.foregroundDevices(for: agentId)
        let now = clock.now()
        handedOff = handedOff.filter { now.timeIntervalSince($0.value) < Self.handoffWindow }
        var tokens: Set<String> = []
        var recipients: [Recipient] = []
        for record in candidates where !foreground.contains(record.id) {
            guard !cards.contains(record.id) else {
                pushLogger.info("\(kind.rawValue, privacy: .public) alert of \(agentId, privacy: .public) left to the card of device \(record.id, privacy: .public)")
                continue
            }
            guard handedOff[HandedOffAlert(device: record.id, agentId: agentId, kind: kind)] == nil else {
                pushLogger.info("\(kind.rawValue, privacy: .public) alert of \(agentId, privacy: .public) already handed off from the lost card of device \(record.id, privacy: .public)")
                continue
            }
            guard let apns = record.apns, ApnsRequest.isValidDeviceToken(apns.token), tokens.insert(apns.token.lowercased()).inserted else {
                continue
            }
            recipients.append(Recipient(device: record.id, apns: apns, silencesAtMac: record.preferences.silenceWhileAtMac))
        }
        return recipients
    }

    private func loadSender() -> Sender? {
        if let sender {
            return sender
        }
        do {
            let loaded = try credentials()
            let clock = clock
            let sender = Sender(
                config: loaded.config,
                client: ApnsClient(tokens: ApnsTokenProvider(key: loaded.key, now: { clock.now() }), transport: transport)
            )
            self.sender = sender
            return sender
        } catch {
            pushLogger.error("APNs is not ready: \(Self.describe(error), privacy: .public)")
            return nil
        }
    }

    private func deliver(_ request: ApnsRequest, to device: DeviceID, kind: PushAlertKind, agentId: AgentID, isFallback: Bool, client: ApnsClient) {
        guard !isShutDown else { return }
        pushLogger.notice(
            "push \(kind.rawValue, privacy: .public) of \(agentId, privacy: .public) device \(device, privacy: .public) fallback=\(isFallback ? "yes" : "no", privacy: .public)"
        )
        let id = UUID()
        let clock = clock
        let delays = configuration.retryDelays
        deliveries[id] = Task { [weak self] in
            var attempt = 0
            while true {
                let outcome: Result<ApnsResponse, any Error>
                do {
                    outcome = .success(try await client.send(request))
                } catch {
                    outcome = .failure(error)
                }
                guard let self, await self.record(outcome, of: request, device: device, kind: kind), attempt < delays.count else { break }
                guard (try? await clock.sleep(for: delays[attempt])) != nil else { break }
                attempt += 1
            }
            await self?.deliveryFinished(id)
        }
    }

    private func deliveryFinished(_ id: UUID) {
        deliveries[id] = nil
    }

    private func record(_ outcome: Result<ApnsResponse, any Error>, of request: ApnsRequest, device: DeviceID, kind: PushAlertKind) async -> Bool {
        let apnsId = request.apnsId.uuidString.lowercased()
        let environment = request.environment.rawValue
        switch outcome {
        case .failure(let error):
            pushLogger.error(
                "\(kind.rawValue, privacy: .public) alert apns-id \(apnsId, privacy: .public) (\(environment, privacy: .public)) failed: \(Self.describe(error), privacy: .public)"
            )
            return !isShutDown && !(error is ApnsError)
        case .success(let response) where response.isSuccess:
            issues[request.environment] = nil
            pushLogger.info(
                "\(kind.rawValue, privacy: .public) alert delivered, apns-id \(response.apnsId ?? apnsId, privacy: .public), unique-id \(response.uniqueId ?? "-", privacy: .public) (\(environment, privacy: .public))"
            )
            return false
        case .success(let response):
            let reason = response.reason ?? ""
            pushLogger.error(
                "\(kind.rawValue, privacy: .public) alert apns-id \(apnsId, privacy: .public) (\(environment, privacy: .public)) refused: \(response.status, privacy: .public) \(reason, privacy: .public)"
            )
            if response.deviceTokenIsInvalid {
                await removeToken(request.deviceToken, from: device)
                return false
            }
            if ApnsReason.configuration.contains(reason) {
                issues[request.environment] = ApnsConfigurationIssue(
                    environment: request.environment,
                    status: response.status,
                    reason: reason,
                    at: clock.now()
                )
                sender = nil
                return false
            }
            return !isShutDown && (response.status == 429 || response.status >= 500)
        }
    }

    private func removeToken(_ token: String, from device: DeviceID) async {
        do {
            if try await devices.removeApnsToken(token, from: device) {
                pushLogger.info("removed the APNs token of device \(device, privacy: .public)")
            }
        } catch {
            pushLogger.error("failed to remove the APNs token of device \(device, privacy: .public): \(Self.describe(error), privacy: .public)")
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as URLError:
            "URLError \(error.code.rawValue)"
        case let error as ApnsError:
            String(describing: error)
        case let error as DeviceStoreError:
            String(describing: error)
        default:
            String(describing: type(of: error))
        }
    }
}
