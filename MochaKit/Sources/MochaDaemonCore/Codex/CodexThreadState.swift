import Foundation
import MochaProtocol
import Synchronization

enum CodexTurnStatus: String, Sendable, Equatable {
    case inProgress
    case completed
    case interrupted
    case failed
}

struct CodexTurn: Sendable, Equatable {
    let id: String
    let status: CodexTurnStatus
    let startedAt: Date?
    let completedAt: Date?
    let durationMs: Int?
    let errorMessage: String?

    init(id: String, status: CodexTurnStatus, startedAt: Date? = nil, completedAt: Date? = nil, durationMs: Int? = nil, errorMessage: String? = nil) {
        self.id = id
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.errorMessage = errorMessage
    }

    init?(_ raw: OrderedJSON) {
        guard let id = raw["id"]?.stringValue,
              let status = raw["status"]?.stringValue.flatMap(CodexTurnStatus.init(rawValue:)) else { return nil }
        self.init(
            id: id,
            status: status,
            startedAt: CodexProjection.date(seconds: raw["startedAt"]),
            completedAt: CodexProjection.date(seconds: raw["completedAt"]),
            durationMs: raw["durationMs"]?.intValue,
            errorMessage: raw["error"]?["message"]?.stringValue
        )
    }
}

struct CodexThreadSettings: Sendable, Equatable {
    var model: String?
    var effort: String?
    var mode: String?

    init(model: String? = nil, effort: String? = nil, mode: String? = nil) {
        self.model = model
        self.effort = effort
        self.mode = mode
    }
}

struct CodexAccount: Sendable, Equatable {
    let plan: String?
    let email: String?
}

struct CodexSubagentOutcome: Sendable, Equatable {
    let status: SubagentStatus
    let at: Date
}

struct CodexThreadSummary: Sendable, Equatable {
    var name: String?
    var threadPreview: String?
    var branch: String?
    var preview: MessagePreview?
    var prompt: String?
    var activity: ToolActivity?
    var sessionStartedAt: Date?
    var turnStartedAt: Date?
    var turnEndedAt: Date?
    var lastActivityAt: Date?
    var contextLeftPercent: Int?
    var contextUsedTokens: Int?

    var title: String? { CodexProjection.nonEmpty(name) ?? CodexProjection.nonEmpty(threadPreview) }
}

struct CodexItemEvent: Sendable, Equatable {
    let threadId: String
    let turnId: String?
    let item: OrderedJSON
    let at: Date
    let isCompleted: Bool
    let chatItems: [ChatItem]
}

enum CodexThreadEvent: Sendable, Equatable {
    case item(CodexItemEvent)
    case turn(threadId: String, turn: CodexTurn, chatItems: [ChatItem])
    case settings(threadId: String, settings: CodexThreadSettings)
    case resubscribed(threadId: String)

    var threadId: String {
        switch self {
        case .item(let event): event.threadId
        case .turn(let threadId, _, _), .settings(let threadId, _), .resubscribed(let threadId): threadId
        }
    }
}

final class CodexThreadEventHub: Sendable {
    private let subscribers = Mutex<[UUID: AsyncStream<CodexThreadEvent>.Continuation]>([:])

    func events() -> AsyncStream<CodexThreadEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CodexThreadEvent.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        subscribers.withLock { $0[id] = continuation }
        return stream
    }

    func publish(_ event: CodexThreadEvent) {
        subscribers.withLock { subscribers in
            for continuation in subscribers.values {
                continuation.yield(event)
            }
        }
    }

    func finish() {
        let continuations = subscribers.withLock { subscribers in
            defer { subscribers.removeAll() }
            return Array(subscribers.values)
        }
        for continuation in continuations {
            continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        _ = subscribers.withLock { $0.removeValue(forKey: id) }
    }
}

