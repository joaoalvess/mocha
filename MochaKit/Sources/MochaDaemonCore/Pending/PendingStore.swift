import Foundation
import MochaProtocol
import os

let pendingLogger = Logger(subsystem: "com.joaoalves.mocha", category: "pending")

public protocol PendingProviding: Sendable {
    var requests: [PendingRequest] { get async }
    func updates() -> AsyncStream<[PendingRequest]>
    func respond(to requestId: RequestID, with response: PendingResponse) async throws(PendingRespondError)
}

public struct PendingStoreConfiguration: Sendable {
    public var answerDeadline: Duration
    public var transcriptPageLimit: Int

    public init(answerDeadline: Duration = .seconds(580), transcriptPageLimit: Int = 20) {
        self.answerDeadline = answerDeadline
        self.transcriptPageLimit = transcriptPageLimit
    }
}

public enum PendingEndReason: Sendable, Equatable {
    case phone
    case connectionClosed
    case terminalStatus
    case terminalTranscript
    case sessionHook(HookEventName)
    case timeout
    case shutdown

    var logLabel: String {
        switch self {
        case .phone: "phone"
        case .connectionClosed: "connection closed"
        case .terminalStatus: "terminal (Herdr status)"
        case .terminalTranscript: "terminal (transcript)"
        case .sessionHook(let name): "hook \(name.rawValue)"
        case .timeout: "timeout"
        case .shutdown: "shutdown"
        }
    }
}

public struct PendingResolution: Sendable, Equatable {
    public let requestId: RequestID
    public let sessionId: String
    public let reason: PendingEndReason

    public init(requestId: RequestID, sessionId: String, reason: PendingEndReason) {
        self.requestId = requestId
        self.sessionId = sessionId
        self.reason = reason
    }
}

