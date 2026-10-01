import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

struct CodexLiveReplay {
    struct Operation: Codable, Equatable {
        let op: String
        let threadId: String
        let id: String
    }

    struct Chat: Codable, Equatable {
        let threadId: String
        let items: [ChatItem]
    }

    struct TurnEnd: Codable, Equatable {
        let threadId: String
        let id: String
        let status: String
        let durationMs: Int?
    }

    static let now = Date(timeIntervalSince1970: 1_790_827_000)

    private(set) var states: [String: CodexThreadState] = [:]
    private(set) var events: [CodexThreadEvent] = []
    private(set) var operations: [Operation] = []
    private(set) var turnEnds: [TurnEnd] = []
    private var order: [String] = []
    private var chats: [String: [ChatItem]] = [:]

    init(resume: OrderedJSON) {
        var state = CodexThreadState(threadId: CodexSample.threadId)
        state.absorb(resume: resume)
        states[CodexSample.threadId] = state
        order = [CodexSample.threadId]
    }

    static func messages(_ name: String) throws -> [OrderedJSON] {
        let text = String(decoding: try Fixtures.data("codex/live/\(name).jsonl"), as: UTF8.self)
        return try text.split(separator: "\n").map { try OrderedJSON.parse(Data($0.utf8)) }
    }

    static func replaying(_ name: String) throws -> CodexLiveReplay {
        var replay = CodexLiveReplay(resume: try CodexSample.result("thread-resume.response.json"))
        for message in try messages(name) {
            replay.apply(message)
        }
        return replay
    }

    mutating func apply(_ message: OrderedJSON) {
        guard let method = message["method"]?.stringValue, let params = message["params"],
              let threadId = params["threadId"]?.stringValue else { return }
        var state = states[threadId] ?? CodexThreadState(threadId: threadId)
        let produced = state.apply(method, params, now: Self.now)
        states[threadId] = state
        events += produced
        for event in produced {
            switch event {
            case .item(let item):
                deliver(item.chatItems, threadId: threadId)
            case .turn(_, let turn, let chatItems):
                deliver(chatItems, threadId: threadId)
                if turn.status != .inProgress {
                    turnEnds.append(TurnEnd(threadId: threadId, id: turn.id, status: turn.status.rawValue, durationMs: turn.durationMs))
                }
            case .settings, .resubscribed:
                break
            }
        }
    }

    func chat(_ threadId: String) -> [ChatItem] {
        chats[threadId] ?? []
    }

    var allChats: [Chat] {
        order.filter { chats[$0] != nil }.map { Chat(threadId: $0, items: chats[$0] ?? []) }
    }

    private mutating func deliver(_ items: [ChatItem], threadId: String) {
        if !order.contains(threadId) { order.append(threadId) }
        var chat = chats[threadId] ?? []
        for item in items {
            if let index = chat.firstIndex(where: { $0.id == item.id }) {
                guard chat[index] != item else { continue }
                chat[index] = item
                operations.append(Operation(op: "update", threadId: threadId, id: item.id))
            } else {
                chat.append(item)
                operations.append(Operation(op: "append", threadId: threadId, id: item.id))
            }
        }
        chats[threadId] = chat
    }
}

private struct LiveSnapshot: Codable, Equatable {
    let operations: [CodexLiveReplay.Operation]
    let chats: [CodexLiveReplay.Chat]
    let turnEnds: [CodexLiveReplay.TurnEnd]
    let agent: AgentSummary
    let chatMeta: ChatMeta
}

private struct PageSnapshot: Codable, Equatable {
    let title: String
    let status: AgentStatus
    let activeTurnId: String?
    let before: String?
    let items: [ChatItem]
}

@Suite(.timeLimit(.minutes(1)))
struct CodexChatSnapshotTests {
    static let liveNames = ["basic-turn", "plan-turn", "command-turn", "compact-turn", "subagent-turn", "interrupted-turn"]

    private static var isUpdating: Bool {
        ProcessInfo.processInfo.environment["MOCHA_UPDATE_SNAPSHOTS"] == "1"
    }

