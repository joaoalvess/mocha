import Foundation
import MochaProtocol

extension HubError {
    static let codexUnavailable = HubError(code: .codexUnavailable, message: "Controle indisponível nesta tab Codex.")
    static let codexFailed = HubError(code: .internal, message: "Falha ao falar com o Codex no Mac.")
    static let codexInvalidImage = HubError(code: .invalidPayload, message: "Imagem inválida para o Codex.")
}

extension SessionHub {
    static let codexRefreshDelay: Duration = .milliseconds(250)
    static let codexRefreshLimit = 30

    func attachCodex(_ codex: any CodexServing) {
        self.codex = codex
    }

    func startCodexUpdates() {
        guard let codex else { return }
        let updates = codex.updates
        sessionServiceTasks.append(Task { [weak self] in
            for await update in updates {
                await self?.codexUpdated(update)
            }
        })
        let events = codex.threadEvents()
        sessionServiceTasks.append(Task { [weak self] in
            for await event in events {
                await self?.codexThreadEvent(event)
            }
        })
    }

    func retainCodexPanes() async {
        guard let codex, herdrAvailable else { return }
        let ids = Set(TreeComposer.agents(in: baseTree).filter { $0.kind == TreeComposer.codexKind }.map(\.id))
        await codex.retainPanes(ids)
    }

    func runCodex(_ command: AgentCommand, agent: HerdrAgent, id: String, clientId: UUID) async {
        guard let codex else {
            send(.codexUnavailable, id: id, to: clientId)
            return
        }
        do {
            switch command {
            case .prompt(let text):
                try await codex.prompt(agent, text: text)
            case .interrupt:
                try await codex.interrupt(agent)
            }
            send(.ack(), id: id, to: clientId)
        } catch CodexServiceError.noActiveTurn {
            send(.ack(), id: id, to: clientId)
        } catch CodexServiceError.invalidImage {
            send(.codexInvalidImage, id: id, to: clientId)
        } catch CodexServiceError.unverifiedAgent {
            send(.codexUnavailable, id: id, to: clientId)
        } catch {
            gatewayLogger.error("codex command failed: \(String(describing: error), privacy: .public)")
            send(.codexFailed, id: id, to: clientId)
        }
    }

    func openCodexTab(in workspaceId: WorkspaceID, id: String, clientId: UUID) async {
        guard let codex else {
            send(.codexUnavailable, id: id, to: clientId)
            return
        }
        guard await herdr.isAvailable else {
            send(.herdrUnavailable, id: id, to: clientId)
            return
        }
        guard TreeComposer.containsWorkspace(workspaceId, in: baseTree) else {
            send(.workspaceNotFound, id: id, to: clientId)
            return
        }
        let herdr = herdr
        let remote = "unix://\(codex.socketPath)"
        let since = Date().addingTimeInterval(-2)
        Task { [weak self] in
            let reply: Result<AgentID, HubError>
            do {
                let created = try await herdr.newCodexTab(in: workspaceId, remote: remote)
                let cwd = await herdr.agent(created.paneId)?.cwd ?? created.cwd
                if let cwd {
                    await codex.expectPane(created.paneId, cwd: cwd, since: since)
                }
                reply = .success(created.paneId)
            } catch let error as HerdrBridgeError {
                reply = .failure(.herdr(error))
            } catch {
                reply = .failure(.herdrFailed)
            }
            await self?.finishCodexTab(reply, id: id, clientId: clientId)
        }
    }

    func answerCodex(_ requestId: RequestID, with response: PendingResponse) async throws(PendingRespondError) {
        guard let codex else { throw PendingRespondError.requestNotFound }
        do {
            try await codex.respond(to: requestId, with: response)
        } catch CodexServiceError.invalidResponse {
            throw PendingRespondError.invalidPayload("Resposta inválida para este pedido do Codex.")
        } catch CodexServiceError.requestNotFound {
            throw PendingRespondError.requestNotFound
        } catch {
            gatewayLogger.error("codex respond failed: \(String(describing: error), privacy: .public)")
            throw PendingRespondError.requestNotFound
        }
    }

