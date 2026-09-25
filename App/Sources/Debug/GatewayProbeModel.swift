#if DEBUG
import CryptoKit
import Foundation
import Network
import Observation
import SwiftUI
import os

struct GatewayProbeEntry: Identifiable, Sendable {
    let id: Int
    let date: Date
    let text: String
}

@MainActor
@Observable
final class GatewayProbeModel {
    enum Phase: Equatable {
        case stopped
        case connecting(attempt: Int)
        case connected
        case waiting(attempt: Int, delay: Double)
        case background
    }

    static let defaultURL = "wss://mac-mini.tail1234.ts.net/v1"
    static let echoInterval: Duration = .seconds(2)
    static let lateEchoWarning: Duration = .seconds(5)
    static let deadEchoLimit: Duration = .seconds(15)
    static let maxEntries = 500
    static let postBodySize = 1 << 20

    private(set) var phase: Phase = .stopped
    private(set) var entries: [GatewayProbeEntry] = []
    private(set) var network = "desconhecida"
    private(set) var roundTripsByNetwork: [String: [Double]] = [:]
    private(set) var lastRoundTripMs: Double?
    private(set) var isForeground = false
    private(set) var wantsConnection = true
    var autoEcho = true
    let url: URL?

    @ObservationIgnored private let logger = Logger(subsystem: "com.joaoalves.mocha", category: "gateway-probe")
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var connectStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var lostAt: ContinuousClock.Instant?
    @ObservationIgnored private var lossReason: String?
    @ObservationIgnored private var attempts = 0
    @ObservationIgnored private var nextSeq = 1
    @ObservationIgnored private var pendingEchoes: [Int: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var lateEchoWarned: Set<Int> = []
    @ObservationIgnored private var pendingReconnect: GatewayProbeReconnect?
    @ObservationIgnored private var unsentLog: [String] = []
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var echoTask: Task<Void, Never>?
    @ObservationIgnored private var sessionEventsTask: Task<Void, Never>?
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var entryCounter = 0
    @ObservationIgnored private var ranHttpChecks = false

    init() {
        url = URL(string: UserDefaults.standard.string(forKey: "gatewayURL") ?? Self.defaultURL)
    }

    var httpBaseURL: URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "ws" ? "http" : "https"
        components.path = ""
        components.query = nil
        return components.url
    }

