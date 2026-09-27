import Foundation
import MochaProtocol

extension SessionHub {
    static let cardInterval: TimeInterval = 1

    struct CardThrottle {
        let clientId: UUID
        let token: UUID
        let itemId: String
        var lastItem: ChatItem
        var lastSentAt: Date
        var pending: Task<Void, Never>?
    }

    struct MetaThrottle {
        var lastSentAt: Date
        var pending: Task<Void, Never>?
    }

    func startSubagentServices() {
        guard let subagents else { return }
        let events = subagents.events()
        subagentTasks.append(Task { [weak self] in
            for await event in events {
                await self?.subagentEvent(event)
            }
        })
        let updates = observedSessionUpdates
        subagentTasks.append(Task {
            for await sessions in updates {
                await subagents.observe(sessions: sessions)
            }
        })
    }

    func publishObservedSessions() {
        guard subagents != nil, !isShuttingDown else { return }
        var sessionIds = Set(TreeComposer.agents(in: baseTree).filter { $0.kind == TreeComposer.claudeKind }.compactMap(\.sessionId))
        for client in clients.values {
            for chat in client.chats.values {
                if let sessionId = chat.sessionId {
                    sessionIds.insert(sessionId)
                }
            }
        }
        guard sessionIds != observedSubagentSessions else { return }
        observedSubagentSessions = sessionIds
        subagentStates = subagentStates.filter { sessionIds.contains($0.value.sessionId) }
        workflowStates = workflowStates.filter { sessionIds.contains($0.value.sessionId) }
        runningSubagentCounts = runningSubagentCounts.filter { sessionIds.contains($0.key) }
        observedSessionContinuation.yield(sessionIds)
    }

    func listSubagents(_ agentId: AgentID, id: String, clientId: UUID) async {
        let resolved = await herdr.resolve(agentId)
        guard let agent = await herdr.agent(resolved) else {
            send(.agentNotFound, id: id, to: clientId)
            return
        }
        guard agent.kind == TreeComposer.claudeKind else {
            send(.notClaude, id: id, to: clientId)
            return
        }
        guard let sessionId = agent.sessionId, let subagents else {
            send(.subagentList(agentId: resolved, items: []), id: id, to: clientId)
            return
        }
        let items = await subagents.subagents(session: sessionId)
        send(.subagentList(agentId: resolved, items: items), id: id, to: clientId)
    }

    func resolveSubagentTranscript(sessionId: String, agentId: String, id: String, clientId: UUID) async -> SubagentTranscript? {
        guard UUID(uuidString: sessionId) != nil else {
            send(.invalidSessionId, id: id, to: clientId)
            return nil
        }
        guard SubagentFileName.isValidId(agentId) else {
            send(.invalidSubagentId, id: id, to: clientId)
            return nil
        }
        guard let transcript = await subagents?.transcript(session: sessionId, agentId: agentId) else {
            send(.subagentNotFound, id: id, to: clientId)
            return nil
        }
        return transcript
    }

    func overlaid(_ items: [ChatItem]) -> [ChatItem] {
        items.map(overlaid)
    }

    func overlaid(_ item: ChatItem) -> ChatItem {
        var copy = item
        switch item.kind {
        case .subagent(var call):
            let state = call.agentId.flatMap { subagentStates[$0] }
                ?? subagentStates.values.first { $0.toolUseId == call.toolUseId && $0.runId == nil }
            guard let state else { return item }
            call.agentId = call.agentId ?? state.agentId
            call.status = state.status
            call.activity = state.activity
            call.toolUses = state.toolUses
            call.startedAt = state.startedAt
            call.durationMs = state.durationMs
            call.failureReason = state.failureReason
            copy.kind = .subagent(call)
        case .workflow(var call):
            let state = call.runId.flatMap { workflowStates[$0] } ?? workflowStates.values.first { $0.toolUseId == call.toolUseId }
            guard let state else { return item }
            call.runId = call.runId ?? state.runId
            call.status = state.status
            call.phases = state.phases
            call.agentCount = state.agentCount
            call.toolUses = state.toolUses
            call.durationMs = state.durationMs
            copy.kind = .workflow(call)
        default:
            return item
        }
        return copy
    }

