import Foundation
import MochaProtocol

extension SessionHub {
    func openChat(_ requested: ChatTarget, before: String?, limit: Int?, id: String, clientId: UUID) async {
        let limit = min(max(limit ?? Self.defaultChatLimit, Self.chatLimits.lowerBound), Self.chatLimits.upperBound)
        let target: ChatTarget
        let sessionId: String?
        var subagent: SubagentTranscript?
        switch requested {
        case .agent(let agentId):
            let resolved = await herdr.resolve(agentId)
            guard let agent = await herdr.agent(resolved) else {
                send(.agentNotFound, id: id, to: clientId)
                return
            }
            if agent.kind == TreeComposer.codexKind {
                let threadId = await codex?.threadId(for: resolved)
                await openCodexChat(.agent(resolved), threadId: threadId, before: before, limit: limit, id: id, clientId: clientId)
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
            guard await transcripts.meta(forSession: transcriptSession(requestedSessionId)) != nil else {
                send(.sessionNotFound, id: id, to: clientId)
                return
            }
            target = requested
            sessionId = requestedSessionId
        case .codexThread(let threadId):
            await openCodexChat(requested, threadId: threadId, before: before, limit: limit, id: id, clientId: clientId)
            return
        case .subagent(let requestedSessionId, let agentId):
            guard let transcript = await resolveSubagentTranscript(sessionId: requestedSessionId, agentId: agentId, id: id, clientId: clientId) else {
                return
            }
            target = requested
            sessionId = requestedSessionId
            subagent = transcript
        }
        if let before {
            await sendOlderPage(target, sessionId: sessionId, subagent: subagent, before: before, limit: limit, id: id, clientId: clientId)
        } else {
            await subscribeChat(target, sessionId: sessionId, subagent: subagent, limit: limit, id: id, clientId: clientId)
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
                await transcripts.meta(forSession: transcriptSession(sessionId)) == nil
            {
                send(.sessionNotFound, id: id, to: clientId)
                return
            }
            removeChat(at: target, clientId: clientId)
        case .codexThread:
            removeChat(at: target, clientId: clientId)
        case .subagent(let sessionId, let agentId):
            if clients[clientId]?.chats[target] == nil,
               await resolveSubagentTranscript(sessionId: sessionId, agentId: agentId, id: id, clientId: clientId) == nil {
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
                let meta = chatMeta(for: chat.target, sessionId: chat.sessionId, subagentMeta: chat.subagentMeta)
                guard meta != last, shouldSendChatMeta(meta, previous: last, token: chat.token) else { continue }
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
        subagent: SubagentTranscript?,
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
            let page = try await transcripts.page(session: transcriptSession(sessionId, subagent: subagent), before: before, limit: limit)
            if subagent == nil {
                remember(page.meta, forSession: sessionId, source: nil)
            }
            if let token = clients[clientId]?.chats[target]?.token {
                rememberCards(page.items, token: token, clientId: clientId)
            }
            let chatPage = ChatPage(
                target: target,
                meta: chatMeta(for: target, sessionId: sessionId, subagentMeta: subagent == nil ? nil : page.meta),
                items: overlaid(page.items),
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

    private func subscribeChat(
        _ target: ChatTarget,
        sessionId: String?,
        subagent: SubagentTranscript?,
        limit: Int,
        id: String,
        clientId: UUID
    ) async {
        guard clients[clientId] != nil else { return }
        let token = UUID()
        if let previous = clients[clientId]?.chats[target] {
            previous.cancel()
            forgetCards(token: previous.token)
        }
        var opened = OpenChat(token: token, target: target, sessionId: sessionId)
        opened.subagent = subagent
        clients[clientId]?.chats[target] = opened
        publishOpenChats()
        guard let sessionId else {
            let meta = chatMeta(for: target, sessionId: nil)
            updateChat(token, clientId: clientId) { $0.lastMeta = meta }
            send(.chatPage(ChatPage(target: target, meta: meta, items: [], before: nil, hasMore: false)), id: id, to: clientId)
            return
        }
        let subscription: TranscriptSubscription
        do {
            subscription = try await transcripts.open(session: transcriptSession(sessionId, subagent: subagent), limit: limit)
        } catch {
            removeChat(token, clientId: clientId)
            send(.transcriptFailed, id: id, to: clientId)
            return
        }
        let page = subscription.page
        let subagentMeta = subagent == nil ? nil : page.meta
        if subagent == nil {
            remember(page.meta, forSession: sessionId, source: token)
        }
        let current = chat(token, clientId: clientId)
        let replyTarget = current?.target ?? target
        let meta = chatMeta(for: replyTarget, sessionId: sessionId, subagentMeta: subagentMeta)
        if let current, current.sessionId == sessionId, current.subscription == nil {
            updateChat(token, clientId: clientId) { chat in
                chat.subscription = subscription
                chat.forwarder = chatForwarder(subscription.deltas, token: token, sessionId: sessionId, clientId: clientId)
                chat.lastMeta = meta
                chat.subagentMeta = subagentMeta
            }
            rememberCards(page.items, token: token, clientId: clientId)
        } else {
            subscription.cancel()
        }
        send(
            .chatPage(ChatPage(target: replyTarget, meta: meta, items: overlaid(page.items), before: page.before, hasMore: page.hasMore)),
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
            subscription = try await transcripts.open(session: transcriptSession(sessionId), limit: Self.defaultChatLimit)
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
            rememberCards(subscription.page.items, token: token, clientId: clientId)
            send(.chatAppend(target: current.target, items: overlaid(subscription.page.items)), to: clientId)
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
            rememberCards(items, token: token, clientId: clientId)
            send(.chatAppend(target: chat.target, items: overlaid(items)), to: clientId)
        case .update(let items):
            guard !items.isEmpty else { return }
            rememberCards(items, token: token, clientId: clientId)
            send(.chatUpdate(target: chat.target, items: overlaid(items)), to: clientId)
        case .meta(let meta):
            if chat.subagent != nil {
                updateChat(token, clientId: clientId) { $0.subagentMeta = meta }
                refreshChatMetas()
            } else {
                remember(meta, forSession: sessionId, source: token)
            }
        }
    }

    private func chatMeta(for target: ChatTarget, sessionId: String?, subagentMeta: TranscriptMeta? = nil) -> ChatMeta {
        let meta = sessionId.flatMap { metas[$0] }
        switch target {
        case .agent(let agentId):
            return TreeComposer.agentChatMeta(summary: composedAgent(agentId), meta: meta)
        case .session:
            return TreeComposer.sessionChatMeta(meta: meta, workspaceLabel: archivedWorkspaceLabel(forSession: sessionId))
        case .codexThread:
            return ChatMeta(title: "Codex", workspaceLabel: "", status: .unknown)
        case .subagent(let sessionId, let agentId):
            return subagentChatMeta(sessionId: sessionId, agentId: agentId, meta: subagentMeta)
        }
    }

    func chat(_ token: UUID, clientId: UUID) -> OpenChat? {
        clients[clientId]?.chats.values.first { $0.token == token }
    }

    func updateChat(_ token: UUID, clientId: UUID, _ transform: (inout OpenChat) -> Void) {
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
        forgetCards(token: chat.token)
        publishOpenChats()
    }
}