struct CodexThreadState: Sendable {
    static let liveMethods: Set<String> = [
        "item/started", "item/completed", "turn/started", "turn/completed",
        "thread/settings/updated", "thread/tokenUsage/updated", "thread/name/updated",
    ]
    static let closedTurnsLimit = 200

    let threadId: String
    private(set) var cwd: String?
    private(set) var summary = CodexThreadSummary()
    private(set) var settings = CodexThreadSettings()
    private(set) var activeTurnId: String?
    private(set) var lastAgentMessage: String?
    private(set) var cards: [String: ChatItem] = [:]
    private(set) var outcomes: [String: CodexSubagentOutcome] = [:]
    private(set) var closedTurns: [String: CodexTurn] = [:]
    private var closedOrder: [String] = []
    private var itemStarts: [String: Date] = [:]
    private var turnItemTimes: [String: Date] = [:]
    private var runningTools: [String] = []
    private var lastToolId: String?
    private var tools: [String: ToolActivity] = [:]
    private var sawLiveEvent = false

    init(threadId: String) {
        self.threadId = threadId
    }

    mutating func absorb(thread: OrderedJSON) {
        if let cwd = thread["cwd"]?.stringValue { self.cwd = cwd }
        if let name = thread["name"] { summary.name = name.stringValue }
        if let preview = thread["preview"]?.stringValue { summary.threadPreview = preview }
        if let branch = thread["gitInfo"]?["branch"]?.stringValue { summary.branch = branch }
        if let createdAt = CodexProjection.date(seconds: thread["createdAt"]) { summary.sessionStartedAt = createdAt }
        if summary.lastActivityAt == nil { summary.lastActivityAt = CodexProjection.date(seconds: thread["updatedAt"]) }
        if settings.model == nil { settings.model = thread["model"]?.stringValue }
        if settings.effort == nil { settings.effort = thread["reasoningEffort"]?.stringValue }
    }

    mutating func absorb(resume result: OrderedJSON) {
        sawLiveEvent = false
        if let thread = result["thread"] { absorb(thread: thread) }
        settings = CodexProjection.settings(result, fallback: settings)
    }

    mutating func absorb(page: CodexThreadPage) {
        for (child, card) in page.cards where cards[child] == nil {
            cards[child] = card
        }
        for (child, outcome) in page.outcomes where outcomes[child] == nil {
            outcomes[child] = outcome
        }
    }

    mutating func hydrate(turns: [CodexTurn], entries: [CodexItemEntry]) {
        let overwrite = !sawLiveEvent
        if let turn = turns.first {
            if overwrite || summary.turnStartedAt == nil {
                summary.turnStartedAt = turn.startedAt
                summary.turnEndedAt = turn.status == .inProgress ? nil : turn.completedAt
            }
            if turn.status == .inProgress, activeTurnId == nil {
                activeTurnId = turn.id
            }
        }
        for turn in turns where turn.status != .inProgress {
            remember(turn)
        }
        var preview: MessagePreview?
        var prompt: String?
        var agentMessage: String?
        var tool: (id: String, activity: ToolActivity)?
        var latest: Date?
        for entry in entries {
            if let startedAt = entry.startedAt { latest = max(latest ?? startedAt, startedAt) }
            let at = entry.startedAt ?? Date(timeIntervalSince1970: 0)
            if let found = CodexProjection.subagentOutcome(entry.item), outcomes[found.child] == nil {
                outcomes[found.child] = CodexSubagentOutcome(status: found.status, at: at)
            }
            if let card = CodexProjection.subagentCard(entry.item, at: at, status: nil),
               let child = CodexProjection.subagentChild(card), cards[child] == nil {
                cards[child] = outcomes[child].map { CodexProjection.withOutcome(card, $0) } ?? card
            }
            guard let item = CodexProjection.item(entry.item, at: at, isCompleted: entry.isCompleted, cwd: cwd) else { continue }
            if preview == nil { preview = CodexProjection.preview(of: item) }
            if prompt == nil, case .userPrompt = item.kind { prompt = CodexProjection.preview(of: item)?.text }
            if agentMessage == nil, case .assistantText(let markdown) = item.kind { agentMessage = markdown }
            if tool == nil, let activity = CodexProjection.activity(of: item) { tool = (item.id, activity) }
        }
        if overwrite || summary.preview == nil { summary.preview = preview ?? summary.preview }
        if overwrite || summary.prompt == nil { summary.prompt = prompt ?? summary.prompt }
        if overwrite || lastAgentMessage == nil { lastAgentMessage = agentMessage ?? lastAgentMessage }
        if let tool, overwrite || lastToolId == nil {
            lastToolId = tool.id
            tools[tool.id] = tool.activity
            pruneTools()
        }
        if let latest, latest > summary.lastActivityAt ?? .distantPast { summary.lastActivityAt = latest }
        refreshActivity()
    }

