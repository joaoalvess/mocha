import Foundation
import MochaProtocol

enum CodexServiceError: Error, Sendable, Equatable {
    case unavailable
    case unverifiedAgent
    case noActiveTurn
    case invalidImage
    case requestNotFound
    case invalidResponse
}

struct CodexPaneState: Sendable, Equatable {
    let threadId: String
    var status: AgentStatus
    var title: String?
}

enum CodexServiceUpdate: Sendable {
    case availability(Bool)
    case panes([AgentID: CodexPaneState])
    case thread(String)
    case pending([PendingRequest])
    case usage(UsageSnapshot)
    case turnDone(AgentID, lastMessage: String?)
    case needsInput(PendingRequest)
}

actor CodexService {
    nonisolated let updates: AsyncStream<CodexServiceUpdate>
    let socketPath: String

    private struct Decision {
        let request: PendingRequest
        let connectionId: UUID
        let rpcId: OrderedJSON
        let threadId: String
        let method: String
        let questionIds: Set<String>
    }

    private let continuation: AsyncStream<CodexServiceUpdate>.Continuation
    private let server: CodexAppServer
    private let uploadsDirectory: URL
    private var paneThreads: [AgentID: String] = [:]
    private var paneCwds: [AgentID: String] = [:]
    private var subscribed: Set<String> = []
    private var threadStatuses: [String: AgentStatus] = [:]
    private var threadTitles: [String: String] = [:]
    private var activeTurns: [String: String] = [:]
    private var lastAgentMessages: [String: String] = [:]
    private var matcher = CodexPaneMatcher()
    private var publishedPanes: [AgentID: CodexPaneState] = [:]
    private var decisions: [RequestID: Decision] = [:]
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var stopped = false

    init(socketPath: String, uploadsDirectory: URL) {
        self.socketPath = socketPath
        self.uploadsDirectory = uploadsDirectory
        server = CodexAppServer(socketPath: socketPath)
        (updates, continuation) = AsyncStream.makeStream(of: CodexServiceUpdate.self)
    }

    var isConnected: Bool { get async { await server.isConnected } }
    var pendingRequests: [PendingRequest] { decisions.values.map(\.request).sorted { $0.createdAt < $1.createdAt } }

    func start() {
        guard eventTask == nil else { return }
        stopped = false
        let events = server.events
        eventTask = Task { [weak self] in
            for await event in events { await self?.handle(event) }
        }
        connectTask = Task { [weak self] in
            await self?.connectLoop()
        }
    }

    func stop() async {
        stopped = true
        eventTask?.cancel()
        connectTask?.cancel()
        eventTask = nil
        connectTask = nil
        clearThreads()
        await server.shutdown()
        continuation.finish()
    }

    func expectPane(_ paneId: AgentID, cwd: String, since: Date) {
        paneCwds[paneId] = CodexPaneMatcher.normalized(cwd)
        guard let threadId = matcher.expect(paneId, cwd: cwd, since: since, now: Date()) else { return }
        associate(paneId, threadId: threadId)
    }

    func retainPanes(_ paneIds: Set<AgentID>) {
        let gone = Set(paneThreads.keys).union(paneCwds.keys).subtracting(paneIds)
        guard !gone.isEmpty else { return }
        for paneId in gone {
            if let threadId = paneThreads.removeValue(forKey: paneId) {
                decisions = decisions.filter { $0.value.threadId != threadId }
            }
            paneCwds[paneId] = nil
            matcher.forget(paneId)
        }
        publishPending()
        publishPanes()
    }

    func verify(_ agent: HerdrAgent) async -> Bool {
        await controlThread(for: agent) != nil
    }

    func threadId(for paneId: AgentID) -> String? { paneThreads[paneId] }

    func page(threadId: String, before: String?, limit: Int) async throws -> CodexThreadPage {
        guard await server.isConnected else { throw CodexServiceError.unavailable }
        let metadata = try await server.request("thread/read", params: .object([
            .init("threadId", .string(threadId)), .init("includeTurns", .bool(false)),
        ]))
        var members: [OrderedJSON.Member] = [
            .init("threadId", .string(threadId)),
            .init("itemsView", .string("full")),
            .init("sortDirection", .string("desc")),
            .init("limit", .number(String(min(max(limit, 1), 200)))),
        ]
        if let before { members.append(.init("cursor", .string(before))) }
        let turns: OrderedJSON
        do {
            turns = try await server.request("thread/turns/list", params: .object(members))
        } catch CodexAppServerError.rejected where before == nil {
            turns = .object([])
        }
        guard let page = CodexProjection.page(thread: metadata["thread"] ?? .null, turns: turns) else {
            throw CodexAppServerError.invalidResponse
        }
        return page
    }

    func prompt(_ agent: HerdrAgent, text: String) async throws {
        guard let threadId = await controlThread(for: agent) else { throw CodexServiceError.unverifiedAgent }
        let input = try Self.promptInput(text, uploadsDirectory: uploadsDirectory)
        if let activeTurnId = await activeTurn(threadId) {
            _ = try await server.request("turn/steer", params: .object([
                .init("threadId", .string(threadId)),
                .init("expectedTurnId", .string(activeTurnId)),
                .init("input", .array(input)),
            ]))
        } else {
            _ = try await server.request("turn/start", params: .object([
                .init("threadId", .string(threadId)),
                .init("input", .array(input)),
            ]))
        }
        await subscribe(threadId)
    }

    func interrupt(_ agent: HerdrAgent) async throws {
        guard let threadId = await controlThread(for: agent) else { throw CodexServiceError.unverifiedAgent }
        guard let turnId = await activeTurn(threadId) else { throw CodexServiceError.noActiveTurn }
        _ = try await server.request("turn/interrupt", params: .object([
            .init("threadId", .string(threadId)), .init("turnId", .string(turnId)),
        ]))
    }

    func respond(to requestId: RequestID, with response: PendingResponse) async throws {
        guard let decision = decisions.removeValue(forKey: requestId) else { throw CodexServiceError.requestNotFound }
        publishPending()
        let result: OrderedJSON
        switch (decision.request.kind, response) {
        case (.permission, .allow):
            result = .object([.init("decision", .string("accept"))])
        case (.permission, .deny):
            result = .object([.init("decision", .string("decline"))])
        case (.question, .answers(let answers)) where Set(answers.keys) == decision.questionIds:
            let entries = answers.sorted { $0.key < $1.key }.map { key, value in
                OrderedJSON.Member(key, .object([.init("answers", .array(value.map(OrderedJSON.string)))]))
            }
            result = .object([.init("answers", .object(entries))])
        default:
            decisions[requestId] = decision
            publishPending()
            throw CodexServiceError.invalidResponse
        }
        try await server.respond(to: decision.rpcId, on: decision.connectionId, result: result)
        publishPanes()
    }

    func refreshUsage() async {
        guard let result = try? await server.request("account/rateLimits/read", params: .object([])),
              let snapshot = CodexProjection.usage(result) else { return }
        continuation.yield(.usage(snapshot))
    }

    static func promptInput(_ text: String, uploadsDirectory: URL) throws -> [OrderedJSON] {
        let prefix = "[imagem: "
        let directory = uploadsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var plain: [String] = []
        var imagePaths: [String] = []
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix(prefix), line.hasSuffix("]") else {
                plain.append(line)
                continue
            }
            let path = String(line.dropFirst(prefix.count).dropLast())
            let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard file.deletingLastPathComponent() == directory,
                  ["png", "jpg", "jpeg", "webp"].contains(file.pathExtension.lowercased()),
                  FileManager.default.fileExists(atPath: file.path) else { throw CodexServiceError.invalidImage }
            imagePaths.append(file.path)
        }
        var input: [OrderedJSON] = []
        let body = plain.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            input.append(.object([.init("type", .string("text")), .init("text", .string(body))]))
        }
        input += imagePaths.map { .object([.init("type", .string("localImage")), .init("path", .string($0))]) }
        return input
    }

    private func controlThread(for agent: HerdrAgent) async -> String? {
        guard agent.kind == "codex", await server.isConnected else { return nil }
        if let threadId = paneThreads[agent.paneId] { return threadId }
        guard let id = agent.sessionId, UUID(uuidString: id) != nil else { return nil }
        do {
            let result = try await server.request("thread/read", params: .object([
                .init("threadId", .string(id)), .init("includeTurns", .bool(false)),
            ]))
            guard let threadId = result["thread"]?["id"]?.stringValue, threadId == id,
                  let threadCwd = result["thread"]?["cwd"]?.stringValue,
                  let paneCwd = agent.cwd ?? agent.foregroundCwd,
                  CodexPaneMatcher.normalized(threadCwd) == CodexPaneMatcher.normalized(paneCwd),
                  !paneThreads.values.contains(id)
            else { return nil }
            associate(agent.paneId, threadId: id)
            return id
        } catch {
            return nil
        }
    }

    private func activeTurn(_ threadId: String) async -> String? {
        if let turnId = activeTurns[threadId] { return turnId }
        guard subscribed.contains(threadId) else { return nil }
        return try? await page(threadId: threadId, before: nil, limit: 1).activeTurnId
    }

    private func associate(_ paneId: AgentID, threadId: String) {
        let previous = paneThreads[paneId]
        guard previous != threadId else { return }
        paneThreads[paneId] = threadId
        if let previous {
            decisions = decisions.filter { $0.value.threadId != previous }
            publishPending()
        }
        publishPanes()
        Task { await self.subscribe(threadId) }
    }

    private func subscribe(_ threadId: String) async {
        guard !subscribed.contains(threadId), paneThreads.values.contains(threadId) else { return }
        do {
            _ = try await server.request("thread/resume", params: .object([
                .init("threadId", .string(threadId)), .init("excludeTurns", .bool(true)),
            ]))
            subscribed.insert(threadId)
            continuation.yield(.thread(threadId))
        } catch {}
    }

    private func connectLoop() async {
        while !stopped && !Task.isCancelled {
            if await server.isConnected {
                for threadId in Set(paneThreads.values).subtracting(subscribed) {
                    await subscribe(threadId)
                }
            } else if (try? await server.connect()) != nil {
                continuation.yield(.availability(true))
                await refreshUsage()
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func clearThreads() {
        paneThreads.removeAll()
        paneCwds.removeAll()
        subscribed.removeAll()
        threadStatuses.removeAll()
        threadTitles.removeAll()
        activeTurns.removeAll()
        lastAgentMessages.removeAll()
        matcher.reset()
        decisions.removeAll()
    }

    private func handle(_ event: CodexServerEvent) {
        switch event.method {
        case "mocha/disconnected":
            clearThreads()
            publishPending()
            publishPanes()
            continuation.yield(.availability(false))
            return
        case "serverRequest/resolved":
            let resolved = event.params["requestId"]
            decisions = decisions.filter { $0.value.connectionId != event.connectionId || $0.value.rpcId != resolved }
            publishPending()
            publishPanes()
            return
        default:
            break
        }
        if let requestId = event.requestId {
            addDecision(event, rpcId: requestId)
            return
        }
        let threadId = event.params["threadId"]?.stringValue
        switch event.method {
        case "thread/started":
            threadStarted(event.params["thread"] ?? .null)
        case "thread/status/changed":
            if let threadId { threadStatuses[threadId] = CodexProjection.status(event.params["status"]) }
        case "thread/name/updated":
            if let threadId { threadTitles[threadId] = event.params["threadName"]?.stringValue }
        case "turn/started":
            if let threadId {
                threadStatuses[threadId] = .working
                activeTurns[threadId] = event.params["turn"]?["id"]?.stringValue
            }
        case "turn/completed":
            if let threadId {
                threadStatuses[threadId] = .idle
                activeTurns[threadId] = nil
                if let paneId = paneThreads.first(where: { $0.value == threadId })?.key {
                    continuation.yield(.turnDone(paneId, lastMessage: lastAgentMessages[threadId]))
                }
            }
        case "item/completed":
            if let threadId, event.params["item"]?["type"]?.stringValue == "agentMessage",
               let text = event.params["item"]?["text"]?.stringValue {
                lastAgentMessages[threadId] = text
            }
        case "account/rateLimits/updated":
            if let snapshot = CodexProjection.usage(event.params) { continuation.yield(.usage(snapshot)) }
        default:
            break
        }
        publishPanes()
        if let threadId, paneThreads.values.contains(threadId) {
            continuation.yield(.thread(threadId))
        }
    }

    private func threadStarted(_ thread: OrderedJSON) {
        guard let threadId = thread["id"]?.stringValue, let cwd = thread["cwd"]?.stringValue,
              thread["parentThreadId"]?.stringValue == nil, thread["ephemeral"]?.boolValue != true else { return }
        threadStatuses[threadId] = CodexProjection.status(thread["status"])
        threadTitles[threadId] = thread["name"]?.stringValue
        let at = thread["createdAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date()
        if let paneId = matcher.threadStarted(threadId, cwd: cwd, at: at) {
            associate(paneId, threadId: threadId)
            return
        }
        let normalized = CodexPaneMatcher.normalized(cwd)
        let sameCwd = paneCwds.filter { $0.value == normalized && paneThreads[$0.key] != nil }
        if sameCwd.count == 1, let paneId = sameCwd.first?.key {
            associate(paneId, threadId: threadId)
        }
    }

    private func publishPanes() {
        var panes: [AgentID: CodexPaneState] = [:]
        let blocked = Set(decisions.values.map(\.threadId))
        for (paneId, threadId) in paneThreads {
            let status = blocked.contains(threadId) ? .blocked : threadStatuses[threadId] ?? .idle
            panes[paneId] = CodexPaneState(threadId: threadId, status: status, title: threadTitles[threadId])
        }
        guard panes != publishedPanes else { return }
        publishedPanes = panes
        continuation.yield(.panes(panes))
    }

    private func addDecision(_ event: CodexServerEvent, rpcId: OrderedJSON) {
        guard let threadId = event.params["threadId"]?.stringValue,
              let paneId = paneThreads.first(where: { $0.value == threadId })?.key,
              let itemId = event.params["itemId"]?.stringValue else { return }
        let callback = event.params["approvalId"]?.stringValue ?? rpcId.compactSerialized()
        let requestId = "codex:\(threadId):\(itemId):\(event.method):\(callback)"
        let kind: PendingKind
        var questionIds: Set<String> = []
        switch event.method {
        case "item/commandExecution/requestApproval":
            let summary = event.params["command"]?.stringValue ?? event.params["reason"]?.stringValue ?? "Comando"
            kind = .permission(toolName: "Codex", summary: summary, inputJSON: event.params.compactSerialized())
        case "item/fileChange/requestApproval":
            kind = .permission(
                toolName: "Codex",
                summary: event.params["reason"]?.stringValue ?? "Alteração de arquivos",
                inputJSON: event.params.compactSerialized()
            )
        case "item/tool/requestUserInput":
            let questions = (event.params["questions"]?.arrayValue ?? []).compactMap { raw -> PendingQuestion? in
                guard let id = raw["id"]?.stringValue, let question = raw["question"]?.stringValue else { return nil }
                questionIds.insert(id)
                let options = (raw["options"]?.arrayValue ?? []).compactMap { option -> PendingOption? in
                    guard let label = option["label"]?.stringValue else { return nil }
                    return PendingOption(label: label, description: option["description"]?.stringValue)
                }
                return PendingQuestion(header: raw["header"]?.stringValue ?? "Pergunta", question: question, options: options, multiSelect: false, id: id)
            }
            guard !questions.isEmpty else { return }
            kind = .question(questions: questions)
        default:
            return
        }
        let started = event.params["startedAtMs"]?.doubleValue.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        let request = PendingRequest(id: requestId, agentId: paneId, createdAt: started, kind: kind)
        decisions[requestId] = Decision(
            request: request,
            connectionId: event.connectionId,
            rpcId: rpcId,
            threadId: threadId,
            method: event.method,
            questionIds: questionIds
        )
        publishPending()
        publishPanes()
        continuation.yield(.needsInput(request))
    }

    private func publishPending() {
        continuation.yield(.pending(pendingRequests))
    }
}
