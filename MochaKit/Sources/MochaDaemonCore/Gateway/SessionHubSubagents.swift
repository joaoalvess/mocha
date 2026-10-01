import Foundation
import MochaProtocol

extension SessionHub {
    static let cardInterval: TimeInterval = 1
    static let codexSubagentCacheLimit = 64

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
        pruneCodexSubagents()
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
        let codexRoots = Set(codexPanes.values.map(\.threadId))
        runningSubagentCounts = runningSubagentCounts.filter { sessionIds.contains($0.key) || codexRoots.contains($0.key) }
        observedSessionContinuation.yield(sessionIds)
    }

    func listSubagents(_ agentId: AgentID, id: String, clientId: UUID) async {
        let resolved = await herdr.resolve(agentId)
        guard let agent = await herdr.agent(resolved) else {
            send(.agentNotFound, id: id, to: clientId)
            return
        }
        if agent.kind == TreeComposer.codexKind {
            await listCodexSubagents(resolved, id: id, clientId: clientId)
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
        if !copy.imagePaths.isEmpty {
            copy.imagePaths = ImageFiles.existing(copy.imagePaths)
        }
        switch item.kind {
        case .subagent(var call):
            if let subagent = call.agentId.flatMap({ codexSubagents[$0] }) {
                copy.kind = .subagent(subagent.overlay(call))
                return copy
            }
            let state = call.agentId.flatMap { subagentStates[$0] }
                ?? subagentStates.values.first { $0.toolUseId == call.toolUseId && $0.runId == nil }
            guard let state else { return copy }
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
            guard let state else { return copy }
            call.runId = call.runId ?? state.runId
            call.status = state.status
            call.phases = state.phases
            call.agentCount = state.agentCount
            call.toolUses = state.toolUses
            call.durationMs = state.durationMs
            copy.kind = .workflow(call)
        default:
            return copy
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
              let card = chat.cards[throttle.itemId] ?? chat.codexItems[throttle.itemId] else {
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

    func codexSubagentEvent(_ event: CodexThreadEvent) async {
        guard let codex else { return }
        switch event {
        case .resubscribed(let threadId):
            Task { [weak self] in
                await codex.refreshSubagents(of: threadId, inferOutcomes: true)
                await self?.refreshCodexSubagents(around: threadId)
            }
        case .item(let item):
            guard item.item["type"]?.stringValue == "subAgentActivity" || codexSubagents[item.threadId] != nil else { return }
            await refreshCodexSubagents(around: item.threadId, delivered: item.chatItems)
        case .turn(let threadId, _, let chatItems):
            guard codexSubagents[threadId] != nil else { return }
            await refreshCodexSubagents(around: threadId, delivered: chatItems)
        case .settings:
            break
        }
    }

    func prepareCodexThreadChat(_ threadId: String) async {
        guard let codex, codexSubagents[threadId] == nil,
              !codexPanes.values.contains(where: { $0.threadId == threadId }),
              !archivedSessions.contains(where: { $0.id == threadId }),
              let subagent = await codex.subagent(threadId),
              codexSubagents[threadId] == nil else { return }
        codexSubagents[threadId] = subagent
    }

    func codexThreadChatMeta(_ threadId: String) -> ChatMeta {
        guard let subagent = codexSubagents[threadId] else { return codexRootChatMeta(threadId) }
        let root = codexRootChatMeta(subagent.rootThreadId)
        let parentTitle = subagent.isNested ? codexSubagents[subagent.parentThreadId]?.description ?? root.title : root.title
        return ChatMeta(
            title: subagent.description,
            workspaceLabel: root.workspaceLabel,
            model: subagent.model ?? root.model,
            branch: subagent.branch ?? root.branch,
            status: .unknown,
            subagent: subagent.chatInfo(parentTitle: parentTitle)
        )
    }

    private func listCodexSubagents(_ agentId: AgentID, id: String, clientId: UUID) async {
        guard let codex, codexConnected, let pane = codexPanes[agentId] else {
            send(.codexUnavailable, id: id, to: clientId)
            return
        }
        let subagents = await codex.subagentTree(containing: pane.threadId)?.subagents ?? []
        send(.subagentList(agentId: agentId, items: CodexSubagents.listed(subagents)), id: id, to: clientId)
    }

    private func refreshCodexSubagents(around threadId: String, delivered: [ChatItem] = []) async {
        guard let codex, let tree = await codex.subagentTree(containing: threadId) else { return }
        let root = tree.rootThreadId
        let previous = codexSubagents.filter { $0.value.rootThreadId == root }
        var fresh: [String: CodexSubagent] = [:]
        for subagent in tree.subagents {
            fresh[subagent.threadId] = subagent
        }
        for id in previous.keys where fresh[id] == nil {
            codexSubagents[id] = nil
        }
        codexSubagents.merge(fresh) { _, new in new }
        let running = tree.subagents.count { $0.status == .running }
        if runningSubagentCounts[root, default: 0] != running {
            runningSubagentCounts[root] = running > 0 ? running : nil
            scheduleTreeFlush()
        }
        let changed = tree.subagents.filter { previous[$0.threadId] != $0 }
        guard !changed.isEmpty else { return }
        refreshCodexCards(Set(changed.map(\.threadId)), delivered: delivered, deliveredThreadId: threadId)
        refreshChatMetas()
        let unnamed = changed.filter { $0.nickname == nil && previous[$0.threadId]?.status != $0.status }
        for parent in Set(unnamed.map(\.parentThreadId)).sorted() {
            Task { [weak self] in
                await codex.refreshSubagents(of: parent, inferOutcomes: false)
                await self?.refreshCodexSubagents(around: root)
            }
        }
    }

    private func refreshCodexCards(_ children: Set<String>, delivered: [ChatItem], deliveredThreadId: String) {
        var deliveredCards: [String: ChatItem] = [:]
        for item in delivered where Self.isCard(item) {
            deliveredCards[item.id] = item
        }
        let now = clock.now()
        for (clientId, client) in clients where client.isAuthenticated && !client.isClosing {
            for chat in client.chats.values where chat.codexThreadId != nil {
                for card in chat.codexItems.values {
                    guard case .subagent(let call) = card.kind, let child = call.agentId, children.contains(child) else { continue }
                    guard chat.codexThreadId == deliveredThreadId, let fresh = deliveredCards[card.id] else {
                        sendCard(card, token: chat.token, clientId: clientId)
                        continue
                    }
                    let key = Self.cardKey(clientId: clientId, token: chat.token, itemId: card.id)
                    cardThrottles[key]?.pending?.cancel()
                    cardThrottles[key] = CardThrottle(clientId: clientId, token: chat.token, itemId: card.id, lastItem: overlaid(fresh), lastSentAt: now)
                }
            }
        }
    }

    private func codexRootChatMeta(_ threadId: String) -> ChatMeta {
        if let agentId = codexPanes.first(where: { $0.value.threadId == threadId })?.key, let summary = composedAgent(agentId) {
            return TreeComposer.agentChatMeta(summary: summary, meta: nil)
        }
        if let archived = archivedSessions.first(where: { $0.id == threadId }) {
            return ChatMeta(
                title: archived.title,
                workspaceLabel: archived.workspaceLabel,
                model: archived.model,
                branch: archived.branch,
                status: .unknown
            )
        }
        return ChatMeta(title: "Codex", workspaceLabel: "", status: .unknown)
    }

    private func pruneCodexSubagents() {
        let roots = Set(codexPanes.values.map(\.threadId))
        let open = Set(clients.values.flatMap { $0.chats.values.compactMap(\.codexThreadId) })
        let stale = codexSubagents.filter { !roots.contains($0.value.rootThreadId) && !open.contains($0.key) }
        for root in Set(stale.values.map(\.rootThreadId)) {
            runningSubagentCounts[root] = nil
        }
        guard stale.count > Self.codexSubagentCacheLimit else { return }
        for id in stale.keys {
            codexSubagents[id] = nil
        }
    }
}