    mutating func suspend() {
        activeTurnId = nil
        itemStarts.removeAll()
        turnItemTimes.removeAll()
        runningTools.removeAll()
        pruneTools()
        refreshActivity()
    }

    mutating func apply(_ method: String, _ params: OrderedJSON, now: Date) -> [CodexThreadEvent] {
        sawLiveEvent = true
        switch method {
        case "item/started":
            return item(params, isCompleted: false, now: now)
        case "item/completed":
            return item(params, isCompleted: true, now: now)
        case "turn/started":
            guard let turn = params["turn"].flatMap(CodexTurn.init) else { return [] }
            let startedAt = turn.startedAt ?? now
            activeTurnId = turn.id
            summary.turnStartedAt = startedAt
            summary.turnEndedAt = nil
            summary.lastActivityAt = max(summary.lastActivityAt ?? startedAt, startedAt)
            return [.turn(threadId: threadId, turn: turn, chatItems: [])]
        case "turn/completed":
            guard let turn = params["turn"].flatMap(CodexTurn.init) else { return [] }
            activeTurnId = nil
            let endedAt = turn.completedAt ?? now
            summary.turnStartedAt = turn.startedAt ?? summary.turnStartedAt
            summary.turnEndedAt = endedAt
            summary.lastActivityAt = max(summary.lastActivityAt ?? endedAt, endedAt)
            runningTools.removeAll()
            pruneTools()
            refreshActivity()
            remember(turn)
            let closing = CodexProjection.closingItem(turn, after: turnItemTimes.removeValue(forKey: turn.id), fallback: endedAt)
            return [.turn(threadId: threadId, turn: turn, chatItems: closing.map { [$0] } ?? [])]
        case "thread/settings/updated":
            let updated = CodexProjection.settings(params["threadSettings"], fallback: settings)
            guard updated != settings else { return [] }
            settings = updated
            return [.settings(threadId: threadId, settings: updated)]
        case "thread/tokenUsage/updated":
            let usage = params["tokenUsage"]
            guard let last = usage?["last"]?["totalTokens"]?.intValue else { return [] }
            summary.contextUsedTokens = last
            if let window = usage?["modelContextWindow"]?.intValue {
                summary.contextLeftPercent = CodexProjection.contextLeftPercent(lastTokens: last, window: window)
            }
            return []
        case "thread/name/updated":
            summary.name = params["threadName"]?.stringValue
            return []
        default:
            return []
        }
    }