    func moveCodexPane(from oldId: AgentID, to newId: AgentID) async {
        guard let codex, oldId != newId else { return }
        if let pane = codexPanes.removeValue(forKey: oldId) {
            codexPanes[newId] = pane
        }
        await codex.movePane(from: oldId, to: newId)
    }

    func openCodexChat(_ target: ChatTarget, threadId: String?, before: String?, limit: Int, id: String, clientId: UUID) async {
        guard let codex, let threadId else {
            guard before == nil else {
                send(.invalidCursor, id: id, to: clientId)
                return
            }
            let token = registerCodexChat(target, threadId: nil, items: [], clientId: clientId)
            let meta = codexChatMeta(for: target)
            updateChat(token, clientId: clientId) { $0.lastMeta = meta }
            send(.chatPage(ChatPage(target: target, meta: meta, items: [], before: nil, hasMore: false)), id: id, to: clientId)
            return
        }
        let page: CodexThreadPage
        do {
            page = try await codex.page(threadId: threadId, before: before, limit: limit)
        } catch {
            if case .codexThread = target {
                send(.sessionNotFound, id: id, to: clientId)
            } else {
                send(.codexFailed, id: id, to: clientId)
            }
            return
        }
        let meta = codexChatMeta(for: target)
        if before == nil {
            let token = registerCodexChat(target, threadId: threadId, items: page.items, clientId: clientId)
            updateChat(token, clientId: clientId) { $0.lastMeta = meta }
        } else if let token = clients[clientId]?.chats[target]?.token {
            updateChat(token, clientId: clientId) { chat in
                for item in page.items {
                    chat.codexItems[item.id] = item
                }
            }
        }
        send(
            .chatPage(ChatPage(target: target, meta: meta, items: overlaid(page.items), before: page.before, hasMore: page.before != nil)),
            id: id,
            to: clientId
        )
    }

    private func finishCodexTab(_ reply: Result<AgentID, HubError>, id: String, clientId: UUID) {
        switch reply {
        case .success(let agentId):
            send(.ack(agentId: agentId), id: id, to: clientId)
        case .failure(let error):
            send(error, id: id, to: clientId)
        }
    }

    private func registerCodexChat(_ target: ChatTarget, threadId: String?, items: [ChatItem], clientId: UUID) -> UUID {
        let token = UUID()
        if let previous = clients[clientId]?.chats[target] {
            previous.cancel()
            forgetCards(token: previous.token)
        }
        var opened = OpenChat(token: token, target: target, sessionId: nil)
        opened.codexThreadId = threadId
        opened.codexItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        clients[clientId]?.chats[target] = opened
        publishOpenChats()
        return token
    }

    private func codexChatMeta(for target: ChatTarget) -> ChatMeta {
        switch target {
        case .agent(let agentId):
            return TreeComposer.agentChatMeta(summary: composedAgent(agentId), meta: nil)
        default:
            return ChatMeta(title: "Codex", workspaceLabel: "", status: .unknown)
        }
    }

    private func codexUpdated(_ update: CodexServiceUpdate) async {
        switch update {
        case .availability(let connected):
            guard codexConnected != connected else { return }
            codexConnected = connected
            scheduleTreeFlush()
        case .panes(let panes):
            let previous = codexPanes
            codexPanes = panes
            for (agentId, pane) in panes where previous[agentId]?.status != pane.status || previous[agentId]?.title != pane.title {
                broadcast(.agentStatus(agentId: agentId, status: pane.status, title: composedAgent(agentId)?.title))
            }
            await followCodexThreads()
            scheduleTreeFlush()
        case .pending(let requests):
            guard requests != codexPendingRequests else { return }
            codexPendingRequests = requests
            mergePending()
        case .decisions(let decisions):
            codexDecisions = decisions
            mergeDecisions()
            scheduleTreeFlush()
        case .usage(let snapshot):
            codexUsage = snapshot
            broadcast(.usage(snapshot))
        case .alert(let alert):
            codexAlertContinuation.yield(alert)
        }
    }