public actor PendingStore: PendingProviding, PermissionRequestHolding {
    static let resolutionHistory = 16

    private struct Entry {
        var request: PendingRequest
        let sessionId: String
        let toolName: String
        let toolInput: OrderedJSON
        var watch: ToolResultWatch?
        var sawBlocked = false
        var deadline: Task<Void, Never>?
        var transcript: Task<Void, Never>?

        func cancelTasks() {
            deadline?.cancel()
            transcript?.cancel()
        }
    }

    private let herdr: any HerdrBridging
    private let transcripts: any TranscriptProviding
    private let clock: any GatewayClock
    private let configuration: PendingStoreConfiguration
    private let broadcast = LatestValueBroadcast<[PendingRequest]>([])

    private var entries: [RequestID: Entry] = [:]
    private var decided: [RequestID: OrderedJSON] = [:]
    private var waiters: [RequestID: CheckedContinuation<OrderedJSON, Never>] = [:]
    private var herdrEvents: Task<Void, Never>?
    private var isShutDown = false
    private(set) var observedEvents = 0
    private(set) var recentResolutions: [PendingResolution] = []

    public init(
        herdr: any HerdrBridging,
        transcripts: any TranscriptProviding,
        clock: any GatewayClock = SystemGatewayClock(),
        configuration: PendingStoreConfiguration = PendingStoreConfiguration()
    ) {
        self.herdr = herdr
        self.transcripts = transcripts
        self.clock = clock
        self.configuration = configuration
    }

    public var requests: [PendingRequest] {
        entries.values.map(\.request).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public nonisolated func updates() -> AsyncStream<[PendingRequest]> {
        broadcast.subscribe()
    }

    public func start() {
        guard herdrEvents == nil, !isShutDown else { return }
        let events = herdr.events()
        herdrEvents = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.apply(event)
            }
        }
    }

    public func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        herdrEvents?.cancel()
        herdrEvents = nil
        for id in Array(entries.keys) {
            finish(id, reply: PendingHookReply.noDecision, reason: .shutdown, publishing: false)
        }
        for waiter in waiters.values {
            waiter.resume(returning: PendingHookReply.noDecision)
        }
        waiters.removeAll()
        decided.removeAll()
        broadcast.publish([])
        broadcast.finish()
    }

    public func observe(_ hook: ReceivedHook) {
        let name = hook.event.name
        guard name == .userPromptSubmit || name == .stop else { return }
        let ids = ids(ofSession: hook.event.context.sessionId)
        guard !ids.isEmpty else { return }
        for id in ids {
            finish(id, reply: PendingHookReply.noDecision, reason: .sessionHook(name), publishing: false)
        }
        publish()
    }

    public func open(_ hook: ReceivedHook, request: PermissionRequestHook) -> RequestID {
        let context = hook.event.context
        for id in ids(ofSession: context.sessionId) {
            finish(id, reply: PendingHookReply.noDecision, reason: .sessionHook(.permissionRequest), publishing: false)
        }
        let id = UUID().uuidString.lowercased()
        guard !isShutDown else { return id }
        var entry = Entry(
            request: PendingRequest(id: id, agentId: hook.agentId, createdAt: hook.receivedAt, kind: PendingRequestFactory.kind(for: request)),
            sessionId: context.sessionId,
            toolName: request.toolName,
            toolInput: request.toolInput
        )
        entry.deadline = scheduleDeadline(for: id)
        if context.subagentId == nil {
            entry.transcript = watchTranscript(for: id, session: TranscriptSession(sessionId: context.sessionId, transcriptPath: context.transcriptPath))
        }
        entries[id] = entry
        pendingLogger.info("request \(id, privacy: .public) (\(entry.request.kind.type, privacy: .public) \(request.toolName, privacy: .public)) opened for \(hook.agentId, privacy: .public)")
        publish()
        return id
    }

    public nonisolated func reply(to requestId: RequestID) async -> OrderedJSON {
        await withTaskCancellationHandler {
            await awaitReply(requestId)
        } onCancel: {
            Task { await self.connectionClosed(requestId) }
        }
    }

    public func respond(to requestId: RequestID, with response: PendingResponse) throws(PendingRespondError) {
        guard let entry = entries[requestId] else { throw .requestNotFound }
        let reply = try PendingHookReply.reply(to: response, kind: entry.request.kind, toolInput: entry.toolInput)
        finish(requestId, reply: reply, reason: .phone)
    }

    func contains(_ requestId: RequestID) -> Bool {
        entries[requestId] != nil
    }

    func isWatchingTranscript(_ requestId: RequestID) -> Bool {
        entries[requestId]?.watch != nil
    }

    func connectionClosed(_ requestId: RequestID) {
        if entries[requestId] != nil {
            finish(requestId, reply: PendingHookReply.noDecision, reason: .connectionClosed)
        }
        decided[requestId] = nil
    }

    private func awaitReply(_ requestId: RequestID) async -> OrderedJSON {
        if let reply = decided.removeValue(forKey: requestId) {
            return reply
        }
        guard entries[requestId] != nil else { return PendingHookReply.noDecision }
        return await withCheckedContinuation { continuation in
            waiters.updateValue(continuation, forKey: requestId)?.resume(returning: PendingHookReply.noDecision)
        }
    }

    private func apply(_ event: HerdrBridgeEvent) {
        observedEvents += 1
        switch event {
        case .agentStatus(let agentId, let status, _):
            for (id, entry) in entries where entry.request.agentId == agentId {
                if status == .blocked {
                    entries[id]?.sawBlocked = true
                } else if entry.sawBlocked {
                    finish(id, reply: PendingHookReply.noDecision, reason: .terminalStatus)
                }
            }
        case .paneMoved(let from, let to):
            let moved = entries.filter { $0.value.request.agentId == from }.map(\.key)
            guard !moved.isEmpty else { return }
            for id in moved {
                entries[id]?.request.agentId = to
            }
            publish()
        case .snapshot, .treeChanged, .sessionChanged, .availability:
            break
        }
    }

    private func transcriptOpened(_ requestId: RequestID, items: [ChatItem]) -> Bool {
        guard let entry = entries[requestId] else { return false }
        entries[requestId]?.watch = ToolResultWatch(toolName: entry.toolName, items: items)
        return true
    }

    private func transcriptChanged(_ requestId: RequestID, _ delta: TranscriptDelta) -> Bool {
        guard var watch = entries[requestId]?.watch else { return false }
        observedEvents += 1
        let answered = watch.observe(delta)
        entries[requestId]?.watch = watch
        guard answered else { return true }
        finish(requestId, reply: PendingHookReply.noDecision, reason: .terminalTranscript)
        return false
    }

    private func deadlineElapsed(_ requestId: RequestID) {
        guard entries[requestId] != nil else { return }
        finish(requestId, reply: PendingHookReply.noDecision, reason: .timeout)
    }

    private func scheduleDeadline(for requestId: RequestID) -> Task<Void, Never> {
        let clock = clock
        let delay = configuration.answerDeadline
        return Task { [weak self] in
            guard (try? await clock.sleep(for: delay)) != nil else { return }
            await self?.deadlineElapsed(requestId)
        }
    }

    private func watchTranscript(for requestId: RequestID, session: TranscriptSession) -> Task<Void, Never> {
        let transcripts = transcripts
        let limit = configuration.transcriptPageLimit
        return Task { [weak self] in
            guard let subscription = try? await transcripts.open(session: session, limit: limit) else { return }
            defer { subscription.cancel() }
            guard let self, await self.transcriptOpened(requestId, items: subscription.page.items) else { return }
            for await delta in subscription.deltas {
                guard await self.transcriptChanged(requestId, delta) else { return }
            }
        }
    }

    private func ids(ofSession sessionId: String) -> [RequestID] {
        entries.filter { $0.value.sessionId == sessionId }.map(\.key)
    }

    private func finish(_ requestId: RequestID, reply: OrderedJSON, reason: PendingEndReason, publishing: Bool = true) {
        guard let entry = entries.removeValue(forKey: requestId) else { return }
        entry.cancelTasks()
        if let waiter = waiters.removeValue(forKey: requestId) {
            waiter.resume(returning: reply)
        } else {
            decided[requestId] = reply
        }
        recentResolutions.append(PendingResolution(requestId: requestId, sessionId: entry.sessionId, reason: reason))
        if recentResolutions.count > Self.resolutionHistory {
            recentResolutions.removeFirst(recentResolutions.count - Self.resolutionHistory)
        }
        pendingLogger.info("request \(requestId, privacy: .public) of \(entry.request.agentId, privacy: .public) ended: \(reason.logLabel, privacy: .public)")
        if publishing {
            publish()
        }
    }

    private func publish() {
        broadcast.publish(requests)
    }
}
