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
    var summary = CodexThreadSummary()
    var settings = CodexThreadSettings()

    var title: String? { summary.title }
}

enum CodexServiceUpdate: Sendable {
    case availability(Bool)
    case panes([AgentID: CodexPaneState])
    case pending([PendingRequest])
    case decisions([AgentID: PendingDecision])
    case usage(UsageSnapshot)
    case alert(CodexAlert)
}

actor CodexService: CodexServing {
    static let requestPrefix = "codex:"
    static let waitingFlags: Set<String> = ["waitingOnApproval", "waitingOnUserInput"]
    static let pageLimits = 1...200
    static let turnPageSize = 100
    static let turnPagesLimit = 20
    static let hydrationItems = 20
    static let pageNeighborsLimit = 64

    nonisolated let updates: AsyncStream<CodexServiceUpdate>
    nonisolated let socketPath: String

    private struct Decision {
        var request: PendingRequest
        var connectionId: UUID
        var rpcId: OrderedJSON
        let threadId: String
    }

    private struct Unanswerable {
        let threadId: String
        var connectionId: UUID
        var rpcId: OrderedJSON
    }

    private struct ThreadInfo {
        let cwd: String
        let isOwnable: Bool
    }

    private let continuation: AsyncStream<CodexServiceUpdate>.Continuation
    private let server: CodexAppServer
    private let uploadsDirectory: URL
    private let bindingStore: CodexPaneBindingStore
    private let retryInterval: Duration
    private var paneThreads: [AgentID: String] = [:]
    private var staleThreads: [AgentID: String] = [:]
    private var paneCwds: [AgentID: String] = [:]
    private var savedBindings: [AgentID: CodexPaneBinding] = [:]
    private var threadInfos: [String: ThreadInfo] = [:]
    private var subscribed: Set<String> = []
    private var threadStatuses: [String: AgentStatus] = [:]
    private var waitingThreads: Set<String> = []
    private var threads: [String: CodexThreadState] = [:]
    private var pageNeighbors: [String: String] = [:]
    private var account: CodexAccount?
    private var rateLimits: OrderedJSON?
    private let threadEventHub = CodexThreadEventHub()
    private var fileChanges: [String: [String]] = [:]
    private var matcher = CodexPaneMatcher()
    private var publishedPanes: [AgentID: CodexPaneState] = [:]
    private var decisions: [RequestID: Decision] = [:]
    private var unanswerable: [String: Unanswerable] = [:]
    private var suspended: Set<String> = []
    private var outcomes: [AgentID: PendingDecision] = [:]
    private var publishedOutcomes: [AgentID: PendingDecision] = [:]
    private var startedAt = Date()
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var stopped = false

    init(socketPath: String, uploadsDirectory: URL, bindingsFile: URL? = nil, retryInterval: Duration = .seconds(2)) {
        self.socketPath = socketPath
        self.uploadsDirectory = uploadsDirectory
        self.retryInterval = retryInterval
        bindingStore = bindingsFile.map(CodexPaneBindingStore.init(url:)) ?? CodexPaneBindingStore(socketPath: socketPath)
        server = CodexAppServer(socketPath: socketPath)
        (updates, continuation) = AsyncStream.makeStream(of: CodexServiceUpdate.self)
    }

    var isConnected: Bool { get async { await server.isConnected } }
    var pendingRequests: [PendingRequest] { decisions.values.map(\.request).sorted { $0.createdAt < $1.createdAt } }

    func start() {
        guard eventTask == nil else { return }
        stopped = false
        startedAt = Date()
        loadBindings()
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
        suspendConnection()
        await server.shutdown()
        continuation.finish()
        threadEventHub.finish()
    }

    nonisolated func threadEvents() -> AsyncStream<CodexThreadEvent> {
        threadEventHub.events()
    }

    func threadSettings(for threadId: String) -> CodexThreadSettings? {
        threads[threadId]?.settings
    }

    func threadSummary(for threadId: String) -> CodexThreadSummary? {
        threads[threadId]?.summary
    }

    func activeTurnId(for threadId: String) async -> String? {
        await activeTurn(threadId)
    }

    func expectPane(_ paneId: AgentID, cwd: String, since: Date) {
        paneCwds[paneId] = CodexPaneMatcher.normalized(cwd)
        guard let threadId = matcher.expect(paneId, cwd: cwd, since: since, now: Date()) else { return }
        associate(paneId, threadId: threadId)
    }

    func retainPanes(_ paneIds: Set<AgentID>) {
        let gone = Set(paneThreads.keys).union(staleThreads.keys).union(paneCwds.keys).subtracting(paneIds)
        guard !gone.isEmpty else { return }
        for paneId in gone {
            staleThreads[paneId] = nil
            paneCwds[paneId] = nil
            outcomes[paneId] = nil
            matcher.forget(paneId)
            if let threadId = paneThreads.removeValue(forKey: paneId) {
                release(threadId)
            }
        }
        saveBindings()
        publishPending()
        publishDecisions()
        publishPanes()
    }

    func movePane(from oldId: AgentID, to newId: AgentID) {
        guard oldId != newId else { return }
        if let threadId = paneThreads.removeValue(forKey: oldId) { paneThreads[newId] = threadId }
        if let threadId = staleThreads.removeValue(forKey: oldId) { staleThreads[newId] = threadId }
        if let cwd = paneCwds.removeValue(forKey: oldId) { paneCwds[newId] = cwd }
        if let outcome = outcomes.removeValue(forKey: oldId) { outcomes[newId] = outcome }
        matcher.move(from: oldId, to: newId)
        for (requestId, decision) in decisions where decision.request.agentId == oldId {
            decisions[requestId]?.request.agentId = newId
        }
        saveBindings()
        publishPending()
        publishDecisions()
        publishPanes()
    }

    func threadId(for paneId: AgentID) -> String? { paneThreads[paneId] }

    func page(threadId: String, before: String?, limit: Int) async throws -> CodexThreadPage {
        guard await server.isConnected else { throw CodexServiceError.unavailable }
        let thread: OrderedJSON
        do {
            thread = try await server.request("thread/read", params: .object([
                .init("threadId", .string(threadId)), .init("includeTurns", .bool(false)),
            ]))["thread"] ?? .null
        } catch CodexAppServerError.rejected where before == nil {
            guard let cwd = threads[threadId]?.cwd else { throw CodexServiceError.unavailable }
            thread = .object([.init("id", .string(threadId)), .init("cwd", .string(cwd))])
        }
        var members: [OrderedJSON.Member] = [
            .init("threadId", .string(threadId)),
            .init("limit", .number(String(min(max(limit, Self.pageLimits.lowerBound), Self.pageLimits.upperBound)))),
            .init("sortDirection", .string("desc")),
        ]
        if let before { members.append(.init("cursor", .string(before))) }
        let listed: OrderedJSON
        do {
            listed = try await server.request("thread/items/list", params: .object(members))
        } catch CodexAppServerError.rejected where before == nil {
            listed = .object([])
        }
        let entries = CodexProjection.entries(listed)
        let turns = await turns(Set(entries.compactMap(\.turnId)), of: threadId)
        let state = threads[threadId]
        guard let page = CodexProjection.page(
            thread: thread,
            listed: listed,
            turns: turns,
            newerTurnId: before.flatMap { pageNeighbors[$0] },
            cards: state?.cards ?? [:],
            outcomes: state?.outcomes ?? [:]
        ) else {
            throw CodexAppServerError.invalidResponse
        }
        if let next = page.before, let oldest = entries.last?.turnId {
            if pageNeighbors.count >= Self.pageNeighborsLimit { pageNeighbors.removeAll() }
            pageNeighbors[next] = oldest
        }
        if var state {
            state.absorb(thread: thread)
            state.absorb(page: page)
            threads[threadId] = state
            publishPanes()
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
        guard let decision = decisions[requestId] else { throw CodexServiceError.requestNotFound }
        let result: OrderedJSON
        switch (decision.request.kind, response) {
        case (.permission, .allow):
            result = .object([.init("decision", .string("accept"))])
        case (.permission, .deny):
            result = .object([.init("decision", .string("decline"))])
        case (.question(let questions), .answers(let answers)):
            guard let translated = Self.answersById(answers, questions: questions) else { throw CodexServiceError.invalidResponse }
            let entries = translated.sorted { $0.key < $1.key }.map { key, value in
                OrderedJSON.Member(key, .object([.init("answers", .array(value.map(OrderedJSON.string)))]))
            }
            result = .object([.init("answers", .object(entries))])
        default:
            throw CodexServiceError.invalidResponse
        }
        decisions[requestId] = nil
        publishPending()
        publishPanes()
        do {
            try await server.respond(to: decision.rpcId, on: decision.connectionId, result: result)
        } catch {
            codexLogger.error("codex request \(requestId, privacy: .public) is gone: \(String(describing: error), privacy: .public)")
            throw CodexServiceError.requestNotFound
        }
        outcomes[decision.request.agentId] = PendingDecision(requestId: requestId, outcome: PendingOutcome(response))
        publishDecisions()
    }

    func refreshUsage() async {
        if let result = try? await server.request("account/read", params: .object([])) {
            account = CodexProjection.account(result)
        }
        guard let result = try? await server.request("account/rateLimits/read", params: .object([])) else { return }
        rateLimits = result
        publishUsage()
    }

    private func refreshAccount() async {
        guard let result = try? await server.request("account/read", params: .object([])) else { return }
        let refreshed = CodexProjection.account(result)
        guard refreshed != account else { return }
        account = refreshed
        publishUsage()
    }

    private func publishUsage() {
        guard let rateLimits, let snapshot = CodexProjection.usage(rateLimits, account: account) else { return }
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

    static func answersById(_ answers: [String: [String]], questions: [PendingQuestion]) -> [String: [String]]? {
        var translated: [String: [String]] = [:]
        for (key, value) in answers {
            let id: String
            if let match = questions.first(where: { $0.id == key })?.id {
                id = match
            } else {
                let matches = questions.filter { $0.question == key }
                guard matches.count == 1, let match = matches[0].id else { return nil }
                id = match
            }
            guard translated[id] == nil else { return nil }
            translated[id] = value
        }
        guard Set(translated.keys) == Set(questions.compactMap(\.id)) else { return nil }
        return translated
    }

    static func pendingKind(_ method: String, params: OrderedJSON, changedPaths: [String]?, cwd: String?) -> PendingKind? {
        switch method {
        case "item/commandExecution/requestApproval":
            let actions = (params["commandActions"]?.arrayValue ?? []).compactMap { $0["command"]?.stringValue }.filter { !$0.isEmpty }
            let command = actions.isEmpty ? params["command"]?.stringValue : actions.joined(separator: "\n")
            let reason = params["reason"]?.stringValue
            var input: [OrderedJSON.Member] = []
            if let command { input.append(.init("command", .string(command))) }
            if let reason { input.append(.init("reason", .string(reason))) }
            if let cwd = params["cwd"]?.stringValue { input.append(.init("cwd", .string(cwd))) }
            return .permission(toolName: "Bash", summary: command ?? reason ?? "Comando", inputJSON: OrderedJSON.object(input).compactSerialized())
        case "item/fileChange/requestApproval":
            let paths = changedPaths ?? []
            let reason = params["reason"]?.stringValue
            var input: [OrderedJSON.Member] = []
            if let first = paths.first { input.append(.init("file_path", .string(first))) }
            if paths.count > 1 { input.append(.init("paths", .array(paths.map(OrderedJSON.string)))) }
            if let reason { input.append(.init("reason", .string(reason))) }
            let summary = paths.isEmpty ? reason ?? "Alteração de arquivos" : paths.map { relative($0, to: cwd) }.joined(separator: ", ")
            return .permission(toolName: "Edit", summary: summary, inputJSON: OrderedJSON.object(input).compactSerialized())
        case "item/tool/requestUserInput":
            let questions = (params["questions"]?.arrayValue ?? []).compactMap { raw -> PendingQuestion? in
                guard let id = raw["id"]?.stringValue, let question = raw["question"]?.stringValue else { return nil }
                let options = (raw["options"]?.arrayValue ?? []).compactMap { option -> PendingOption? in
                    guard let label = option["label"]?.stringValue else { return nil }
                    return PendingOption(label: label, description: option["description"]?.stringValue)
                }
                return PendingQuestion(header: raw["header"]?.stringValue ?? "Pergunta", question: question, options: options, multiSelect: false, id: id)
            }
            return questions.isEmpty ? nil : .question(questions: questions)
        default:
            return nil
        }
    }

    static func unanswerableBody(_ method: String, params: OrderedJSON) -> String? {
        switch method {
        case "item/permissions/requestApproval":
            return nonEmpty(params["reason"]) ?? "O Codex pede uma permissão no terminal."
        case "mcpServer/elicitation/request":
            let server = nonEmpty(params["serverName"]) ?? "MCP"
            guard let message = nonEmpty(params["message"]) ?? nonEmpty(params["title"]) ?? nonEmpty(params["description"]) else {
                return "\(server) pede uma resposta no terminal."
            }
            return "\(server): \(message)"
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: OrderedJSON?) -> String? {
        guard let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func relative(_ path: String, to cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return path }
        let prefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return path }
        return String(path.dropFirst(prefix.count))
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
            paneCwds[agent.paneId] = CodexPaneMatcher.normalized(paneCwd)
            associate(agent.paneId, threadId: id)
            return id
        } catch {
            return nil
        }
    }

    private func activeTurn(_ threadId: String) async -> String? {
        if let turnId = threads[threadId]?.activeTurnId { return turnId }
        guard subscribed.contains(threadId),
              let result = try? await server.request("thread/turns/list", params: Self.turnsParams(threadId, limit: 1, cursor: nil)),
              let turn = result["data"]?.arrayValue?.first.flatMap(CodexTurn.init),
              turn.status == .inProgress else { return nil }
        return turn.id
    }

    private func turns(_ ids: Set<String>, of threadId: String) async -> [String: CodexTurn] {
        let cached = threads[threadId]?.closedTurns ?? [:]
        var found = cached.filter { ids.contains($0.key) }
        if let active = threads[threadId]?.activeTurnId, ids.contains(active) {
            found[active] = CodexTurn(id: active, status: .inProgress)
        }
        var missing = ids.subtracting(found.keys)
        var cursor: String?
        var requests = 0
        while !missing.isEmpty, requests < Self.turnPagesLimit {
            requests += 1
            guard let result = try? await server.request("thread/turns/list", params: Self.turnsParams(threadId, limit: Self.turnPageSize, cursor: cursor)) else { break }
            for turn in (result["data"]?.arrayValue ?? []).compactMap(CodexTurn.init) where missing.contains(turn.id) {
                found[turn.id] = turn
                missing.remove(turn.id)
            }
            cursor = result["nextCursor"]?.stringValue
            if cursor == nil { break }
        }
        return found
    }

    private static func turnsParams(_ threadId: String, limit: Int, cursor: String?) -> OrderedJSON {
        var members: [OrderedJSON.Member] = [
            .init("threadId", .string(threadId)),
            .init("itemsView", .string("notLoaded")),
            .init("sortDirection", .string("desc")),
            .init("limit", .number(String(limit))),
        ]
        if let cursor { members.append(.init("cursor", .string(cursor))) }
        return .object(members)
    }

    private func hydrate(_ threadId: String) async {
        let turns = try? await server.request("thread/turns/list", params: Self.turnsParams(threadId, limit: 2, cursor: nil))
        let items = try? await server.request("thread/items/list", params: .object([
            .init("threadId", .string(threadId)),
            .init("limit", .number(String(Self.hydrationItems))),
            .init("sortDirection", .string("desc")),
        ]))
        guard subscribed.contains(threadId), var state = threads[threadId] else { return }
        state.hydrate(
            turns: (turns?["data"]?.arrayValue ?? []).compactMap(CodexTurn.init),
            entries: items.map(CodexProjection.entries) ?? []
        )
        threads[threadId] = state
        publishPanes()
    }

    private func pane(of threadId: String) -> AgentID? {
        paneThreads.first { $0.value == threadId }?.key
    }

    private func associate(_ paneId: AgentID, threadId: String) {
        staleThreads[paneId] = nil
        let previous = paneThreads[paneId]
        guard previous != threadId else {
            saveBindings()
            return
        }
        paneThreads[paneId] = threadId
        if paneCwds[paneId] == nil, let cwd = threadInfos[threadId]?.cwd {
            paneCwds[paneId] = cwd
        }
        if let previous {
            release(previous)
            publishPending()
        }
        saveBindings()
        publishPanes()
        Task { await self.subscribe(threadId) }
    }

    private func release(_ threadId: String) {
        guard !paneThreads.values.contains(threadId) else { return }
        decisions = decisions.filter { $0.value.threadId != threadId }
        unanswerable = unanswerable.filter { $0.value.threadId != threadId }
        suspended = suspended.filter { !$0.hasPrefix(Self.requestPrefix + threadId + ":") && !$0.hasPrefix(threadId + ":") }
        waitingThreads.remove(threadId)
        if let state = threads.removeValue(forKey: threadId) {
            for child in state.cards.keys where !paneThreads.values.contains(child) {
                threads[child] = nil
            }
        }
        guard subscribed.remove(threadId) != nil else { return }
        let server = server
        Task {
            _ = try? await server.request("thread/unsubscribe", params: .object([.init("threadId", .string(threadId))]))
        }
    }

    private func subscribe(_ threadId: String) async {
        guard !subscribed.contains(threadId), paneThreads.values.contains(threadId) else { return }
        subscribed.insert(threadId)
        do {
            let result = try await server.request("thread/resume", params: .object([
                .init("threadId", .string(threadId)), .init("excludeTurns", .bool(true)),
            ]))
            guard subscribed.contains(threadId) else { return }
            threads[threadId, default: CodexThreadState(threadId: threadId)].absorb(resume: result)
            publishPanes()
            await hydrate(threadId)
            threadEventHub.publish(.resubscribed(threadId: threadId))
        } catch {
            subscribed.remove(threadId)
        }
    }

    private func connectLoop() async {
        while !stopped && !Task.isCancelled {
            if await server.isConnected {
                if !staleThreads.isEmpty {
                    await reconcile(afterConnect: false)
                }
                await subscribeAll()
            } else if (try? await server.connect()) != nil {
                continuation.yield(.availability(true))
                await reconcile(afterConnect: true)
                await subscribeAll()
                await refreshUsage()
            }
            try? await Task.sleep(for: retryInterval)
        }
    }

    private func subscribeAll() async {
        for threadId in Set(paneThreads.values).subtracting(subscribed).sorted() {
            await subscribe(threadId)
        }
    }

    private func reconcile(afterConnect: Bool) async {
        guard let loaded = await loadedThreads() else { return }
        for (paneId, threadId) in staleThreads.sorted(by: { $0.key < $1.key }) where loaded.contains(threadId) && pane(of: threadId) == nil {
            associate(paneId, threadId: threadId)
        }
        guard afterConnect, !staleThreads.isEmpty else { return }
        let owned = Set(paneThreads.values).union(staleThreads.values)
        var candidates: [String: [String]] = [:]
        for threadId in loaded.subtracting(owned).sorted() {
            guard let info = await threadInfo(threadId), info.isOwnable else { continue }
            candidates[info.cwd, default: []].append(threadId)
        }
        for paneId in staleThreads.keys.sorted() {
            guard let cwd = paneCwds[paneId], staleThreads.keys.filter({ paneCwds[$0] == cwd }).count == 1,
                  let found = candidates[cwd], found.count == 1, let threadId = found.first, pane(of: threadId) == nil
            else { continue }
            codexLogger.info("pane \(paneId, privacy: .public) adopted thread \(threadId, privacy: .public)")
            associate(paneId, threadId: threadId)
        }
    }

    private func loadedThreads() async -> Set<String>? {
        var loaded: Set<String> = []
        var cursor: String?
        repeat {
            var params: [OrderedJSON.Member] = []
            if let cursor { params.append(.init("cursor", .string(cursor))) }
            guard let result = try? await server.request("thread/loaded/list", params: .object(params)) else { return nil }
            loaded.formUnion((result["data"]?.arrayValue ?? []).compactMap(\.stringValue))
            cursor = result["nextCursor"]?.stringValue
        } while cursor != nil
        return loaded
    }

    private func threadInfo(_ threadId: String) async -> ThreadInfo? {
        if let info = threadInfos[threadId] { return info }
        guard let result = try? await server.request("thread/read", params: .object([
            .init("threadId", .string(threadId)), .init("includeTurns", .bool(false)),
        ])) else { return nil }
        return remember(result["thread"] ?? .null)
    }

    @discardableResult
    private func remember(_ thread: OrderedJSON) -> ThreadInfo? {
        guard let threadId = thread["id"]?.stringValue, let cwd = thread["cwd"]?.stringValue else { return nil }
        let info = ThreadInfo(
            cwd: CodexPaneMatcher.normalized(cwd),
            isOwnable: thread["ephemeral"]?.boolValue != true && thread["parentThreadId"]?.stringValue == nil
        )
        threadInfos[threadId] = info
        return info
    }

    private func loadBindings() {
        savedBindings = bindingStore.load()
        for (paneId, binding) in savedBindings where paneThreads[paneId] == nil {
            staleThreads[paneId] = binding.threadId
            if !binding.cwd.isEmpty {
                paneCwds[paneId] = CodexPaneMatcher.normalized(binding.cwd)
            }
        }
    }

    private func saveBindings() {
        var bindings: [AgentID: CodexPaneBinding] = [:]
        for (paneId, threadId) in staleThreads.merging(paneThreads, uniquingKeysWith: { _, bound in bound }) {
            bindings[paneId] = CodexPaneBinding(threadId: threadId, cwd: paneCwds[paneId] ?? threadInfos[threadId]?.cwd ?? "")
        }
        guard bindings != savedBindings else { return }
        savedBindings = bindings
        bindingStore.save(bindings)
    }

    private func suspendConnection() {
        for (paneId, threadId) in paneThreads {
            staleThreads[paneId] = threadId
        }
        paneThreads.removeAll()
        suspended.formUnion(decisions.keys)
        suspended.formUnion(unanswerable.keys)
        decisions.removeAll()
        unanswerable.removeAll()
        subscribed.removeAll()
        threadStatuses.removeAll()
        waitingThreads.removeAll()
        for threadId in threads.keys {
            threads[threadId]?.suspend()
        }
        pageNeighbors.removeAll()
        fileChanges.removeAll()
    }

    private func handle(_ event: CodexServerEvent) {
        switch event.method {
        case "mocha/disconnected":
            suspendConnection()
            publishPending()
            publishPanes()
            continuation.yield(.availability(false))
            return
        case "serverRequest/resolved":
            let resolved = event.params["requestId"]
            decisions = decisions.filter { $0.value.connectionId != event.connectionId || $0.value.rpcId != resolved }
            unanswerable = unanswerable.filter { $0.value.connectionId != event.connectionId || $0.value.rpcId != resolved }
            publishPending()
            publishPanes()
            return
        default:
            break
        }
        if let requestId = event.requestId {
            serverRequest(event, rpcId: requestId)
            return
        }
        let threadId = event.params["threadId"]?.stringValue
        switch event.method {
        case "thread/started":
            threadStarted(event.params["thread"] ?? .null)
        case "thread/status/changed":
            if let threadId { statusChanged(threadId, status: event.params["status"]) }
        case "turn/started":
            if let threadId { threadStatuses[threadId] = .working }
        case "turn/completed":
            if let threadId { threadStatuses[threadId] = .idle }
        case "item/started":
            if let item = event.params["item"], item["type"]?.stringValue == "fileChange", let itemId = item["id"]?.stringValue {
                fileChanges[itemId] = (item["changes"]?.arrayValue ?? []).compactMap { $0["path"]?.stringValue }
            }
        case "item/completed":
            if let item = event.params["item"], let itemId = item["id"]?.stringValue {
                fileChanges[itemId] = nil
            }
        case "account/rateLimits/updated":
            rateLimits = event.params
            publishUsage()
        case "account/updated":
            Task { await self.refreshAccount() }
        default:
            break
        }
        if let threadId, CodexThreadState.liveMethods.contains(event.method) {
            apply(event.method, params: event.params, to: threadId)
        }
        publishPanes()
    }

    private func apply(_ method: String, params: OrderedJSON, to threadId: String) {
        var state = threads[threadId] ?? CodexThreadState(threadId: threadId)
        let events = state.apply(method, params, now: Date())
        threads[threadId] = state
        for event in events {
            threadEventHub.publish(event)
        }
        guard method == "turn/completed", let paneId = pane(of: threadId),
              let turn = params["turn"].flatMap(CodexTurn.init), turn.status == .completed else { return }
        continuation.yield(.alert(.turnDone(paneId, lastMessage: state.lastAgentMessage)))
    }

    private func statusChanged(_ threadId: String, status: OrderedJSON?) {
        threadStatuses[threadId] = CodexProjection.status(status)
        let flags = Set((status?["activeFlags"]?.arrayValue ?? []).compactMap(\.stringValue))
        guard !flags.isDisjoint(with: Self.waitingFlags) else {
            waitingThreads.remove(threadId)
            return
        }
        guard waitingThreads.insert(threadId).inserted, let paneId = pane(of: threadId) else { return }
        continuation.yield(.alert(.blocked(paneId)))
    }

    private func threadStarted(_ thread: OrderedJSON) {
        guard let threadId = thread["id"]?.stringValue, let info = remember(thread), info.isOwnable else { return }
        threadStatuses[threadId] = CodexProjection.status(thread["status"])
        let at = thread["createdAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date()
        if let paneId = matcher.threadStarted(threadId, cwd: info.cwd, at: at) {
            associate(paneId, threadId: threadId)
        } else {
            let sameCwd = Set(paneThreads.keys).union(staleThreads.keys).filter { paneCwds[$0] == info.cwd }
            if sameCwd.count == 1, let paneId = sameCwd.first {
                associate(paneId, threadId: threadId)
            }
        }
        guard pane(of: threadId) != nil else { return }
        threads[threadId, default: CodexThreadState(threadId: threadId)].absorb(thread: thread)
    }

    private func serverRequest(_ event: CodexServerEvent, rpcId: OrderedJSON) {
        guard let threadId = event.params["threadId"]?.stringValue, let paneId = pane(of: threadId) else { return }
        let itemId = event.params["itemId"]?.stringValue
        let startedAtMs = event.params["startedAtMs"]?.doubleValue
        let isOld = startedAtMs.map { Date(timeIntervalSince1970: $0 / 1000) < startedAt } ?? false
        if let body = Self.unanswerableBody(event.method, params: event.params) {
            let key = "\(threadId):\(itemId ?? body)"
            if unanswerable[key] != nil {
                unanswerable[key]?.connectionId = event.connectionId
                unanswerable[key]?.rpcId = rpcId
                return
            }
            unanswerable[key] = Unanswerable(threadId: threadId, connectionId: event.connectionId, rpcId: rpcId)
            let redelivered = suspended.remove(key) != nil || isOld
            publishPanes()
            if !redelivered {
                continuation.yield(.alert(.needsInputWithoutActions(paneId, body: body)))
            }
            return
        }
        guard let itemId else { return }
        let requestId = "\(Self.requestPrefix)\(threadId):\(itemId)"
        if decisions[requestId] != nil {
            decisions[requestId]?.connectionId = event.connectionId
            decisions[requestId]?.rpcId = rpcId
            return
        }
        guard let kind = Self.pendingKind(event.method, params: event.params, changedPaths: fileChanges[itemId], cwd: paneCwds[paneId]) else {
            codexLogger.debug("ignoring codex request \(event.method, privacy: .public)")
            return
        }
        let createdAt = startedAtMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        let request = PendingRequest(id: requestId, agentId: paneId, createdAt: createdAt, kind: kind)
        decisions[requestId] = Decision(request: request, connectionId: event.connectionId, rpcId: rpcId, threadId: threadId)
        let redelivered = suspended.remove(requestId) != nil || isOld
        publishPending()
        publishPanes()
        if !redelivered {
            continuation.yield(.alert(.needsInput(request)))
        }
    }

    private func publishPanes() {
        var panes: [AgentID: CodexPaneState] = [:]
        let blocked = waitingThreads.union(decisions.values.map(\.threadId)).union(unanswerable.values.map(\.threadId))
        for (paneId, threadId) in paneThreads {
            let status = blocked.contains(threadId) ? .blocked : threadStatuses[threadId] ?? .idle
            let state = threads[threadId]
            panes[paneId] = CodexPaneState(
                threadId: threadId,
                status: status,
                summary: state?.summary ?? CodexThreadSummary(),
                settings: state?.settings ?? CodexThreadSettings()
            )
        }
        guard panes != publishedPanes else { return }
        publishedPanes = panes
        continuation.yield(.panes(panes))
    }

    private func publishPending() {
        continuation.yield(.pending(pendingRequests))
    }

    private func publishDecisions() {
        guard outcomes != publishedOutcomes else { return }
        publishedOutcomes = outcomes
        continuation.yield(.decisions(outcomes))
    }
}