    private func codexThreadEvent(_ event: CodexThreadEvent) async {
        switch event {
        case .item(let item):
            deliverCodexItems(item.chatItems, threadId: item.threadId)
        case .turn(let threadId, let turn, let chatItems):
            deliverCodexItems(chatItems, threadId: threadId)
            guard turn.status != .inProgress,
                  let agentId = codexPanes.first(where: { $0.value.threadId == threadId })?.key else { return }
            let herdr = herdr
            Task { await herdr.refreshDirtyState(ofAgent: agentId) }
        case .settings:
            break
        case .resubscribed(let threadId):
            scheduleCodexRefresh(threadId)
        }
    }

    private func deliverCodexItems(_ items: [ChatItem], threadId: String) {
        guard !items.isEmpty else { return }
        for (clientId, client) in clients {
            for chat in client.chats.values where chat.codexThreadId == threadId {
                let appended = items.filter { chat.codexItems[$0.id] == nil }
                let changed = items.filter { item in chat.codexItems[item.id].map { $0 != item } ?? false }
                guard !appended.isEmpty || !changed.isEmpty else { continue }
                updateChat(chat.token, clientId: clientId) { chat in
                    for item in items {
                        chat.codexItems[item.id] = item
                    }
                }
                if !appended.isEmpty {
                    send(.chatAppend(target: chat.target, items: overlaid(appended)), to: clientId)
                }
                if !changed.isEmpty {
                    send(.chatUpdate(target: chat.target, items: overlaid(changed)), to: clientId)
                }
            }
        }
    }

    private func followCodexThreads() async {
        for (clientId, client) in clients {
            for (target, chat) in client.chats {
                guard case .agent(let agentId) = target, let threadId = codexPanes[agentId]?.threadId,
                      chat.codexThreadId != threadId, chat.subscription == nil else { continue }
                let switched = chat.codexThreadId != nil
                updateChat(chat.token, clientId: clientId) { chat in
                    chat.codexThreadId = threadId
                    chat.codexItems = [:]
                }
                if !switched {
                    scheduleCodexRefresh(threadId)
                }
            }
        }
    }

    private func scheduleCodexRefresh(_ threadId: String) {
        guard codexRefreshes[threadId] == nil, !isShuttingDown else { return }
        let clock = clock
        codexRefreshes[threadId] = Task { [weak self] in
            guard (try? await clock.sleep(for: Self.codexRefreshDelay)) != nil else { return }
            await self?.refreshCodexThread(threadId)
        }
    }

    private func refreshCodexThread(_ threadId: String) async {
        codexRefreshes[threadId] = nil
        guard let codex else { return }
        let watchers = clients.flatMap { clientId, client in
            client.chats.values.filter { $0.codexThreadId == threadId }.map { (clientId, $0.token) }
        }
        guard !watchers.isEmpty,
              let page = try? await codex.page(threadId: threadId, before: nil, limit: Self.codexRefreshLimit) else { return }
        for (clientId, token) in watchers {
            guard let chat = chat(token, clientId: clientId), chat.codexThreadId == threadId else { continue }
            let appended = page.items.filter { chat.codexItems[$0.id] == nil }
            let changed = page.items.filter { item in chat.codexItems[item.id].map { $0 != item } ?? false }
            updateChat(token, clientId: clientId) { chat in
                for item in page.items {
                    chat.codexItems[item.id] = item
                }
            }
            if !appended.isEmpty {
                send(.chatAppend(target: chat.target, items: overlaid(appended)), to: clientId)
            }
            if !changed.isEmpty {
                send(.chatUpdate(target: chat.target, items: overlaid(changed)), to: clientId)
            }
        }
        refreshChatMetas()
    }
}
