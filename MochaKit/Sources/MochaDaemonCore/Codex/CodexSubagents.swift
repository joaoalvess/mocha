import Foundation
import MochaProtocol

struct CodexListedThread: Sendable, Equatable {
    let id: String
    let nickname: String?
    let name: String?
    let createdAt: Date?
    let updatedAt: Date?
    let status: SubagentStatus

    init?(_ raw: OrderedJSON) {
        guard let id = raw["id"]?.stringValue else { return nil }
        self.id = id
        nickname = CodexProjection.nonEmpty(raw["agentNickname"]?.stringValue)
        name = CodexProjection.agentName(path: CodexSubagents.spawnPath(of: raw))
        createdAt = CodexProjection.date(seconds: raw["createdAt"])
        updatedAt = CodexProjection.date(seconds: raw["updatedAt"])
        status = CodexSubagents.status(ofThread: raw["status"])
    }
}

struct CodexSubagent: Sendable, Equatable {
    let threadId: String
    let parentThreadId: String
    let rootThreadId: String
    var toolUseId: String
    var name: String
    var nickname: String?
    var status: SubagentStatus
    var activity: ToolActivity?
    var toolUses: Int
    var startedAt: Date?
    var durationMs: Int?
    var failureReason: String?
    var model: String?
    var branch: String?

    var agentType: String { nickname ?? name }
    var description: String { name }
    var isNested: Bool { parentThreadId != rootThreadId }

    var state: SubagentState {
        SubagentState(
            agentId: threadId,
            sessionId: rootThreadId,
            toolUseId: toolUseId,
            parentAgentId: isNested ? parentThreadId : nil,
            agentType: agentType,
            description: description,
            status: status,
            activity: activity,
            toolUses: toolUses,
            startedAt: startedAt,
            durationMs: durationMs,
            failureReason: failureReason
        )
    }

    func chatInfo(parentTitle: String) -> SubagentChatInfo {
        SubagentChatInfo(
            parentTitle: parentTitle,
            agentType: agentType,
            status: status,
            startedAt: startedAt,
            durationMs: durationMs,
            toolUses: toolUses,
            failureReason: failureReason
        )
    }

    func overlay(_ call: SubagentCall) -> SubagentCall {
        var call = call
        call.agentType = agentType
        if call.status == .running || status != .running {
            call.status = status
            call.durationMs = durationMs
            call.failureReason = failureReason
        }
        call.activity = call.status == .running ? activity : nil
        call.toolUses = toolUses
        call.startedAt = call.startedAt ?? startedAt
        return call
    }
}

struct CodexSubagentTree: Sendable, Equatable {
    let rootThreadId: String
    let subagents: [CodexSubagent]
}

enum CodexSubagents {
    static let maxDepth = 4
    static let defaultName = "subagente"
    static let failedTurnReason = "O turno falhou."

    static func tree(of root: String, threads: [String: CodexThreadState]) -> CodexSubagentTree {
        var subagents: [CodexSubagent] = []
        var visited: Set<String> = [root]
        var parents: [(threadId: String, depth: Int)] = [(root, 1)]
        while !parents.isEmpty {
            let (parent, depth) = parents.removeFirst()
            guard let state = threads[parent] else { continue }
            for child in Set(state.cards.keys).union(state.listedChildren.keys).sorted() where visited.insert(child).inserted {
                guard let subagent = subagent(child, parent: state, root: root, child: threads[child]) else { continue }
                subagents.append(subagent)
                if depth < maxDepth {
                    parents.append((child, depth + 1))
                }
            }
        }
        return CodexSubagentTree(rootThreadId: root, subagents: subagents)
    }

    static func listed(_ subagents: [CodexSubagent]) -> [SubagentSummary] {
        SubagentOrdering.listed(subagents.map(\.state))
    }

    static func children(_ result: OrderedJSON) -> [CodexListedThread] {
        (result["data"]?.arrayValue ?? []).compactMap(CodexListedThread.init)
    }