    func rememberCards(_ items: [ChatItem], token: UUID, clientId: UUID) {
        let cards = items.filter(Self.isCard)
        guard !cards.isEmpty else { return }
        let now = clock.now()
        updateChat(token, clientId: clientId) { chat in
            for card in cards {
                chat.cards[card.id] = card
            }
        }
        for card in cards {
            let key = Self.cardKey(clientId: clientId, token: token, itemId: card.id)
            cardThrottles[key]?.pending?.cancel()
            cardThrottles[key] = CardThrottle(clientId: clientId, token: token, itemId: card.id, lastItem: overlaid(card), lastSentAt: now)
        }
    }

    func forgetCards(token: UUID) {
        for (key, throttle) in cardThrottles where throttle.token == token {
            throttle.pending?.cancel()
            cardThrottles[key] = nil
        }
        metaThrottles[token]?.pending?.cancel()
        metaThrottles[token] = nil
    }

    func subagentChatMeta(sessionId: String, agentId: String, meta: TranscriptMeta?) -> ChatMeta {
        let parent = parentChatMeta(sessionId: sessionId)
        let state = subagentStates[agentId]
        let parentTitle = state?.parentAgentId.flatMap { subagentStates[$0]?.description } ?? parent.title
        let info = state.map {
            SubagentChatInfo(
                parentTitle: parentTitle,
                agentType: $0.agentType,
                status: $0.status,
                startedAt: $0.startedAt,
                durationMs: $0.durationMs,
                toolUses: $0.toolUses,
                failureReason: $0.failureReason
            )
        }
        return ChatMeta(
            title: state?.description ?? meta?.title ?? "Subagente",
            workspaceLabel: parent.workspaceLabel,
            model: meta?.model,
            branch: meta?.branch,
            status: .unknown,
            permissionMode: nil,
            subagent: info
        )
    }

    func shouldSendChatMeta(_ meta: ChatMeta, previous: ChatMeta, token: UUID) -> Bool {
        guard let info = meta.subagent else { return true }
        let now = clock.now()
        guard var throttle = metaThrottles[token] else {
            metaThrottles[token] = MetaThrottle(lastSentAt: now)
            return true
        }
        let elapsed = now.timeIntervalSince(throttle.lastSentAt)
        if info.status != previous.subagent?.status || elapsed >= Self.cardInterval {
            throttle.pending?.cancel()
            metaThrottles[token] = MetaThrottle(lastSentAt: now)
            return true
        }
        if throttle.pending == nil {
            throttle.pending = scheduleAfter(Self.cardInterval - elapsed) { hub in
                await hub.metaThrottleFired(token: token)
            }
            metaThrottles[token] = throttle
        }
        return false
    }

    private func metaThrottleFired(token: UUID) {
        metaThrottles[token]?.pending = nil
        metaThrottles[token]?.lastSentAt = .distantPast
        refreshChatMetas()
    }

    private func parentChatMeta(sessionId: String) -> ChatMeta {
        if let agent = TreeComposer.agents(in: baseTree).first(where: { $0.sessionId == sessionId }) {
            return TreeComposer.agentChatMeta(summary: composedSummary(agent), meta: metas[sessionId])
        }
        return TreeComposer.sessionChatMeta(meta: metas[sessionId], workspaceLabel: archivedWorkspaceLabel(forSession: sessionId))
    }

