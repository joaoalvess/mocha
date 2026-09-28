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
}

public struct PushServiceConfiguration: Sendable {
    public var needsInputWindow: Duration
    public var blockedGrace: Duration
    public var retryDelays: [Duration]
    public var turnDoneLifetime: TimeInterval
    public var needsInputLifetime: TimeInterval
    public var cardAlertWindow: TimeInterval

    public init(
        needsInputWindow: Duration = .seconds(10),
        blockedGrace: Duration = .seconds(1),
        retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)],
        turnDoneLifetime: TimeInterval = 60 * 60,
        needsInputLifetime: TimeInterval = 10 * 60,
        cardAlertWindow: TimeInterval = 60
    ) {
        self.needsInputWindow = needsInputWindow
        self.blockedGrace = blockedGrace
        self.retryDelays = retryDelays
        self.turnDoneLifetime = turnDoneLifetime
        self.needsInputLifetime = needsInputLifetime
        self.cardAlertWindow = cardAlertWindow
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
        let hasCard: Bool
    }

    private struct CardAlertKey: Hashable {
        let device: DeviceID
        let agentId: AgentID
        let kind: PushAlertKind
    }

    private struct ParkedAlert {
        let request: ApnsRequest
        let at: Date
    }

    private struct BlockedCheck {
        let token: UUID
        let task: Task<Void, Never>
    }

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
    private var deliveries: [UUID: Task<Void, Never>] = [:]
    private var issues: [ApnsEnvironment: ApnsConfigurationIssue] = [:]
    private var liveActivityCards: (any LiveActivityCardHolding)?
    private var parkedAlerts: [CardAlertKey: ParkedAlert] = [:]
    private var missedCardAlerts: [CardAlertKey: Date] = [:]
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
        await cards.attachAlertFallback(self)
    }

    public func cardAlert(_ kind: PushAlertKind, of agentId: AgentID, on device: DeviceID, wasShown: Bool) {
        guard !isShutDown else { return }
        let now = clock.now()
        pruneCardAlerts(at: now)
        let key = CardAlertKey(device: device, agentId: agentId, kind: kind)
        let parked = parkedAlerts.removeValue(forKey: key)
        guard !wasShown else {
            missedCardAlerts[key] = nil
            return
        }
        guard let parked, let sender = loadSender() else {
            missedCardAlerts[key] = now
            return
        }
        pushLogger.info("\(kind.rawValue, privacy: .public) alert of \(agentId, privacy: .public) was not shown on the card of device \(device, privacy: .public)")
        deliver(parked.request, to: device, kind: kind, client: sender.client)
    }

    public func handle(_ hook: ReceivedHook) async {
        guard !isShutDown else { return }
        switch hook.event {
        case .stop(let stop):
            await alert(.turnDone, agentId: hook.agentId, body: PushAlertText.turnDoneBody(stop.lastAssistantMessage))
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
        case .sessionStart, .userPromptSubmit, .notification:
            break
        }
    }

    func handle(_ alert: CodexAlert) async {
        guard !isShutDown else { return }
        switch alert {
        case .turnDone(let agentId, let lastMessage):
            await self.alert(.turnDone, agentId: agentId, body: PushAlertText.turnDoneBody(lastMessage))
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

    func waitForDeliveries() async {
        while let task = deliveries.values.first {
            await task.value
        }
    }

    private func blockedGraceElapsed(_ agentId: AgentID, token: UUID) async {
        guard blockedChecks[agentId]?.token == token else { return }
        blockedChecks[agentId] = nil
        guard blockedAgents.contains(agentId) else { return }
        guard let agent = await audience.agentSummary(agentId), agent.kind == TreeComposer.claudeKind else { return }
        await secondaryNeedsInput(agentId, agent: agent)
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
        let now = clock.now()
        let payload: Data
        do {
            payload = try ApnsAlertPush(
                title: PushAlertText.title(kind, workspaceLabel: summary?.workspaceLabel, provider: provider),
                body: body,
                threadId: agentId,
                category: category ?? kind.category,
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
        pruneCardAlerts(at: now)
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
            let key = CardAlertKey(device: recipient.device, agentId: agentId, kind: kind)
            guard recipient.hasCard, missedCardAlerts.removeValue(forKey: key) == nil else {
                deliver(request, to: recipient.device, kind: kind, client: sender.client)
                continue
            }
            parkedAlerts[key] = ParkedAlert(request: request, at: now)
        }
    }

    private func pruneCardAlerts(at now: Date) {
        let window = configuration.cardAlertWindow
        parkedAlerts = parkedAlerts.filter { now.timeIntervalSince($0.value.at) < window }
        missedCardAlerts = missedCardAlerts.filter { now.timeIntervalSince($0.value) < window }
    }

    private func recipients(for kind: PushAlertKind, agentId: AgentID) async -> [Recipient] {
        let records: [DeviceRecord]
        do {
            records = try await devices.devices()
        } catch {
            pushLogger.error("failed to read devices: \(Self.describe(error), privacy: .public)")
            return []
        }
        let cardIsHeldByAnotherAgent = await liveActivityCards?.cardHolder().map { $0 != agentId } ?? false
        let candidates = records.filter { record in
            record.apns != nil && (kind != .turnDone || record.preferences.turnDoneAlerts)
        }
        guard !candidates.isEmpty else { return [] }
        let foreground = await audience.foregroundDevices(for: agentId)
        var tokens: Set<String> = []
        var recipients: [Recipient] = []
        for record in candidates where !foreground.contains(record.id) {
            guard let apns = record.apns, ApnsRequest.isValidDeviceToken(apns.token), tokens.insert(apns.token.lowercased()).inserted else {
                continue
            }
            recipients.append(Recipient(device: record.id, apns: apns, hasCard: record.hasLiveActivityCard && !cardIsHeldByAnotherAgent))
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

    private func deliver(_ request: ApnsRequest, to device: DeviceID, kind: PushAlertKind, client: ApnsClient) {
        guard !isShutDown else { return }
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