    func start() {
        guard session == nil else { return }
        let delegate = GatewayProbeSessionDelegate()
        session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        sessionEventsTask = Task { [weak self] in
            for await event in delegate.events {
                self?.handle(event)
            }
        }
        pathTask = Task { [weak self] in
            for await path in NWPathMonitor() {
                self?.pathChanged(path)
            }
        }
        record("sonda iniciada, alvo \(url?.absoluteString ?? "URL inválida")")
    }

    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        start()
        switch scenePhase {
        case .active:
            isForeground = true
            record("app ativo")
            if wantsConnection, task == nil {
                reconnectTask?.cancel()
                connect()
            }
        case .inactive:
            record("app inativo")
        case .background:
            isForeground = false
            record("app em background: fechando o WebSocket")
            closeCurrent(code: .goingAway, reason: "background")
            phase = .background
        @unknown default:
            break
        }
    }

    func toggleConnection() {
        if wantsConnection {
            wantsConnection = false
            record("desconectado pelo usuário")
            closeCurrent(code: .normalClosure, reason: "usuário")
            lostAt = nil
            lossReason = nil
            phase = .stopped
        } else {
            wantsConnection = true
            attempts = 0
            connect()
        }
    }

    func clearLog() {
        entries.removeAll()
        roundTripsByNetwork.removeAll()
        lastRoundTripMs = nil
    }

    func unpinProbe() {
        UserDefaults.standard.removeObject(forKey: "probe")
        record("sonda desafixada: o próximo launch sem -probe abre o app normal")
    }

    func pinProbe() {
        UserDefaults.standard.set("gateway", forKey: "probe")
    }

    func sendEcho() {
        guard let task, phase == .connected else { return }
        let seq = nextSeq
        nextSeq += 1
        let echo = GatewayProbeEcho(
            seq: seq,
            network: network,
            previousRoundTripMs: lastRoundTripMs.map { ($0 * 100).rounded() / 100 },
            reconnect: pendingReconnect,
            log: unsentLog.isEmpty ? nil : unsentLog
        )
        guard let data = try? JSONEncoder().encode(echo) else { return }
        pendingReconnect = nil
        unsentLog.removeAll()
        pendingEchoes[seq] = .now
        let text = String(decoding: data, as: UTF8.self)
        Task { [weak self] in
            do {
                try await task.send(.string(text))
            } catch {
                self?.lost(task, reason: "falha no envio", detail: GatewayProbeSessionDelegate.describe(error))
            }
        }
    }

    func checkHealth() async {
        guard let session, let url = httpBaseURL?.appending(path: "v1/health") else { return }
        let started = ContinuousClock.now
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            record("health \(status) em \(Self.milliseconds(since: started)) ms: \(String(decoding: data, as: UTF8.self))")
        } catch {
            record("health falhou: \(GatewayProbeSessionDelegate.describe(error))")
        }
    }

    func postBody() async {
        guard let session, let url = httpBaseURL?.appending(path: "spike/echo").appending(queryItems: [URLQueryItem(name: "origem", value: "sonda")]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer sonda-s5", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let body = Data((0..<Self.postBodySize).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let expectedHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let started = ContinuousClock.now
        do {
            let (data, response) = try await session.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let elapsed = Self.milliseconds(since: started)
            guard status == 200, let echo = try? JSONDecoder().decode(GatewayProbeSpikeEcho.self, from: data) else {
                record("POST \(body.count)B → \(status) em \(elapsed) ms")
                return
            }
            let hashMatches = echo.bodySha256 == expectedHash ? "ok" : "divergente"
            record("POST \(body.count)B → 200 em \(elapsed) ms: recebidos \(echo.bodyBytes)B (sha \(hashMatches)), Content-Length=\(echo.header("Content-Length") ?? "-"), Transfer-Encoding=\(echo.header("Transfer-Encoding") ?? "-"), Authorization \(echo.header("Authorization") == "Bearer sonda-s5" ? "chegou" : "não chegou"), query=\(echo.query ?? "-")")
        } catch {
            record("POST falhou: \(GatewayProbeSessionDelegate.describe(error))")
        }
    }

    private func connect() {
        guard task == nil, let session, let url, wantsConnection, isForeground else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        attempts += 1
        let task = session.webSocketTask(with: url)
        self.task = task
        connectStartedAt = .now
        phase = .connecting(attempt: attempts)
        record("conectando (tentativa \(attempts), rede \(network))")
        task.resume()
        Task { [weak self] in
            await self?.receiveLoop(task)
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while true {
            do {
                let message = try await task.receive()
                guard task === self.task else { return }
                handle(message)
            } catch {
                lost(task, reason: "falha na leitura", detail: GatewayProbeSessionDelegate.describe(error))
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let echo = try? JSONDecoder().decode(GatewayProbeEcho.self, from: Data(text.utf8)) else {
                record("mensagem de texto inesperada: \(text.prefix(120))")
                return
            }
            guard let sentAt = pendingEchoes.removeValue(forKey: echo.seq) else {
                record("eco #\(echo.seq) sem envio pendente")
                return
            }
            lateEchoWarned.remove(echo.seq)
            let roundTrip = Double((ContinuousClock.now - sentAt) / .microseconds(1)) / 1000
            lastRoundTripMs = roundTrip
            roundTripsByNetwork[echo.network, default: []].append(roundTrip)
            record(String(format: "eco #%d em %.1f ms (%@)", echo.seq, roundTrip, echo.network), mirror: false)
        case .data(let data):
            record("mensagem binária de \(data.count)B")
        @unknown default:
            record("mensagem desconhecida")
        }
    }

    private func handle(_ event: GatewayProbeSessionEvent) {
        switch event {
        case .opened(let id):
            guard id == task?.taskIdentifier else { return }
            opened()
        case .closed(let id, let code, let reason):
            record("close recebido do servidor na tarefa \(id): código \(code) motivo \(reason ?? "-")")
            if id == task?.taskIdentifier, let task {
                lost(task, reason: "close \(code)", detail: "servidor fechou")
            }
        case .completed(let id, let status, let error):
            record("tarefa \(id) terminou: status HTTP \(status.map(String.init) ?? "-"), erro \(error ?? "nenhum")")
            if id == task?.taskIdentifier, let task {
                lost(task, reason: "tarefa terminou", detail: error ?? "sem erro")
            }
        case .metrics(let id, let protocolName):
            record("tarefa \(id) usou \(protocolName ?? "protocolo desconhecido")")
        }
    }

    private func opened() {
        let now = ContinuousClock.now
        let handshake = connectStartedAt.map { Self.milliseconds(from: $0, to: now) } ?? 0
        phase = .connected
        if let lostAt {
            let downtime = Self.milliseconds(from: lostAt, to: now)
            let reason = lossReason ?? "desconhecido"
            pendingReconnect = GatewayProbeReconnect(reason: reason, downtimeMs: downtime, handshakeMs: handshake, attempts: attempts)
            record("reconectado (\(reason)): fora do ar \(downtime) ms, handshake \(handshake) ms, \(attempts) tentativa(s)")
        } else {
            pendingReconnect = GatewayProbeReconnect(reason: "início", downtimeMs: 0, handshakeMs: handshake, attempts: attempts)
            record("conectado: handshake \(handshake) ms")
        }
        lostAt = nil
        lossReason = nil
        attempts = 0
        startEchoLoop()
        sendEcho()
        runHttpChecksOnce()
    }

    private func runHttpChecksOnce() {
        guard !ranHttpChecks else { return }
        ranHttpChecks = true
        Task { [weak self] in
            await self?.checkHealth()
            await self?.postBody()
        }
    }

    private func lost(_ lostTask: URLSessionWebSocketTask, reason: String, detail: String) {
        guard lostTask === task else { return }
        record("conexão perdida (\(reason)): \(detail)")
        lostTask.cancel(with: .goingAway, reason: nil)
        tearDown()
        if lostAt == nil {
            lostAt = .now
            lossReason = reason
        }
        scheduleReconnect()
    }

    private func closeCurrent(code: URLSessionWebSocketTask.CloseCode, reason: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        guard let task else { return }
        task.cancel(with: code, reason: Data(reason.utf8))
        tearDown()
        lostAt = .now
        lossReason = reason
        attempts = 0
    }

    private func tearDown() {
        task = nil
        echoTask?.cancel()
        echoTask = nil
        pendingEchoes.removeAll()
        lateEchoWarned.removeAll()
    }

    private func scheduleReconnect() {
        guard wantsConnection, isForeground else {
            phase = isForeground ? .stopped : .background
            return
        }
        let base = 0.5 * pow(2, Double(attempts))
        let delay = (min(8, base * Double.random(in: 0.8...1.2)) * 100).rounded() / 100
        phase = .waiting(attempt: attempts + 1, delay: delay)
        record("nova tentativa em \(delay) s")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func startEchoLoop() {
        echoTask?.cancel()
        echoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.echoInterval)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let task, phase == .connected else { return }
        let now = ContinuousClock.now
        for (seq, sentAt) in pendingEchoes.sorted(by: { $0.key < $1.key }) {
            let age = now - sentAt
            if age > Self.deadEchoLimit {
                lost(task, reason: "sem eco", detail: "eco #\(seq) sem resposta há \(Self.milliseconds(from: sentAt, to: now)) ms")
                return
            }
            if age > Self.lateEchoWarning, !lateEchoWarned.contains(seq) {
                lateEchoWarned.insert(seq)
                record("eco #\(seq) atrasado: \(Self.milliseconds(from: sentAt, to: now)) ms sem resposta")
            }
        }
        if autoEcho {
            sendEcho()
        }
    }

    private func pathChanged(_ path: NWPath) {
        let label = Self.label(for: path)
        let interfaces = path.availableInterfaces.map { "\($0.name)(\(Self.label(for: $0.type)))" }.joined(separator: " ")
        guard label != network else { return }
        record("rede: \(network) → \(label) [\(interfaces)]")
        network = label
        if case .waiting = phase, path.status == .satisfied {
            record("rede disponível: tentando agora")
            connect()
        }
    }

    private func record(_ text: String, mirror: Bool = true) {
        let date = Date.now
        entryCounter += 1
        entries.insert(GatewayProbeEntry(id: entryCounter, date: date, text: text), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        logger.info("\(text, privacy: .public)")
        if mirror {
            unsentLog.append("\(date.formatted(Self.timeFormat)) \(text)")
            if unsentLog.count > 50 {
                unsentLog.removeFirst(unsentLog.count - 50)
            }
        }
    }

    static let timeFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current).time(includingFractionalSeconds: true)

    static func label(for path: NWPath) -> String {
        guard path.status == .satisfied else { return "sem rede" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "celular" }
        if path.usesInterfaceType(.wiredEthernet) { return "cabo" }
        let physical = path.availableInterfaces.map(\.type).first { $0 != .other && $0 != .loopback }
        return physical.map { label(for: $0) } ?? "outra"
    }

    static func label(for type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "wifi"
        case .cellular: "celular"
        case .wiredEthernet: "cabo"
        case .loopback: "loopback"
        case .other: "outra"
        @unknown default: "outra"
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        milliseconds(from: start, to: .now)
    }

    static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
        Int((end - start) / .milliseconds(1))
    }
}
#endif