    private static func expectedURL(_ name: String) -> URL {
        Fixtures.url("codex/expected/\(name).json")
    }

    private static func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    private static func compare<Value: Encodable>(_ produced: Value, name: String) throws {
        let data = try encoded(produced)
        if isUpdating {
            let url = expectedURL(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        let stored = try Data(contentsOf: expectedURL(name))
        #expect(String(decoding: data, as: UTF8.self) == String(decoding: stored, as: UTF8.self), "\(name) mudou; rode com MOCHA_UPDATE_SNAPSHOTS=1 e revise o diff")
    }

    static func agent(_ state: CodexThreadState?) -> AgentSummary {
        let base = AgentSummary(id: CodexSample.pane, kind: "codex", status: .idle, title: "codex", workspaceLabel: "work", branch: "main")
        let pane = state.map { CodexPaneState(threadId: $0.threadId, status: .idle, summary: $0.summary, settings: $0.settings) }
        return TreeComposer.codexSummary(base, pane: pane, connected: true)
    }

    @Test(arguments: liveNames)
    func liveFixtureMatchesExpectedSnapshot(_ name: String) throws {
        let replay = try CodexLiveReplay.replaying(name)
        let agent = Self.agent(replay.states[CodexSample.threadId])
        let snapshot = LiveSnapshot(
            operations: replay.operations,
            chats: replay.allChats,
            turnEnds: replay.turnEnds,
            agent: agent,
            chatMeta: TreeComposer.agentChatMeta(summary: agent, meta: nil)
        )
        try Self.compare(snapshot, name: name)
    }

    @Test func threadPageMatchesExpectedSnapshot() throws {
        let thread = try #require(try CodexSample.result("thread-read.response.json")["thread"])
        let listed = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-items-list.response.json"))["result"])
        let turnsResult = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-turns-list.response.json"))["result"])
        let turns = Dictionary(uniqueKeysWithValues: (turnsResult["data"]?.arrayValue ?? []).compactMap(CodexTurn.init).map { ($0.id, $0) })
        let page = try #require(CodexProjection.page(thread: thread, listed: listed, turns: turns, newerTurnId: nil))
        let snapshot = PageSnapshot(title: page.title, status: page.status, activeTurnId: page.activeTurnId, before: page.before, items: page.items)
        try Self.compare(snapshot, name: "thread-page")
    }

    @Test func everyStartedItemIsAppendedOnceAndOnlyUpdatedWhenItChanges() throws {
        for name in Self.liveNames {
            let replay = try CodexLiveReplay.replaying(name)
            let appended = replay.operations.filter { $0.op == "append" }.map { "\($0.threadId)/\($0.id)" }
            #expect(Set(appended).count == appended.count, "\(name) repetiu um append")
            let chatIds = replay.allChats.flatMap { chat in chat.items.map { "\(chat.threadId)/\($0.id)" } }
            #expect(Set(chatIds).count == chatIds.count, "\(name) duplicou um item")
        }
    }

    @Test func theLiveChatMatchesTheReloadedPageItemByItem() throws {
        let replay = try CodexLiveReplay.replaying("interrupted-turn")
        let thread = try #require(try CodexSample.result("thread-read.response.json")["thread"])
        let listed = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-items-list.response.json"))["result"])
        let turnsResult = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-turns-list.response.json"))["result"])
        let turns = Dictionary(uniqueKeysWithValues: (turnsResult["data"]?.arrayValue ?? []).compactMap(CodexTurn.init).map { ($0.id, $0) })
        let page = try #require(CodexProjection.page(thread: thread, listed: listed, turns: turns, newerTurnId: nil))
        let live = Dictionary(uniqueKeysWithValues: replay.chat(CodexSample.threadId).map { ($0.id, $0) })
        let shared = page.items.filter { live[$0.id] != nil }
        #expect(shared.count == 4)
        for item in shared {
            #expect(live[item.id] == item)
        }
    }
}