    private mutating func item(_ params: OrderedJSON, isCompleted: Bool, now: Date) -> [CodexThreadEvent] {
        guard let raw = params["item"], let id = raw["id"]?.stringValue else { return [] }
        let turnId = params["turnId"]?.stringValue
        let eventAt: Date
        let at: Date
        if isCompleted {
            eventAt = CodexProjection.date(milliseconds: params["completedAtMs"]) ?? now
            at = itemStarts.removeValue(forKey: id) ?? eventAt
        } else {
            eventAt = CodexProjection.date(milliseconds: params["startedAtMs"]) ?? now
            at = itemStarts[id] ?? eventAt
            itemStarts[id] = at
        }
        summary.lastActivityAt = max(summary.lastActivityAt ?? eventAt, eventAt)
        if let turnId, closedTurns[turnId] == nil {
            turnItemTimes[turnId] = max(turnItemTimes[turnId] ?? at, at)
        }
        if let turnId, activeTurnId != turnId, closedTurns[turnId] == nil {
            activeTurnId = turnId
            if summary.turnStartedAt == nil || summary.turnEndedAt != nil {
                summary.turnStartedAt = eventAt
                summary.turnEndedAt = nil
            }
        }
        var chatItems: [ChatItem] = []
        if let card = CodexProjection.subagentCard(raw, at: at, status: nil), let child = CodexProjection.subagentChild(card) {
            let projected = outcomes[child].map { CodexProjection.withOutcome(card, $0) } ?? card
            cards[child] = projected
            chatItems = [projected]
        } else if let found = CodexProjection.subagentOutcome(raw) {
            let outcome = outcomes[found.child] ?? CodexSubagentOutcome(status: found.status, at: at)
            outcomes[found.child] = outcome
            if let card = cards[found.child] {
                let updated = CodexProjection.withOutcome(card, outcome)
                cards[found.child] = updated
                chatItems = [updated]
            }
        } else if let projected = CodexProjection.item(raw, at: at, isCompleted: isCompleted, cwd: cwd) {
            chatItems = [projected]
            track(projected, isCompleted: isCompleted)
        }
        return [.item(CodexItemEvent(threadId: threadId, turnId: turnId, item: raw, at: at, isCompleted: isCompleted, chatItems: chatItems))]
    }

    private mutating func track(_ item: ChatItem, isCompleted: Bool) {
        switch item.kind {
        case .userPrompt:
            if let preview = CodexProjection.preview(of: item) {
                summary.preview = preview
                summary.prompt = preview.text
            }
        case .assistantText(let markdown):
            if let preview = CodexProjection.preview(of: item) { summary.preview = preview }
            if isCompleted { lastAgentMessage = markdown }
        case .toolCall:
            guard let activity = CodexProjection.activity(of: item) else { return }
            tools[item.id] = activity
            if isCompleted {
                runningTools.removeAll { $0 == item.id }
            } else if !runningTools.contains(item.id) {
                runningTools.append(item.id)
                lastToolId = item.id
                toolUses += 1
            }
            if lastToolId == nil { lastToolId = item.id }
            pruneTools()
            refreshActivity()
        default:
            break
        }
    }

    private mutating func remember(_ turn: CodexTurn) {
        guard turn.status != .inProgress else { return }
        if closedTurns[turn.id] == nil { closedOrder.append(turn.id) }
        closedTurns[turn.id] = turn
        while closedOrder.count > Self.closedTurnsLimit {
            closedTurns[closedOrder.removeFirst()] = nil
        }
    }

    private mutating func pruneTools() {
        let keep = Set(runningTools + [lastToolId].compactMap { $0 })
        tools = tools.filter { keep.contains($0.key) }
    }

    private mutating func refreshActivity() {
        summary.activity = (runningTools.last ?? lastToolId).flatMap { tools[$0] }
    }

    private(set) var toolUses = 0
    private(set) var listedChildren: [String: CodexListedThread] = [:]

    var lastClosedTurn: CodexTurn? {
        closedTurns.values.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    mutating func absorb(children: [CodexListedThread], inferOutcomes: Bool) {
        for child in children {
            listedChildren[child.id] = child
            guard inferOutcomes, child.status != .running, outcomes[child.id] == nil,
                  let at = child.updatedAt ?? child.createdAt else { continue }
            let outcome = CodexSubagentOutcome(status: child.status, at: at)
            outcomes[child.id] = outcome
            if let card = cards[child.id] {
                cards[child.id] = CodexProjection.withOutcome(card, outcome)
            }
        }
    }
}
