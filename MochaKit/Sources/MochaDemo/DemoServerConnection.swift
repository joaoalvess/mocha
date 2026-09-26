import Foundation
import MochaProtocol

public actor DemoServerConnection: ServerConnection {
    public nonisolated let messages: AsyncStream<ServerEnvelope>
    public nonisolated let states: AsyncStream<ConnectionState>

    static let defaultPageSize = 60
    static let maximumPageSize = 200
    static let cursorPrefix = "demo:"
    static let host = HostInfo(hostName: "Mac de demonstração", daemonVersion: "0.1.0-demo", herdrConnected: true)
    static let deviceId: DeviceID = "D3E0D3E0-0000-4000-8000-000000000001"
    static let deviceToken = "demo-device-token"
    static let claudeOnlyMessage = "Chat disponível só para Claude Code."
    static let agentNotFoundMessage = "Agente não encontrado."
    static let repeatedHelloMessage = "O hello já foi feito nesta conexão."
    static let replyMarkdown = """
    Isto é o **modo demo** do Mocha: nenhuma mensagem saiu do iPhone.

    No uso real, o prompt vai para o Claude Code no Mac pelo `mochad`, e a resposta aparece aqui assim que o Claude a grava no transcript.
    """

    private let messageContinuation: AsyncStream<ServerEnvelope>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    private let options: DemoOptions
    private var state: ConnectionState = .idle
    private var isPaired: Bool
    private var workspaces: [WorkspaceNode]
    private var chats: [AgentID: DemoChat]
    private var movedAgents: [AgentID: AgentID] = [:]
    private var openChats: Set<AgentID> = []
    private var preferences = DevicePreferences()
    private var handshakeCount = 0
    private var connectionTask: Task<Void, Never>?
    private var turns: [AgentID: Task<Void, Never>] = [:]
    private var scriptTask: Task<Void, Never>?
    private var nextScriptStep = 0
    private var scriptTurnStartedAt: Date?

    public init(options: DemoOptions = DemoOptions()) throws {
        self.init(dataset: try DemoDataset.bundled(), options: options)
    }

    init(dataset: DemoDataset, options: DemoOptions) {
        let (messages, messageContinuation) = AsyncStream.makeStream(of: ServerEnvelope.self)
        let (states, stateContinuation) = AsyncStream.makeStream(of: ConnectionState.self)
        stateContinuation.yield(.idle)
        self.messages = messages
        self.messageContinuation = messageContinuation
        self.states = states
        self.stateContinuation = stateContinuation
        self.options = options
        self.isPaired = options.startsPaired
        self.workspaces = dataset.workspaces
        self.chats = Dictionary(dataset.chats.map { ($0.agentId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    deinit {
        messageContinuation.finish()
        stateContinuation.finish()
        connectionTask?.cancel()
        scriptTask?.cancel()
        for turn in turns.values {
            turn.cancel()
        }
    }

    public func start() {
        switch state {
        case .idle, .failed:
            if isPaired {
                openConnection(pairing: false)
            } else {
                setState(.pairingRequired(nil))
            }
        case .connecting, .connected, .waitingToRetry, .pairingRequired:
            break
        }
    }

    public func stop() {
        cancelConnectionWork()
        setState(.idle)
    }

    public func pair(_ link: PairingLink) {
        openConnection(pairing: true)
    }

    public func send(_ message: ClientMessage, id: String) throws {
        guard state == .connected else { throw ServerConnectionError.notConnected }
        handle(message, id: id)
    }

    private func openConnection(pairing: Bool) {
        cancelConnectionWork()
        setState(.connecting)
        connectionTask = Task { [weak self, connectDelay = options.connectDelay] in
            do {
                try await Task.sleep(for: connectDelay)
            } catch {
                return
            }
            await self?.completeConnection(pairing: pairing)
        }
    }

    private func completeConnection(pairing: Bool) {
        guard !Task.isCancelled, state == .connecting else { return }
        connectionTask = nil
        handshake(pairing: pairing)
    }

    private func handshake(pairing: Bool) {
        handshakeCount += 1
        let id = "hello-\(handshakeCount)"
        if pairing {
            isPaired = true
        }
        openChats = []
        let helloOk = HelloOkPayload(
            host: Self.host,
            deviceId: Self.deviceId,
            deviceToken: pairing ? Self.deviceToken : nil,
            preferences: preferences
        )
        messageContinuation.yield(ServerEnvelope(id: id, message: .helloOk(helloOk)))
        setState(.connected)
        messageContinuation.yield(ServerEnvelope(id: id, message: .tree(workspaces: workspaces)))
        resumeScript()
    }

    private func cancelConnectionWork() {
        connectionTask?.cancel()
        connectionTask = nil
        scriptTask?.cancel()
        scriptTask = nil
        openChats = []
    }

    private func setState(_ newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        stateContinuation.yield(newState)
    }

    private func handle(_ message: ClientMessage, id: String) {
        switch message {
        case .hello:
            fail(id, .invalidPayload, Self.repeatedHelloMessage)
        case .openChat(let agentId, let before, let limit):
            openChat(agentId: agentId, before: before, limit: limit, id: id)
        case .closeChat(let agentId):
            openChats.remove(currentId(for: agentId))
            reply(id, .ack())
        case .sendPrompt(let agentId, let text):
            sendPrompt(agentId: agentId, text: text, id: id)
        case .interrupt(let agentId):
            interrupt(agentId: agentId, id: id)
        case .setForeground, .registerLiveActivity:
            reply(id, .ack())
        case .unpair:
            reply(id, .ack())
            isPaired = false
            cancelConnectionWork()
            setState(.pairingRequired(nil))
        case .ping:
            reply(id, .pong)
        case .slash(let agentId, _):
            guard claudeChat(agentId, replyingTo: id) != nil else { return }
            reply(id, .ack())
        case .setPreferences(let newPreferences):
            preferences = newPreferences
            reply(id, .ack())
        case .respond:
            fail(id, .requestNotFound, "Pedido não encontrado.")
        case .newAgentTab:
            fail(id, .internal, "Nova tab não está disponível no modo demo.")
        case .unknown(let type):
            fail(id, .unknownType, "Tipo de mensagem desconhecido: \(type).")
        }
    }

    private func claudeChat(_ agentId: AgentID, replyingTo id: String) -> DemoChat? {
        let current = currentId(for: agentId)
        guard let agent = workspaces.agent(withId: current) else {
            fail(id, .agentNotFound, Self.agentNotFoundMessage)
            return nil
        }
        guard agent.kind == "claude" else {
            fail(id, .invalidPayload, Self.claudeOnlyMessage)
            return nil
        }
        guard let chat = chats[current] else {
            fail(id, .agentNotFound, Self.agentNotFoundMessage)
            return nil
        }
        return chat
    }

    private func currentId(for agentId: AgentID) -> AgentID {
        var current = agentId
        for _ in 0...movedAgents.count {
            guard let next = movedAgents[current] else { break }
            current = next
        }
        return current
    }

    private func openChat(agentId: AgentID, before: String?, limit: Int?, id: String) {
        guard let chat = claudeChat(agentId, replyingTo: id) else { return }
        var end = chat.items.count
        if let before {
            guard let index = Self.index(fromCursor: before), (0...chat.items.count).contains(index) else {
                return fail(id, .invalidPayload, "Cursor de paginação inválido.")
            }
            end = index
        }
        let pageSize = min(max(limit ?? Self.defaultPageSize, 1), Self.maximumPageSize)
        let start = max(0, end - pageSize)
        let hasMore = start > 0
        openChats.insert(chat.agentId)
        let page = ChatPage(
            agentId: chat.agentId,
            meta: chat.meta,
            items: Array(chat.items[start..<end]),
            before: hasMore ? Self.cursor(forIndex: start) : nil,
            hasMore: hasMore
        )
        reply(id, .chatPage(page))
    }

    private func sendPrompt(agentId: AgentID, text: String, id: String) {
        guard let chat = claudeChat(agentId, replyingTo: id) else { return }
        guard chat.meta.status != .blocked else {
            return fail(id, .agentBlocked, "O agente está esperando uma resposta no terminal.")
        }
        reply(id, .ack())
        let target = chat.agentId
        turns[target]?.cancel()
        turns[target] = Task { [weak self, echoDelay = options.echoDelay, replyDelay = options.replyDelay] in
            do {
                try await Task.sleep(for: echoDelay)
            } catch {
                return
            }
            guard let startedAt = await self?.echoPrompt(text, for: target) else { return }
            do {
                try await Task.sleep(for: replyDelay)
            } catch {
                return
            }
            await self?.finishTurn(for: target, startedAt: startedAt)
        }
    }

    private func echoPrompt(_ text: String, for agentId: AgentID) -> Date? {
        guard !Task.isCancelled else { return nil }
        let current = currentId(for: agentId)
        let now = Date()
        append([ChatItem(id: Self.newItemId(), at: now, kind: .userPrompt(text: text, imageCount: 0))], to: current)
        setStatus(.working, for: current)
        return now
    }

    private func finishTurn(for agentId: AgentID, startedAt: Date) {
        guard !Task.isCancelled else { return }
        let current = currentId(for: agentId)
        turns[current] = nil
        let now = Date()
        append(
            [
                ChatItem(id: Self.newItemId(), at: now, kind: .assistantText(markdown: Self.replyMarkdown)),
                ChatItem(id: Self.newItemId(), at: now, kind: .turnFooter(durationMs: Self.milliseconds(from: startedAt, to: now))),
            ],
            to: current
        )
        setStatus(.idle, for: current)
    }

    private func interrupt(agentId: AgentID, id: String) {
        guard let chat = claudeChat(agentId, replyingTo: id) else { return }
        reply(id, .ack())
        turns.removeValue(forKey: chat.agentId)?.cancel()
        guard chat.meta.status == .working else { return }
        setStatus(.idle, for: chat.agentId)
    }

    private func append(_ newItems: [ChatItem], to agentId: AgentID) {
        guard chats[agentId] != nil, let lastItem = newItems.last else { return }
        chats[agentId]?.items.append(contentsOf: newItems)
        workspaces.updateAgent(withId: agentId) { $0.lastActivityAt = lastItem.at }
        guard openChats.contains(agentId) else { return }
        emit(.chatAppend(agentId: agentId, items: newItems))
    }

    private func replace(_ item: ChatItem, in agentId: AgentID) {
        guard let index = chats[agentId]?.items.firstIndex(where: { $0.id == item.id }) else { return }
        chats[agentId]?.items[index] = item
        guard openChats.contains(agentId) else { return }
        emit(.chatUpdate(agentId: agentId, items: [item]))
    }

    private func setStatus(_ status: AgentStatus, for agentId: AgentID) {
        chats[agentId]?.meta.status = status
        workspaces.updateAgent(withId: agentId) { $0.status = status }
        emit(.agentStatus(agentId: agentId, status: status))
        emitTree()
    }

    private func emitTree() {
        emit(.treeChanged(workspaces: workspaces))
    }

    private func reply(_ id: String, _ message: ServerMessage) {
        messageContinuation.yield(ServerEnvelope(id: id, message: message))
    }

    private func emit(_ message: ServerMessage) {
        guard state == .connected else { return }
        messageContinuation.yield(ServerEnvelope(message: message))
    }

    private func fail(_ id: String, _ code: ProtocolErrorCode, _ message: String) {
        reply(id, .error(code: code, message: message))
    }

    private func resumeScript() {
        guard options.runsScript, scriptTask == nil, nextScriptStep < DemoScript.steps.count else { return }
        scriptTask = Task { [weak self] in
            while let delay = await self?.pendingScriptDelay() {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                await self?.runPendingScriptStep()
            }
        }
    }

    private func pendingScriptDelay() -> Duration? {
        guard !Task.isCancelled else { return nil }
        guard nextScriptStep < DemoScript.steps.count else {
            scriptTask = nil
            return nil
        }
        return DemoScript.steps[nextScriptStep].delay * options.scriptTimeScale
    }

    private func runPendingScriptStep() {
        guard !Task.isCancelled, nextScriptStep < DemoScript.steps.count else { return }
        let event = DemoScript.steps[nextScriptStep].event
        nextScriptStep += 1
        perform(event)
    }

    private func perform(_ event: DemoScriptEvent) {
        let now = Date()
        let turnAgent = currentId(for: DemoScript.turnAgentId)
        switch event {
        case .addWorktree:
            chats[DemoScript.worktreeAgentId] = DemoScript.worktreeChat(at: now)
            workspaces.updateWorkspace(withId: DemoScript.worktreeParentId) { parent in
                parent.children.append(DemoScript.worktree(at: now))
            }
            emitTree()
        case .startTurn:
            scriptTurnStartedAt = now
            append([DemoScript.prompt(at: now)], to: turnAgent)
            setStatus(.working, for: turnAgent)
        case .appendThinking:
            append([DemoScript.thinking(at: now)], to: turnAgent)
        case .appendPlan:
            append([DemoScript.plan(at: now)], to: turnAgent)
        case .appendRead:
            append([DemoScript.read(at: now)], to: turnAgent)
        case .appendRunningTool:
            append([DemoScript.testRun(at: now, status: .running)], to: turnAgent)
        case .finishRunningTool:
            let startedAt = chats[turnAgent]?.items.first { $0.id == DemoScript.runningToolItemId }?.at ?? now
            replace(DemoScript.testRun(at: startedAt, status: .succeeded), in: turnAgent)
        case .renameChat:
            rename(turnAgent, to: DemoScript.renamedTitle)
        case .finishTurn:
            let durationMs = Self.milliseconds(from: scriptTurnStartedAt ?? now, to: now)
            append(DemoScript.finalAnswer(at: now, durationMs: durationMs), to: turnAgent)
            setStatus(.idle, for: turnAgent)
        case .switchSession:
            switchSession(of: currentId(for: DemoScript.worktreeAgentId), to: DemoScript.clearedSessionId, at: now)
        case .moveAgent:
            moveAgent(from: currentId(for: DemoScript.movedAgentId), to: DemoScript.movedAgentNewId)
        case .dropConnection:
            openChats = []
            setState(.waitingToRetry(.unreachable))
        case .retryConnection:
            guard state == .waitingToRetry(.unreachable) else { return }
            setState(.connecting)
        case .completeReconnection:
            guard state == .connecting, connectionTask == nil else { return }
            handshake(pairing: false)
        }
    }

    private func rename(_ agentId: AgentID, to title: String) {
        guard var meta = chats[agentId]?.meta else { return }
        meta.title = title
        chats[agentId]?.meta = meta
        workspaces.updateAgent(withId: agentId) { $0.title = title }
        if openChats.contains(agentId) {
            emit(.chatMeta(agentId: agentId, meta: meta))
        }
        emitTree()
    }

    private func switchSession(of agentId: AgentID, to sessionId: String, at date: Date) {
        guard chats[agentId] != nil else { return }
        chats[agentId]?.items = [DemoScript.clearCommand(at: date)]
        workspaces.updateAgent(withId: agentId) { agent in
            agent.sessionId = sessionId
            agent.lastActivityAt = date
        }
        emitTree()
    }

    private func moveAgent(from oldId: AgentID, to newId: AgentID) {
        guard oldId != newId, workspaces.updateAgent(withId: oldId, { $0.id = newId }) else { return }
        movedAgents[oldId] = newId
        if var chat = chats.removeValue(forKey: oldId) {
            chat.agentId = newId
            chats[newId] = chat
        }
        if openChats.remove(oldId) != nil {
            openChats.insert(newId)
        }
        if let turn = turns.removeValue(forKey: oldId) {
            turns[newId] = turn
        }
        emitTree()
    }

    static func cursor(forIndex index: Int) -> String {
        cursorPrefix + String(index)
    }

    static func index(fromCursor cursor: String) -> Int? {
        guard cursor.hasPrefix(cursorPrefix) else { return nil }
        return Int(cursor.dropFirst(cursorPrefix.count))
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1_000).rounded())
    }

    private static func newItemId() -> String {
        "demo-" + UUID().uuidString.lowercased()
    }
}
