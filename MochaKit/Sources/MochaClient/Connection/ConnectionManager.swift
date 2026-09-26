import Foundation
import MochaProtocol
import os

let connectionLogger = Logger(subsystem: "com.joaoalves.mocha", category: "connection")

public actor ConnectionManager: ServerConnection {
    public nonisolated let messages: AsyncStream<ServerEnvelope>
    public nonisolated let states: AsyncStream<ConnectionState>

    static let badGatewayStatus = 502
    static let protocolErrorCloseCode = 1002
    static let policyViolationCloseCode = 1008

    private struct Session {
        let generation: Int
        let channel: any WebSocketChannel
        let helloId: String
        var pairing: PairingLink?
        var isOpen = false
        var receiveTask: Task<Void, Never>?
        var heartbeatTask: Task<Void, Never>?
        var pendingPings: [Int: Duration] = [:]
        var nextPing = 0
        var unpairRequestId: String?
    }

    private let messageContinuation: AsyncStream<ServerEnvelope>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    private let configuration: ConnectionConfiguration
    private let tokenStore: any TokenStore
    private let apnsRegistration: any ApnsRegistrationSource
    private let transport: any WebSocketTransport
    private let clock: any ConnectionClock
    private let pathMonitor: any NetworkPathMonitoring
    private let jitter: @Sendable () -> Double
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var state: ConnectionState = .idle
    private var isActive = false
    private var isLoadingCredential = false
    private var credential: DeviceCredential?
    private var session: Session?
    private var generation = 0
    private var helloCount = 0
    private var backoff = ReconnectBackoff()
    private var retryTask: Task<Void, Never>?
    private var pathTask: Task<Void, Never>?
    private var lastPath: NetworkPathUpdate?

    public init(
        configuration: ConnectionConfiguration,
        tokenStore: any TokenStore,
        apnsRegistration: any ApnsRegistrationSource = NoApnsRegistration(),
        transport: any WebSocketTransport = URLSessionWebSocketTransport(),
        clock: any ConnectionClock = SystemConnectionClock(),
        pathMonitor: any NetworkPathMonitoring = SystemNetworkPathMonitor(),
        jitter: @escaping @Sendable () -> Double = ReconnectBackoff.randomJitter
    ) {
        let (messages, messageContinuation) = AsyncStream.makeStream(of: ServerEnvelope.self)
        let (states, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
        stateContinuation.yield(.idle)
        self.messages = messages
        self.messageContinuation = messageContinuation
        self.states = states
        self.stateContinuation = stateContinuation
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.apnsRegistration = apnsRegistration
        self.transport = transport
        self.clock = clock
        self.pathMonitor = pathMonitor
        self.jitter = jitter
    }

    deinit {
        messageContinuation.finish()
        stateContinuation.finish()
        retryTask?.cancel()
        pathTask?.cancel()
        session?.receiveTask?.cancel()
        session?.heartbeatTask?.cancel()
        session?.channel.close(.goingAway)
    }

    public func start() async {
        guard !isLoadingCredential, session == nil, retryTask == nil else { return }
        switch state {
        case .idle, .failed:
            break
        case .connecting, .connected, .waitingToRetry, .pairingRequired:
            return
        }
        activate()
        if credential == nil {
            isLoadingCredential = true
            credential = await loadCredential()
            isLoadingCredential = false
            guard isActive, session == nil, retryTask == nil else { return }
        }
        reconnect()
    }

    public func stop() async {
        isActive = false
        pathTask?.cancel()
        pathTask = nil
        lastPath = nil
        retryTask?.cancel()
        retryTask = nil
        generation += 1
        closeSession(.goingAway)
        setState(.idle)
    }

    public func pair(_ link: PairingLink) async {
        activate()
        open(link.url, pairing: link)
    }

    public func send(_ message: ClientMessage, id: String) async throws {
        guard state == .connected, let current = session, current.isOpen else {
            throw ServerConnectionError.notConnected
        }
        guard let text = encode(ClientEnvelope(id: id, message: message)) else {
            throw ServerConnectionError.notConnected
        }
        if case .unpair = message {
            session?.unpairRequestId = id
        }
        do {
            try await current.channel.send(text)
        } catch {
            throw ServerConnectionError.notConnected
        }
    }

    private func activate() {
        isActive = true
        guard pathTask == nil else { return }
        let updates = pathMonitor.updates()
        pathTask = Task { [weak self] in
            for await update in updates {
                await self?.pathChanged(update)
            }
        }
    }

    private func loadCredential() async -> DeviceCredential? {
        do {
            return try await tokenStore.load()
        } catch {
            connectionLogger.error("could not read the device credential: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func reconnect() {
        guard let credential else {
            setState(.pairingRequired(nil))
            return
        }
        open(credential.url, pairing: nil)
    }

    private func open(_ url: URL, pairing: PairingLink?) {
        retryTask?.cancel()
        retryTask = nil
        closeSession(.normalClosure)
        generation += 1
        helloCount += 1
        let generation = generation
        let helloId = "hello-\(helloCount)"
        let channel = transport.connect(to: url)
        var session = Session(generation: generation, channel: channel, helloId: helloId, pairing: pairing)
        session.receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                let result: Result<String?, any Error>
                do {
                    result = .success(try await channel.receive())
                } catch {
                    result = .failure(error)
                }
                guard let self, await self.handle(result, generation: generation) else { return }
            }
        }
        self.session = session
        setState(.connecting)
        let hello = HelloPayload(
            deviceToken: pairing == nil ? credential?.token : nil,
            pairingCode: pairing?.code,
            deviceName: configuration.deviceName,
            appVersion: configuration.appVersion,
            apns: apnsRegistration.currentRegistration()
        )
        guard let text = encode(ClientEnvelope(id: helloId, message: .hello(hello))) else {
            lose(.unreachable)
            return
        }
        Task { [weak self] in
            do {
                try await channel.send(text)
                await self?.markOpen(generation: generation)
            } catch {
                await self?.channelFailed(error, generation: generation)
            }
        }
    }

    private func handle(_ result: Result<String?, any Error>, generation: Int) async -> Bool {
        guard session?.generation == generation else { return false }
        switch result {
        case .failure(let error):
            channelFailed(error, generation: generation)
            return false
        case .success(nil):
            return true
        case .success(let text?):
            markOpen(generation: generation)
            await receive(text, generation: generation)
            return session?.generation == generation
        }
    }

    private func receive(_ text: String, generation: Int) async {
        guard let current = session else { return }
        let envelope: ServerEnvelope
        do {
            envelope = try decoder.decode(ServerEnvelope.self, from: Data(text.utf8))
        } catch {
            connectionLogger.error("ignored an undecodable server message: \(String(describing: error), privacy: .public)")
            return
        }
        if envelope.id == current.helloId {
            switch envelope.message {
            case .helloOk(let payload):
                await accept(payload, envelope: envelope, generation: generation)
            case .error(let code, _):
                refuse(code)
            default:
                messageContinuation.yield(envelope)
            }
            return
        }
        if envelope.id == nil, case .error(let code, _) = envelope.message, let problem = Self.pairingProblem(for: code) {
            requirePairing(problem)
            return
        }
        messageContinuation.yield(envelope)
        if let unpairId = current.unpairRequestId, envelope.id == unpairId, case .ack = envelope.message {
            await completeUnpair(generation: generation)
        }
    }

    private func accept(_ payload: HelloOkPayload, envelope: ServerEnvelope, generation: Int) async {
        if let pairing = session?.pairing {
            guard let token = payload.deviceToken else {
                requirePairing(.pairingExpired)
                return
            }
            let paired = DeviceCredential(url: pairing.url, token: token)
            credential = paired
            session?.pairing = nil
            do {
                try await tokenStore.save(paired)
            } catch {
                connectionLogger.error("could not save the device credential: \(String(describing: error), privacy: .public)")
            }
            guard session?.generation == generation else { return }
        }
        backoff.reset()
        messageContinuation.yield(envelope)
        setState(.connected)
    }

    private func refuse(_ code: ProtocolErrorCode) {
        if let problem = Self.pairingProblem(for: code) {
            requirePairing(problem)
        } else if code == .protocolMismatch {
            fail(.protocolMismatch)
        } else {
            connectionLogger.error("hello refused with \(code.rawValue, privacy: .public)")
            lose(.unreachable)
        }
    }

    private func completeUnpair(generation: Int) async {
        credential = nil
        do {
            try await tokenStore.delete()
        } catch {
            connectionLogger.error("could not delete the device credential: \(String(describing: error), privacy: .public)")
        }
        guard session?.generation == generation else { return }
        requirePairing(nil)
    }

    private func channelFailed(_ error: any Error, generation: Int) {
        guard let current = session, current.generation == generation else { return }
        let failure = current.channel.failure(for: error)
        connectionLogger.notice("connection \(generation, privacy: .public) failed: \(String(describing: failure), privacy: .public)")
        switch failure {
        case .handshake(status: Self.badGatewayStatus):
            lose(.daemonNotRunning)
        case .closed(code: Self.policyViolationCloseCode):
            requirePairing(.unauthorized)
        case .closed(code: Self.protocolErrorCloseCode):
            fail(.protocolMismatch)
        case .handshake, .closed, .network:
            lose(.unreachable)
        }
    }

    private func markOpen(generation: Int) {
        guard var current = session, current.generation == generation, !current.isOpen else { return }
        current.isOpen = true
        let interval = configuration.pingInterval
        current.heartbeatTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
                guard let self, await self.heartbeat(generation: generation) else { return }
            }
        }
        session = current
    }

    private func heartbeat(generation: Int) -> Bool {
        guard let current = session, current.generation == generation else { return false }
        if let oldest = current.pendingPings.values.min(), clock.now - oldest >= configuration.pongTimeout {
            connectionLogger.notice("no pong for \(String(describing: self.clock.now - oldest), privacy: .public); the connection is dead")
            lose(.unreachable)
            return false
        }
        sendPing()
        return true
    }

    private func sendPing() {
        guard var current = session, current.isOpen else { return }
        let number = current.nextPing
        current.nextPing += 1
        current.pendingPings[number] = clock.now
        session = current
        let generation = current.generation
        current.channel.sendPing { [weak self] received in
            guard received else { return }
            Task { await self?.pongReceived(number, generation: generation) }
        }
    }

    private func pongReceived(_ number: Int, generation: Int) {
        guard session?.generation == generation else { return }
        session?.pendingPings[number] = nil
    }

    private func pathChanged(_ update: NetworkPathUpdate) {
        let previous = lastPath
        lastPath = update
        guard let previous, previous != update else { return }
        if case .waitingToRetry = state, update.isSatisfied {
            retryTask?.cancel()
            retryTask = nil
            reconnect()
        } else {
            sendPing()
        }
    }

    private func lose(_ problem: ConnectionProblem) {
        let wasPairing = session?.pairing != nil
        closeSession(.goingAway)
        if wasPairing {
            setState(.pairingRequired(problem))
        } else if isActive {
            scheduleRetry(problem)
        } else {
            setState(.idle)
        }
    }

    private func requirePairing(_ problem: ConnectionProblem?) {
        retryTask?.cancel()
        retryTask = nil
        closeSession(.normalClosure)
        setState(.pairingRequired(problem))
    }

    private func fail(_ problem: ConnectionProblem) {
        retryTask?.cancel()
        retryTask = nil
        closeSession(.normalClosure)
        setState(.failed(problem))
    }

    private func scheduleRetry(_ problem: ConnectionProblem) {
        let delay = backoff.nextDelay(jitter: jitter())
        setState(.waitingToRetry(problem))
        let generation = generation
        retryTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            await self?.retry(generation: generation)
        }
    }

    private func retry(generation: Int) {
        guard generation == self.generation, session == nil, isActive, case .waitingToRetry = state else { return }
        retryTask = nil
        reconnect()
    }

    private func closeSession(_ code: URLSessionWebSocketTask.CloseCode) {
        guard let current = session else { return }
        session = nil
        current.receiveTask?.cancel()
        current.heartbeatTask?.cancel()
        current.channel.close(code)
    }

    private func setState(_ newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        stateContinuation.yield(newState)
    }

    private func encode(_ envelope: ClientEnvelope) -> String? {
        guard let data = try? encoder.encode(envelope) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func pairingProblem(for code: ProtocolErrorCode) -> ConnectionProblem? {
        switch code {
        case .unauthorized: .unauthorized
        case .pairingExpired: .pairingExpired
        default: nil
        }
    }
}
