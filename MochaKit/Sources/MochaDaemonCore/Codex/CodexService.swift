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

enum CodexServiceUpdate: Sendable {
    case availability(Bool)
    case thread(String)
    case pending([PendingRequest])
    case usage(UsageSnapshot)
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
        paneThreads.removeAll()
        decisions.removeAll()
        await server.shutdown()
        continuation.finish()
    }

    func verify(_ agent: HerdrAgent) async -> Bool {
        guard agent.kind == "codex", let id = agent.sessionId, UUID(uuidString: id) != nil,
              await server.isConnected else { return false }
        do {
            let result = try await server.request("thread/read", params: .object([
                .init("threadId", .string(id)), .init("includeTurns", .bool(false)),
            ]))
            guard let threadId = result["thread"]?["id"]?.stringValue, threadId == id,
                  let threadCwd = result["thread"]?["cwd"]?.stringValue,
                  let paneCwd = agent.cwd ?? agent.foregroundCwd,
                  URL(fileURLWithPath: threadCwd).standardizedFileURL.resolvingSymlinksInPath().path ==
                    URL(fileURLWithPath: paneCwd).standardizedFileURL.resolvingSymlinksInPath().path
            else { return false }
            guard !paneThreads.contains(where: { $0.key != agent.paneId && $0.value == id }) else { return false }
            if paneThreads[agent.paneId] != id {
                _ = try await server.request("thread/resume", params: .object([
                    .init("threadId", .string(id)), .init("excludeTurns", .bool(true)),
                ]))
                let previous = paneThreads[agent.paneId]
                paneThreads[agent.paneId] = id
                if let previous {
                    decisions = decisions.filter { $0.value.threadId != previous }
                    publishPending()
                }
            }
            return true
        } catch {
            return false
        }
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
        let turns = try await server.request("thread/turns/list", params: .object(members))
        guard let page = CodexProjection.page(thread: metadata["thread"] ?? .null, turns: turns) else {
            throw CodexAppServerError.invalidResponse
        }
        return page
    }

    func prompt(_ agent: HerdrAgent, text: String) async throws {
        guard await verify(agent), let threadId = paneThreads[agent.paneId] else { throw CodexServiceError.unverifiedAgent }
        let input = try Self.promptInput(text, uploadsDirectory: uploadsDirectory)
        let page = try await page(threadId: threadId, before: nil, limit: 1)
        if let activeTurnId = page.activeTurnId {
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
    }

    func interrupt(_ agent: HerdrAgent) async throws {
        guard await verify(agent), let threadId = paneThreads[agent.paneId] else { throw CodexServiceError.unverifiedAgent }
        let page = try await page(threadId: threadId, before: nil, limit: 1)
        guard let turnId = page.activeTurnId else { throw CodexServiceError.noActiveTurn }
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

    private func connectLoop() async {
        while !stopped && !Task.isCancelled {
            if !(await server.isConnected) {
                if (try? await server.connect()) != nil {
                    continuation.yield(.availability(true))
                    await refreshUsage()
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func handle(_ event: CodexServerEvent) {
        if event.method == "mocha/disconnected" {
            paneThreads.removeAll()
            decisions.removeAll()
            publishPending()
            continuation.yield(.availability(false))
            return
        }
        if event.method == "serverRequest/resolved" {
            let resolved = event.params["requestId"]
            decisions = decisions.filter { $0.value.connectionId != event.connectionId || $0.value.rpcId != resolved }
            publishPending()
            return
        }
        if let requestId = event.requestId {
            addDecision(event, rpcId: requestId)
            return
        }
        if let threadId = event.params["threadId"]?.stringValue, paneThreads.values.contains(threadId) {
            continuation.yield(.thread(threadId))
        }
        if event.method == "account/rateLimits/updated", let snapshot = CodexProjection.usage(event.params) {
            continuation.yield(.usage(snapshot))
        }
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
    }

    private func publishPending() {
        continuation.yield(.pending(pendingRequests))
    }
}
