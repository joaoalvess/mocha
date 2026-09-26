import Foundation
import MochaProtocol

extension SessionHub {
    func openChat(_ requested: ChatTarget, before: String?, limit: Int?, id: String, clientId: UUID) async {
        let limit = min(max(limit ?? Self.defaultChatLimit, Self.chatLimits.lowerBound), Self.chatLimits.upperBound)
        let target: ChatTarget
        let sessionId: String?
        switch requested {
        case .agent(let agentId):
            let resolved = await herdr.resolve(agentId)
            guard let agent = await herdr.agent(resolved) else {
                send(.agentNotFound, id: id, to: clientId)
                return
            }
            guard agent.kind == TreeComposer.claudeKind else {
                send(.notClaude, id: id, to: clientId)
                return
            }
            target = .agent(resolved)
            sessionId = agent.sessionId
        case .session(let requestedSessionId):
            guard UUID(uuidString: requestedSessionId) != nil else {
                send(.invalidSessionId, id: id, to: clientId)
                return
            }
            guard await transcripts.meta(forSession: TranscriptSession(sessionId: requestedSessionId)) != nil else {
                send(.sessionNotFound, id: id, to: clientId)
                return
            }
            target = requested
            sessionId = requestedSessionId
        }
        if let before {
            await sendOlderPage(target, sessionId: sessionId, before: before, limit: limit, id: id, clientId: clientId)
        } else {
            await subscribeChat(target, sessionId: sessionId, limit: limit, id: id, clientId: clientId)
        }
    }

    func closeChat(_ target: ChatTarget, id: String, clientId: UUID) async {
        switch target {
        case .agent(let agentId):
            let resolved = await herdr.resolve(agentId)
            removeChat(at: .agent(agentId), clientId: clientId)
            removeChat(at: .agent(resolved), clientId: clientId)
        case .session(let sessionId):
            guard UUID(uuidString: sessionId) != nil else {
                send(.invalidSessionId, id: id, to: clientId)
                return
            }
            if clients[clientId]?.chats[target] == nil,
                await transcripts.meta(forSession: TranscriptSession(sessionId: sessionId)) == nil
            {
                send(.sessionNotFound, id: id, to: clientId)
                return
            }
            removeChat(at: target, clientId: clientId)
        }
        send(.ack(), id: id, to: clientId)
    }

    func refreshChatMetas() {
        for (clientId, client) in clients where client.isAuthenticated && !client.isClosing {
            for (key, chat) in client.chats {
                guard let last = chat.lastMeta else { continue }
                let meta = chatMeta(for: chat.target, sessionId: chat.sessionId)
                guard meta != last else { continue }
                clients[clientId]?.chats[key]?.lastMeta = meta
                send(.chatMeta(target: chat.target, meta: meta), to: clientId)
            }
        }
    }

    func switchChats(ofAgent agentId: AgentID, toSession sessionId: String?) async {
        for (clientId, client) in clients {
            guard let chat = client.chats[.agent(agentId)], chat.sessionId != sessionId else { continue }
            await switchChat(token: chat.token, clientId: clientId, toSession: sessionId)
        }
    }

    private func sendOlderPage(
        _ target: ChatTarget,
        sessionId: String?,
        before: String,
        limit: Int,
        id: String,
        clientId: UUID
    ) async {
        guard let sessionId else {
            send(.invalidCursor, id: id, to: clientId)
            return
        }
        do {
            let page = try await transcripts.page(session: TranscriptSession(sessionId: sessionId), before: before, limit: limit)
            remember(page.meta, forSession: sessionId, source: nil)
            let chatPage = ChatPage(
                target: target,
                meta: chatMeta(for: target, sessionId: sessionId),
                items: page.items,
                before: page.before,
                hasMore: page.hasMore
            )
            send(.chatPage(chatPage), id: id, to: clientId)
        } catch TranscriptError.invalidCursor {
            send(.invalidCursor, id: id, to: clientId)
        } catch {
            send(.transcriptFailed, id: id, to: clientId)
        }
    }