    static func read(_ thread: OrderedJSON) -> CodexSubagent? {
        guard let threadId = thread["id"]?.stringValue, let parent = thread["parentThreadId"]?.stringValue else { return nil }
        let turns = (thread["turns"]?.arrayValue ?? []).compactMap { raw in CodexTurn(raw).map { (turn: $0, items: raw["items"]?.arrayValue ?? []) } }
        let last = turns.last?.turn
        var status = turns.isEmpty ? status(ofThread: thread["status"]) : turnStatus(last?.status)
        var failureReason: String?
        if last?.status == .failed {
            status = .failed
            failureReason = CodexProjection.nonEmpty(last?.errorMessage) ?? failedTurnReason
        }
        let startedAt = turns.first?.turn.startedAt ?? CodexProjection.date(seconds: thread["createdAt"])
        let endedAt = last?.completedAt ?? CodexProjection.date(seconds: thread["updatedAt"])
        let durations = turns.compactMap(\.turn.durationMs)
        let measured = !turns.isEmpty && durations.count == turns.count ? durations.reduce(0, +) : duration(from: startedAt, to: endedAt)
        return CodexSubagent(
            threadId: threadId,
            parentThreadId: parent,
            rootThreadId: parent,
            toolUseId: threadId,
            name: CodexProjection.agentName(path: spawnPath(of: thread)) ?? defaultName,
            nickname: CodexProjection.nonEmpty(thread["agentNickname"]?.stringValue),
            status: status,
            toolUses: turns.flatMap(\.items).count(where: isToolCall),
            startedAt: startedAt,
            durationMs: status == .running ? nil : measured,
            failureReason: failureReason,
            model: thread["model"]?.stringValue,
            branch: thread["gitInfo"]?["branch"]?.stringValue
        )
    }

    static func spawnPath(of thread: OrderedJSON) -> String? {
        thread["source"]?["subAgent"]?["thread_spawn"]?["agent_path"]?.stringValue
    }

    static func status(ofThread status: OrderedJSON?) -> SubagentStatus {
        switch status?["type"]?.stringValue {
        case "active": .running
        case "systemError": .failed
        default: .completed
        }
    }

    private static func turnStatus(_ status: CodexTurnStatus?) -> SubagentStatus {
        switch status {
        case .inProgress: .running
        case .interrupted: .stopped
        case .failed: .failed
        case .completed, nil: .completed
        }
    }

    private static func subagent(_ threadId: String, parent: CodexThreadState, root: String, child: CodexThreadState?) -> CodexSubagent? {
        let card = parent.cards[threadId].flatMap { item -> SubagentCall? in
            guard case .subagent(let call) = item.kind else { return nil }
            return call
        }
        let listed = parent.listedChildren[threadId]
        guard card != nil || listed != nil else { return nil }
        let outcome = parent.outcomes[threadId]
        let startedAt = card?.startedAt ?? listed?.createdAt
        var status = outcome?.status ?? (card == nil ? listed?.status ?? .running : .running)
        var failureReason: String?
        if status != .running, let turn = child?.lastClosedTurn, turn.status == .failed {
            status = .failed
            failureReason = CodexProjection.nonEmpty(turn.errorMessage) ?? failedTurnReason
        }
        let endedAt = outcome?.at ?? (status == .running ? nil : listed?.updatedAt)
        return CodexSubagent(
            threadId: threadId,
            parentThreadId: parent.threadId,
            rootThreadId: root,
            toolUseId: card?.toolUseId ?? threadId,
            name: card?.description ?? listed?.name ?? defaultName,
            nickname: listed?.nickname,
            status: status,
            activity: status == .running ? child?.summary.activity : nil,
            toolUses: child?.toolUses ?? 0,
            startedAt: startedAt,
            durationMs: duration(from: startedAt, to: endedAt),
            failureReason: failureReason,
            model: child?.settings.model,
            branch: child?.summary.branch
        )
    }

    private static func isToolCall(_ item: OrderedJSON) -> Bool {
        guard case .toolCall = CodexProjection.item(item, at: Date(timeIntervalSince1970: 0), isCompleted: true, cwd: nil)?.kind else { return false }
        return true
    }

    private static func duration(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }
}
