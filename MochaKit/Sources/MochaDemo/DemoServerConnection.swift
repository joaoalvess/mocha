import Foundation
import MochaProtocol

public actor DemoServerConnection: ServerConnection {
    public nonisolated let messages: AsyncStream<ServerEnvelope>
    public nonisolated let states: AsyncStream<ConnectionState>

    static let defaultPageSize = 60
    static let maximumPageSize = 200
    static let cursorPrefix = "demo:"
    static let host = HostInfo(hostName: "MacBook", daemonVersion: "0.1.0-demo", herdrConnected: true)
    static let deviceId: DeviceID = "D3E0D3E0-0000-4000-8000-000000000001"
    static let deviceToken = "demo-device-token"
    static let freshContextLeftPercent = 100
    static let claudeOnlyMessage = "Chat disponível só para Claude Code."
    static let agentNotFoundMessage = "Agente não encontrado."
    static let repeatedHelloMessage = "O hello já foi feito nesta conexão."
    static let invalidSessionMessage = "Id de sessão inválido."
    static let sessionNotFoundMessage = "Sessão não encontrada."
    static let invalidSubagentMessage = "Id de subagente inválido."
    static let subagentNotFoundMessage = "Subagente não encontrado"
    static let agentBlockedMessage = "O agente está esperando uma resposta no terminal."
    static let clearCommand = "/clear"
    static let replyMarkdown = """
    Isto é o **modo demo** do Mocha: nenhuma mensagem saiu do iPhone.

    No uso real, o prompt vai para o Claude Code no Mac pelo `mochad`, e a resposta aparece aqui assim que o Claude a grava no transcript.
    """

    private enum SessionSource {
        case live(DemoChat)
        case archived(DemoSessionChat)

        var items: [ChatItem] {
            switch self {
            case .live(let chat): chat.items
            case .archived(let chat): chat.items
            }
        }

        var meta: ChatMeta {
            switch self {
            case .live(let chat): chat.meta
            case .archived(let chat): chat.meta
            }
        }
    }

    private let messageContinuation: AsyncStream<ServerEnvelope>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    private let options: DemoOptions
    private let usage: UsageSnapshot
    private var state: ConnectionState = .idle
    private var isPaired: Bool
    private var herdrConnected = true
    private var workspaces: [WorkspaceNode]
    private var chats: [AgentID: DemoChat]
    private var sessionChats: [String: DemoSessionChat]
    private var archived: [ArchivedSession]
    private var subagents: [DemoSubagent]
    private var movedAgents: [AgentID: AgentID] = [:]
    private var openChats: Set<AgentID> = []
    private var openSessions: Set<String> = []
    private var openSubagents: Set<ChatTarget> = []
    private var preferences = DevicePreferences()
    private var handshakeCount = 0
    private var connectionTask: Task<Void, Never>?
    private var turns: [AgentID: Task<Void, Never>] = [:]
    private var scriptTask: Task<Void, Never>?
    private var nextScriptStep = 0
    private var scriptTurnStartedAt: Date?

    public init(options: DemoOptions = DemoOptions(), now: Date = Date()) throws {
        self.init(dataset: try DemoDataset.bundled(now: now, isEmpty: options.isEmpty), options: options)
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
        self.usage = dataset.usage
        self.isPaired = options.startsPaired
        self.workspaces = dataset.workspaces
        self.chats = Dictionary(dataset.chats.map { ($0.agentId, $0) }, uniquingKeysWith: { first, _ in first })
        self.sessionChats = Dictionary(dataset.sessionChats.map { ($0.session.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.archived = dataset.archived
        self.subagents = dataset.subagents
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
        closeAllChats()
        var host = Self.host
        host.herdrConnected = herdrConnected
        let helloOk = HelloOkPayload(
            host: host,
            deviceId: Self.deviceId,
            deviceToken: pairing ? Self.deviceToken : nil,
            preferences: preferences
        )
        messageContinuation.yield(ServerEnvelope(id: id, message: .helloOk(helloOk)))
        setState(.connected)
        messageContinuation.yield(ServerEnvelope(id: id, message: .tree(workspaces: workspaces)))
        emit(.archived(sessions: archived))
        emit(.usage(usage))
        if options.dropsConnectionAfterTree {
            closeAllChats()
            setState(.waitingToRetry(.unreachable))
            return
        }
        resumeScript()
    }

    private func cancelConnectionWork() {
        connectionTask?.cancel()
        connectionTask = nil
        scriptTask?.cancel()
        scriptTask = nil
        closeAllChats()
    }

    private func closeAllChats() {
        openChats = []
        openSessions = []
        openSubagents = []
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
        case .openChat(.agent(let agentId), let before, let limit):
            openChat(agentId: agentId, before: before, limit: limit, id: id)
        case .openChat(.session(let sessionId), let before, let limit):
            openSessionChat(sessionId: sessionId, before: before, limit: limit, id: id)
        case .closeChat(.agent(let agentId)):
            openChats.remove(currentId(for: agentId))
            reply(id, .ack())
        case .closeChat(.session(let sessionId)):
            guard sessionSource(sessionId, replyingTo: id) != nil else { return }
            openSessions.remove(sessionId)
            reply(id, .ack())
        case .openChat(.subagent(let sessionId, let agentId), let before, let limit):
            openSubagentChat(sessionId: sessionId, agentId: agentId, before: before, limit: limit, id: id)
        case .closeChat(.subagent(let sessionId, let agentId)):
            guard subagent(sessionId: sessionId, agentId: agentId, replyingTo: id) != nil else { return }
            openSubagents.remove(.subagent(sessionId: sessionId, agentId: agentId))
            reply(id, .ack())
        case .listSubagents(let agentId):
            listSubagents(agentId: agentId, id: id)
        case .archive(let sessionId):
            archive(sessionId: sessionId, id: id)
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
        case .slash(let agentId, let command):
            runSlash(agentId: agentId, command: command, id: id)
        case .setPreferences(let newPreferences):
            preferences = newPreferences
            reply(id, .ack())
        case .respond:
            fail(id, .requestNotFound, "Pedido não encontrado.")
        case .newAgentTab(let workspaceId):
            newAgentTab(in: workspaceId, id: id)
        case .unknown:
            fail(id, .unknownType, "Tipo de mensagem desconhecido: \(message.type).")
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

    private func sessionSource(_ sessionId: String, replyingTo id: String) -> SessionSource? {
        guard UUID(uuidString: sessionId) != nil else {
            fail(id, .invalidPayload, Self.invalidSessionMessage)
            return nil
        }
        if let agent = workspaces.agent(withSessionId: sessionId), let chat = chats[agent.id] {
            return .live(chat)
        }
        if let chat = sessionChats[sessionId] {
            return .archived(chat)
        }
        fail(id, .sessionNotFound, Self.sessionNotFoundMessage)
        return nil
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
        guard let page = page(of: chat.items, target: .agent(chat.agentId), meta: chat.meta, before: before, limit: limit, id: id) else {
            return
        }
        openChats.insert(chat.agentId)
        reply(id, .chatPage(page))
    }

    private func openSessionChat(sessionId: String, before: String?, limit: Int?, id: String) {
        guard let source = sessionSource(sessionId, replyingTo: id) else { return }
        let target = ChatTarget.session(sessionId)
        guard let page = page(of: source.items, target: target, meta: source.meta, before: before, limit: limit, id: id) else {
            return
        }
        openSessions.insert(sessionId)
        reply(id, .chatPage(page))
    }

    private func subagent(sessionId: String, agentId: String, replyingTo id: String) -> DemoSubagent? {
        guard UUID(uuidString: sessionId) != nil else {
            fail(id, .invalidPayload, Self.invalidSessionMessage)
            return nil
        }
        guard Self.isValidSubagentId(agentId) else {
            fail(id, .invalidPayload, Self.invalidSubagentMessage)
            return nil
        }
        guard let subagent = subagents.subagent(sessionId: sessionId, agentId: agentId) else {
            fail(id, .sessionNotFound, Self.subagentNotFoundMessage)
            return nil
        }
        return subagent
    }

    private func openSubagentChat(sessionId: String, agentId: String, before: String?, limit: Int?, id: String) {
        guard let subagent = subagent(sessionId: sessionId, agentId: agentId, replyingTo: id) else { return }
        let target = ChatTarget.subagent(sessionId: sessionId, agentId: agentId)
        guard let page = page(of: subagent.items, target: target, meta: meta(of: subagent), before: before, limit: limit, id: id) else {
            return
        }
        openSubagents.insert(target)
        reply(id, .chatPage(page))
    }

    private func meta(of subagent: DemoSubagent) -> ChatMeta {
        let parentMeta = sessionMeta(subagent.sessionId)
        let parentTitle = subagent.parentAgentId
            .flatMap { subagents.subagent(sessionId: subagent.sessionId, agentId: $0)?.description }
            ?? parentMeta?.title
            ?? ""
        return ChatMeta(
            title: subagent.description,
            workspaceLabel: parentMeta?.workspaceLabel ?? "",
            model: parentMeta?.model,
            branch: parentMeta?.branch,
            status: .unknown,
            subagent: subagent.chatInfo(parentTitle: parentTitle)
        )
    }

    private func sessionMeta(_ sessionId: String) -> ChatMeta? {
        if let agent = workspaces.agent(withSessionId: sessionId), let chat = chats[agent.id] {
            return chat.meta
        }
        return sessionChats[sessionId]?.meta
    }

    private func listSubagents(agentId: AgentID, id: String) {
        let current = currentId(for: agentId)
        guard let agent = workspaces.agent(withId: current) else {
            return fail(id, .agentNotFound, Self.agentNotFoundMessage)
        }
        guard agent.kind == "claude" else {
            return fail(id, .invalidPayload, Self.claudeOnlyMessage)
        }
        let items = agent.sessionId.map { subagents.summaries(inSession: $0) } ?? []
        reply(id, .subagentList(agentId: current, items: items))
    }

    private func page(of items: [ChatItem], target: ChatTarget, meta: ChatMeta, before: String?, limit: Int?, id: String) -> ChatPage? {
        var end = items.count
        if let before {
            guard let index = Self.index(fromCursor: before), (0...items.count).contains(index) else {
                fail(id, .invalidPayload, "Cursor de paginação inválido.")
                return nil
            }
            end = index
        }
        let pageSize = min(max(limit ?? Self.defaultPageSize, 1), Self.maximumPageSize)
        let start = max(0, end - pageSize)
        let hasMore = start > 0
        return ChatPage(
            target: target,
            meta: meta,
            items: Array(items[start..<end]),
            before: hasMore ? Self.cursor(forIndex: start) : nil,
            hasMore: hasMore
        )
    }

    private func archive(sessionId: String, id: String) {
        guard let agent = workspaces.agent(withSessionId: sessionId) else {
            return fail(id, .sessionNotFound, Self.sessionNotFoundMessage)
        }
        let now = Date()
        workspaces.updateAgent(withId: agent.id) { $0.archivedAt = now }
        reply(id, .ack())
        emitTree()
    }

    private func sendPrompt(agentId: AgentID, text: String, id: String) {
        guard let chat = claudeChat(agentId, replyingTo: id) else { return }
        guard chat.meta.status != .blocked else {
            return fail(id, .agentBlocked, Self.agentBlockedMessage)
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
        let prompt = DemoImageMarkers.split(text)
        append([ChatItem(id: Self.newItemId(), at: now, kind: .userPrompt(text: prompt.text, imageCount: prompt.imageCount))], to: current)
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

    private func newAgentTab(in workspaceId: WorkspaceID, id: String) {
        guard workspaces.workspace(withId: workspaceId) != nil else {
            return fail(id, .invalidPayload, DemoNewAgentTab.workspaceNotFoundMessage)
        }
        let handshake = handshakeCount
        Task { [weak self, delay = options.newAgentTabDelay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.openAgentTab(in: workspaceId, id: id, handshake: handshake)
        }
    }

    private func openAgentTab(in workspaceId: WorkspaceID, id: String, handshake: Int) {
        let isSameConnection = state == .connected && handshakeCount == handshake
        guard let workspace = workspaces.workspace(withId: workspaceId) else {
            if isSameConnection {
                fail(id, .invalidPayload, DemoNewAgentTab.workspaceNotFoundMessage)
            }
            return
        }
        let takenAgentIds = Set(workspaces.allAgents.map(\.id))
            .union(movedAgents.keys)
            .union(movedAgents.values)
            .union(DemoScript.reservedAgentIds)
        let newTab = DemoNewAgentTab(in: workspace, takenAgentIds: takenAgentIds, now: Date())
        chats[newTab.agentId] = newTab.chat
        workspaces.updateWorkspace(withId: workspaceId) { workspace in
            workspace.tabs.append(newTab.tab)
            workspace.agentStatus = workspace.aggregatedAgentStatus
        }
        emitTree()
        if isSameConnection {
            reply(id, .ack(agentId: newTab.agentId))
        }
    }

    private func runSlash(agentId: AgentID, command: String, id: String) {
        guard let chat = claudeChat(agentId, replyingTo: id) else { return }
        guard chat.meta.status != .blocked else {
            return fail(id, .agentBlocked, Self.agentBlockedMessage)
        }
        reply(id, .ack())
        guard Self.isClear(command) else { return }
        clearSession(of: chat.agentId)
    }

    private func clearSession(of agentId: AgentID) {
        turns.removeValue(forKey: agentId)?.cancel()
        if chats[agentId]?.meta.status == .working {
            setStatus(.idle, for: agentId)
        }
        let now = Date()
        let clearItem = ChatItem(id: Self.newItemId(), at: now, kind: .slashCommand(name: Self.clearCommand, args: "", output: nil))
        switchSession(of: agentId, to: UUID().uuidString.lowercased(), startingWith: clearItem, at: now)
    }

    private func append(_ newItems: [ChatItem], to agentId: AgentID) {
        guard chats[agentId] != nil, !newItems.isEmpty else { return }
        chats[agentId]?.items.append(contentsOf: newItems)
        refreshHomeFields(of: agentId)
        emitChatEvent(for: agentId) { .chatAppend(target: $0, items: newItems) }
    }

    private func replace(_ item: ChatItem, in agentId: AgentID) {
        guard let index = chats[agentId]?.items.firstIndex(where: { $0.id == item.id }) else { return }
        chats[agentId]?.items[index] = item
        refreshHomeFields(of: agentId)
        emitChatEvent(for: agentId) { .chatUpdate(target: $0, items: [item]) }
    }

    private func finishSubagent(sessionId: String, agentId: String, at date: Date) {
        guard let index = subagents.firstIndex(where: { $0.sessionId == sessionId && $0.agentId == agentId }),
              subagents[index].status == .running,
              !subagents[index].isWorkflowAgent
        else { return }
        let finish = subagents[index].finished(at: date, answer: DemoSubagents.loadTestAnswer, result: DemoSubagents.loadTestResult)
        subagents[index] = finish.subagent
        replaceCard(of: finish.subagent)
        let target = ChatTarget.subagent(sessionId: sessionId, agentId: agentId)
        if openSubagents.contains(target) {
            if !finish.updated.isEmpty {
                emit(.chatUpdate(target: target, items: finish.updated))
            }
            emit(.chatAppend(target: target, items: finish.appended))
            emit(.chatMeta(target: target, meta: meta(of: finish.subagent)))
        }
        guard let agent = workspaces.agent(withSessionId: sessionId) else { return }
        let running = subagents.runningSubagents(inSession: sessionId)
        workspaces.updateAgent(withId: agent.id) { $0.runningSubagents = running }
        emitTree()
    }

    private func replaceCard(of subagent: DemoSubagent) {
        if let parentAgentId = subagent.parentAgentId {
            guard let parent = subagents.firstIndex(where: { $0.sessionId == subagent.sessionId && $0.agentId == parentAgentId }),
                  let card = subagents[parent].items.firstIndex(where: { $0.id == subagent.cardId })
            else { return }
            subagents[parent].items[card].kind = .subagent(subagent.call)
            let target = ChatTarget.subagent(sessionId: subagent.sessionId, agentId: parentAgentId)
            if openSubagents.contains(target) {
                emit(.chatUpdate(target: target, items: [subagents[parent].items[card]]))
            }
            return
        }
        if let agent = workspaces.agent(withSessionId: subagent.sessionId),
           let card = chats[agent.id]?.items.firstIndex(where: { $0.id == subagent.cardId }) {
            chats[agent.id]?.items[card].kind = .subagent(subagent.call)
            guard let item = chats[agent.id]?.items[card] else { return }
            emitChatEvent(for: agent.id) { .chatUpdate(target: $0, items: [item]) }
            return
        }
        guard let card = sessionChats[subagent.sessionId]?.items.firstIndex(where: { $0.id == subagent.cardId }) else { return }
        sessionChats[subagent.sessionId]?.items[card].kind = .subagent(subagent.call)
        guard let item = sessionChats[subagent.sessionId]?.items[card], openSessions.contains(subagent.sessionId) else { return }
        emit(.chatUpdate(target: .session(subagent.sessionId), items: [item]))
    }

    private func refreshHomeFields(of agentId: AgentID) {
        guard let items = chats[agentId]?.items else { return }
        workspaces.updateAgent(withId: agentId) { $0.refreshHomeFields(from: items) }
    }

    private func emitChatEvent(for agentId: AgentID, _ message: (ChatTarget) -> ServerMessage) {
        if openChats.contains(agentId) {
            emit(message(.agent(agentId)))
        }
        if let sessionId = workspaces.agent(withId: agentId)?.sessionId, openSessions.contains(sessionId) {
            emit(message(.session(sessionId)))
        }
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
            refreshHomeFields(of: DemoScript.worktreeAgentId)
            emitTree()
        case .startTurn:
            scriptTurnStartedAt = now
            append([DemoScript.prompt(at: now)], to: turnAgent)
            setStatus(.working, for: turnAgent)
        case .appendThinking:
            append([DemoScript.thinking(at: now)], to: turnAgent)
            emitTree()
        case .appendPlan:
            append([DemoScript.plan(at: now)], to: turnAgent)
            emitTree()
        case .appendRead:
            append([DemoScript.read(at: now)], to: turnAgent)
            emitTree()
        case .appendRunningTool:
            append([DemoScript.testRun(at: now, status: .running)], to: turnAgent)
            emitTree()
        case .finishRunningTool:
            let startedAt = chats[turnAgent]?.items.first { $0.id == DemoScript.runningToolItemId }?.at ?? now
            replace(DemoScript.testRun(at: startedAt, status: .succeeded), in: turnAgent)
            emitTree()
        case .renameChat:
            rename(turnAgent, to: DemoScript.renamedTitle)
        case .finishTurn:
            let durationMs = Self.milliseconds(from: scriptTurnStartedAt ?? now, to: now)
            append(DemoScript.finalAnswer(at: now, durationMs: durationMs), to: turnAgent)
            setStatus(.idle, for: turnAgent)
        case .switchSession:
            switchSession(of: currentId(for: DemoScript.worktreeAgentId), to: DemoScript.clearedSessionId, startingWith: DemoScript.clearCommand(at: now), at: now)
        case .moveAgent:
            moveAgent(from: currentId(for: DemoScript.movedAgentId), to: DemoScript.movedAgentNewId)
        case .finishWorkingAgent:
            finishWorkingAgent(currentId(for: DemoScript.finishingAgentId), at: now)
        case .finishSubagent:
            finishSubagent(sessionId: DemoScript.finishingSubagentSessionId, agentId: DemoScript.finishingSubagentId, at: now)
        case .disconnectHerdr:
            setHerdrConnected(false)
        case .reconnectHerdr:
            setHerdrConnected(true)
        case .dropConnection:
            closeAllChats()
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
        emitChatEvent(for: agentId) { .chatMeta(target: $0, meta: meta) }
        emitTree()
    }

    private func switchSession(of agentId: AgentID, to sessionId: String, startingWith clearItem: ChatItem, at date: Date) {
        guard let chat = chats[agentId], let agent = workspaces.agent(withId: agentId), let previousSessionId = agent.sessionId else {
            return
        }
        let session = ArchivedSession(
            id: previousSessionId,
            agentId: agentId,
            title: agent.title,
            workspaceLabel: agent.workspaceLabel,
            model: agent.model,
            branch: agent.branch,
            preview: agent.preview,
            contextLeftPercent: agent.contextLeftPercent,
            reason: .cleared,
            endedAt: date,
            sessionStartedAt: agent.sessionStartedAt,
            lastActivityAt: agent.lastActivityAt
        )
        sessionChats[previousSessionId] = DemoSessionChat(session: session, items: chat.items)
        archived = (archived.filter { $0.id != previousSessionId } + [session]).sortedByRecency()
        let items = [clearItem]
        chats[agentId]?.items = items
        let running = subagents.runningSubagents(inSession: sessionId)
        workspaces.updateAgent(withId: agentId) { agent in
            agent.sessionId = sessionId
            agent.runningSubagents = running
            agent.contextLeftPercent = Self.freshContextLeftPercent
            agent.archivedAt = nil
            agent.refreshHomeFields(from: items)
        }
        emitTree()
        emit(.archived(sessions: archived))
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

    private func finishWorkingAgent(_ agentId: AgentID, at date: Date) {
        guard let agent = workspaces.agent(withId: agentId), agent.status == .working else { return }
        let durationMs = Self.milliseconds(from: agent.turnStartedAt ?? date, to: date)
        append(DemoScript.workingAgentAnswer(at: date, durationMs: durationMs), to: agentId)
        setStatus(.idle, for: agentId)
    }

    private func setHerdrConnected(_ connected: Bool) {
        guard herdrConnected != connected else { return }
        herdrConnected = connected
        emit(.herdrStatus(connected: connected))
    }

    static func isClear(_ command: String) -> Bool {
        command.split(whereSeparator: \.isWhitespace).first == Substring(clearCommand)
    }

    static func isValidSubagentId(_ agentId: String) -> Bool {
        agentId.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil
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