    private func subscribeChat(_ target: ChatTarget, sessionId: String?, limit: Int, id: String, clientId: UUID) async {
        guard clients[clientId] != nil else { return }
        let token = UUID()
        clients[clientId]?.chats[target]?.cancel()
        clients[clientId]?.chats[target] = OpenChat(token: token, target: target, sessionId: sessionId)
        publishOpenChats()
        guard let sessionId else {
            let meta = chatMeta(for: target, sessionId: nil)
            updateChat(token, clientId: clientId) { $0.lastMeta = meta }
            send(.chatPage(ChatPage(target: target, meta: meta, items: [], before: nil, hasMore: false)), id: id, to: clientId)
            return
        }
        let subscription: TranscriptSubscription
        do {
            subscription = try await transcripts.open(session: TranscriptSession(sessionId: sessionId), limit: limit)
        } catch {
            removeChat(token, clientId: clientId)
            send(.transcriptFailed, id: id, to: clientId)
            return
        }
        let page = subscription.page
        remember(page.meta, forSession: sessionId, source: token)
        let current = chat(token, clientId: clientId)
        let replyTarget = current?.target ?? target
        let meta = chatMeta(for: replyTarget, sessionId: sessionId)
        if let current, current.sessionId == sessionId, current.subscription == nil {
            updateChat(token, clientId: clientId) { chat in
                chat.subscription = subscription
                chat.forwarder = chatForwarder(subscription.deltas, token: token, sessionId: sessionId, clientId: clientId)
                chat.lastMeta = meta
            }
        } else {
            subscription.cancel()
        }
        send(
            .chatPage(ChatPage(target: replyTarget, meta: meta, items: page.items, before: page.before, hasMore: page.hasMore)),
            id: id,
            to: clientId
        )
    }

    private func switchChat(token: UUID, clientId: UUID, toSession sessionId: String?) async {
        guard let previous = chat(token, clientId: clientId) else { return }
        let learnsSession = previous.sessionId == nil
        previous.cancel()
        updateChat(token, clientId: clientId) { chat in
            chat.sessionId = sessionId
            chat.subscription = nil
            chat.forwarder = nil
        }
        guard let sessionId else { return }
        let subscription: TranscriptSubscription
        do {
            subscription = try await transcripts.open(session: TranscriptSession(sessionId: sessionId), limit: Self.defaultChatLimit)
        } catch {
            gatewayLogger.error("failed to follow the new session of a chat: \(String(describing: error), privacy: .public)")
            return
        }
        guard let current = chat(token, clientId: clientId), current.sessionId == sessionId, current.subscription == nil else {
            subscription.cancel()
            return
        }
        updateChat(token, clientId: clientId) { chat in
            chat.subscription = subscription
            chat.forwarder = chatForwarder(subscription.deltas, token: token, sessionId: sessionId, clientId: clientId)
        }
        remember(subscription.page.meta, forSession: sessionId, source: token)
        if learnsSession, !subscription.page.items.isEmpty {
            send(.chatAppend(target: current.target, items: subscription.page.items), to: clientId)
        }
    }

    private func chatForwarder(
        _ deltas: AsyncStream<TranscriptDelta>,
        token: UUID,
        sessionId: String,
        clientId: UUID
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await delta in deltas {
                await self?.chatDelta(delta, token: token, sessionId: sessionId, clientId: clientId)
            }
        }
    }

    private func chatDelta(_ delta: TranscriptDelta, token: UUID, sessionId: String, clientId: UUID) {
        guard let chat = chat(token, clientId: clientId), chat.sessionId == sessionId else { return }
        switch delta {
        case .append(let items):
            guard !items.isEmpty else { return }
            send(.chatAppend(target: chat.target, items: items), to: clientId)
        case .update(let items):
            guard !items.isEmpty else { return }
            send(.chatUpdate(target: chat.target, items: items), to: clientId)
        case .meta(let meta):
            remember(meta, forSession: sessionId, source: token)
        }
    }

    private func chatMeta(for target: ChatTarget, sessionId: String?) -> ChatMeta {
        let meta = sessionId.flatMap { metas[$0] }
        switch target {
        case .agent(let agentId):
            return TreeComposer.agentChatMeta(summary: composedAgent(agentId), meta: meta)
        case .session:
            return TreeComposer.sessionChatMeta(meta: meta, workspaceLabel: archivedWorkspaceLabel(forSession: sessionId))
        }
    }

    private func chat(_ token: UUID, clientId: UUID) -> OpenChat? {
        clients[clientId]?.chats.values.first { $0.token == token }
    }

    private func updateChat(_ token: UUID, clientId: UUID, _ transform: (inout OpenChat) -> Void) {
        guard let key = clients[clientId]?.chats.first(where: { $0.value.token == token })?.key else { return }
        guard var chat = clients[clientId]?.chats[key] else { return }
        transform(&chat)
        clients[clientId]?.chats[key] = chat
    }

    private func removeChat(_ token: UUID, clientId: UUID) {
        guard let key = clients[clientId]?.chats.first(where: { $0.value.token == token })?.key else { return }
        removeChat(at: key, clientId: clientId)
    }

    private func removeChat(at target: ChatTarget, clientId: UUID) {
        guard let chat = clients[clientId]?.chats.removeValue(forKey: target) else { return }
        chat.cancel()
        publishOpenChats()
    }
}