    private func subagentEvent(_ event: SubagentEvent) {
        switch event {
        case .subagent(let state):
            guard observedSubagentSessions.contains(state.sessionId) else { return }
            subagentStates[state.agentId] = state
            refreshCards { card in
                guard case .subagent(let call) = card.kind else { return false }
                return call.agentId == state.agentId || (call.agentId == nil && call.toolUseId == state.toolUseId)
            }
            refreshChatMetas()
        case .workflow(let state):
            guard observedSubagentSessions.contains(state.sessionId) else { return }
            workflowStates[state.runId] = state
            refreshCards { card in
                guard case .workflow(let call) = card.kind else { return false }
                return call.runId == state.runId || (call.runId == nil && call.toolUseId == state.toolUseId)
            }
        case .runningCount(let sessionId, let count):
            guard observedSubagentSessions.contains(sessionId), runningSubagentCounts[sessionId, default: 0] != count else { return }
            runningSubagentCounts[sessionId] = count
            updateLiveFollows()
            scheduleTreeFlush()
        }
    }

    private func refreshCards(where matches: (ChatItem) -> Bool) {
        for (clientId, client) in clients where client.isAuthenticated && !client.isClosing {
            for chat in client.chats.values {
                for card in chat.cards.values where matches(card) {
                    sendCard(card, token: chat.token, clientId: clientId)
                }
            }
        }
    }

    private func sendCard(_ original: ChatItem, token: UUID, clientId: UUID) {
        let key = Self.cardKey(clientId: clientId, token: token, itemId: original.id)
        let item = overlaid(original)
        let now = clock.now()
        guard var throttle = cardThrottles[key] else {
            cardThrottles[key] = CardThrottle(clientId: clientId, token: token, itemId: original.id, lastItem: item, lastSentAt: now)
            sendCardUpdate(item, token: token, clientId: clientId)
            return
        }
        guard throttle.lastItem != item else { return }
        let elapsed = now.timeIntervalSince(throttle.lastSentAt)
        if Self.cardStatus(item) != Self.cardStatus(throttle.lastItem) || elapsed >= Self.cardInterval {
            throttle.pending?.cancel()
            throttle.pending = nil
            throttle.lastItem = item
            throttle.lastSentAt = now
            cardThrottles[key] = throttle
            sendCardUpdate(item, token: token, clientId: clientId)
            return
        }
        guard throttle.pending == nil else { return }
        throttle.pending = scheduleAfter(Self.cardInterval - elapsed) { hub in
            await hub.cardThrottleFired(key: key)
        }
        cardThrottles[key] = throttle
    }

    private func cardThrottleFired(key: String) {
        guard var throttle = cardThrottles[key] else { return }
        throttle.pending = nil
        throttle.lastSentAt = .distantPast
        cardThrottles[key] = throttle
        guard let chat = clients[throttle.clientId]?.chats.values.first(where: { $0.token == throttle.token }),
              let card = chat.cards[throttle.itemId] else {
            return
        }
        sendCard(card, token: throttle.token, clientId: throttle.clientId)
    }

    private func sendCardUpdate(_ item: ChatItem, token: UUID, clientId: UUID) {
        guard let chat = clients[clientId]?.chats.values.first(where: { $0.token == token }) else { return }
        send(.chatUpdate(target: chat.target, items: [item]), to: clientId)
    }

    private func scheduleAfter(_ interval: TimeInterval, _ action: @escaping @Sendable (SessionHub) async -> Void) -> Task<Void, Never> {
        let clock = clock
        let delay = Duration.milliseconds(Int64(max(0, interval) * 1000))
        return Task { [weak self] in
            guard (try? await clock.sleep(for: delay)) != nil, let self else { return }
            await action(self)
        }
    }

    private static func cardKey(clientId: UUID, token: UUID, itemId: String) -> String {
        "\(clientId.uuidString)|\(token.uuidString)|\(itemId)"
    }

    private static func cardStatus(_ item: ChatItem) -> String? {
        switch item.kind {
        case .subagent(let call): call.status.rawValue
        case .workflow(let call): call.status.rawValue
        default: nil
        }
    }

    static func isCard(_ item: ChatItem) -> Bool {
        switch item.kind {
        case .subagent, .workflow: true
        default: false
        }
    }
}
