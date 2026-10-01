import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

enum CodexSample {
    static let threadId = "01a0f59e-6845-7403-880c-44a4e20672d1"
    static let otherThreadId = "01a0f5a2-8cf1-7591-b15c-8c2d987573a1"
    static let thirdThreadId = "01a0f5a5-e823-71f0-bfc5-668f58f7c511"
    static let cwd = "/Users/dev/Developer/mocha-lab/S9/work"
    static let otherCwd = "/Users/dev/Developer/outro"
    static let pane = "w1:p2"

    static func message(_ name: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Fixtures.data("codex/events/\(name)"))
    }

    static func params(_ name: String) throws -> OrderedJSON {
        try #require(try message(name)["params"])
    }

    static func result(_ name: String) throws -> OrderedJSON {
        try #require(try message(name)["result"])
    }

    static func thread(_ id: String, cwd: String = cwd, ephemeral: Bool = false, parent: String? = nil, at date: Date = Date()) -> OrderedJSON {
        .object([
            .init("id", .string(id)),
            .init("cwd", .string(cwd)),
            .init("ephemeral", .bool(ephemeral)),
            .init("parentThreadId", parent.map(OrderedJSON.string) ?? .null),
            .init("status", .object([.init("type", .string("idle"))])),
            .init("createdAt", .number(String(Int(date.timeIntervalSince1970)))),
            .init("name", .null),
        ])
    }

    static func started(_ thread: OrderedJSON) -> OrderedJSON {
        .object([.init("thread", thread)])
    }

    static func readReply(_ threads: [String: OrderedJSON]) -> @Sendable (FakeCodexRequest) -> FakeCodexReply {
        { request in
            guard let id = request.string("threadId"), let thread = threads[id] else {
                return .error(code: -32600, message: "thread not found")
            }
            return .result(.object([.init("thread", thread)]))
        }
    }

    static func loaded(_ ids: [String]) -> FakeCodexReply {
        .result(.object([.init("data", .array(ids.map(OrderedJSON.string))), .init("nextCursor", .null)]))
    }

    static func setting(_ params: OrderedJSON, _ changes: [String: OrderedJSON]) -> OrderedJSON {
        changes.reduce(params) { $0.setting($1.key, to: $1.value) }
    }

    static func nowMs(_ offset: TimeInterval = 0) -> OrderedJSON {
        .number(String(Int((Date().timeIntervalSince1970 + offset) * 1000)))
    }

    static func bindings(_ entries: [AgentID: (String, String)], in directory: URL) throws {
        let bindings = entries.mapValues { CodexPaneBinding(threadId: $0.0, cwd: $0.1) }
        try JSONEncoder().encode(bindings).write(to: directory.appending(path: CodexPaneBindingStore.fileName))
    }

    static func savedBindings(in directory: URL) -> [AgentID: CodexPaneBinding] {
        CodexPaneBindingStore(url: directory.appending(path: CodexPaneBindingStore.fileName)).load()
    }
}

final class CodexUpdateRecorder: Sendable {
    private let updates = Mutex<[CodexServiceUpdate]>([])

    func record(_ update: CodexServiceUpdate) {
        updates.withLock { $0.append(update) }
    }

    var alerts: [CodexAlert] {
        updates.withLock { $0.compactMap { if case .alert(let alert) = $0 { alert } else { nil } } }
    }

    var panes: [AgentID: CodexPaneState] {
        updates.withLock { $0.last { if case .panes = $0 { true } else { false } } }.flatMap { if case .panes(let panes) = $0 { panes } else { nil } } ?? [:]
    }

    var pending: [PendingRequest] {
        updates.withLock { $0.last { if case .pending = $0 { true } else { false } } }.flatMap { if case .pending(let requests) = $0 { requests } else { nil } } ?? []
    }

    var decisions: [AgentID: PendingDecision] {
        updates.withLock { $0.last { if case .decisions = $0 { true } else { false } } }.flatMap { if case .decisions(let decisions) = $0 { decisions } else { nil } } ?? [:]
    }

    var usages: [UsageSnapshot] {
        updates.withLock { $0.compactMap { if case .usage(let snapshot) = $0 { snapshot } else { nil } } }
    }

    var availability: [Bool] {
        updates.withLock { $0.compactMap { if case .availability(let connected) = $0 { connected } else { nil } } }
    }
}

struct CodexServiceHarness {
    let server: FakeCodexAppServer
    let directory: URL

    func makeService() -> CodexService {
        CodexService(
            socketPath: server.socketPath,
            uploadsDirectory: directory.appending(path: "uploads", directoryHint: .isDirectory),
            retryInterval: .milliseconds(50)
        )
    }

    func start(_ service: CodexService) async -> CodexUpdateRecorder {
        let recorder = CodexUpdateRecorder()
        let updates = service.updates
        Task {
            for await update in updates {
                recorder.record(update)
            }
        }
        await service.start()
        return recorder
    }

    func resumes(of threadId: String) async -> Int {
        await server.requests(method: "thread/resume").count { $0.string("threadId") == threadId }
    }

    func waitForResume(of threadId: String, count: Int = 1) async throws {
        _ = try await eventually { await resumes(of: threadId) >= count ? true : nil }
    }

    func bind(_ service: CodexService, pane: AgentID = CodexSample.pane, thread threadId: String = CodexSample.threadId, cwd: String = CodexSample.cwd) async throws {
        try await connected()
        await service.expectPane(pane, cwd: cwd, since: Date().addingTimeInterval(-2))
        await server.notify("thread/started", params: CodexSample.started(CodexSample.thread(threadId, cwd: cwd)))
        _ = try await eventually { await service.threadId(for: pane) == threadId ? true : nil }
        try await waitForResume(of: threadId)
    }

    func connected() async throws {
        _ = try await eventually { await server.openConnections > 0 ? true : nil }
        _ = try await eventually { await server.requests(method: "initialize").isEmpty ? nil : true }
    }
}

func withCodexServer(_ body: (CodexServiceHarness) async throws -> Void) async throws {
    let directory = try FakeCodexAppServer.temporaryDirectory()
    let server = FakeCodexAppServer(socketPath: directory.appending(path: "codex.sock").path(percentEncoded: false))
    try await server.start()
    let harness = CodexServiceHarness(server: server, directory: directory)
    do {
        try await body(harness)
    } catch {
        await server.stop()
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    await server.stop()
    try? FileManager.default.removeItem(at: directory)
}
