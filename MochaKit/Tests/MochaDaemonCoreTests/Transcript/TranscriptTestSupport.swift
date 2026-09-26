import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Synchronization
import Testing
@testable import MochaDaemonCore

final class TranscriptSandbox {
    let root: URL

    init() throws {
        root = URL.temporaryDirectory.appending(path: "mocha-projects-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var rootPath: String {
        root.path(percentEncoded: false)
    }

    func projectURL(_ name: String = "-Users-dev-projects-demo-app") -> URL {
        root.appending(path: name, directoryHint: .isDirectory)
    }

    func sessionURL(_ sessionId: String, project: String = "-Users-dev-projects-demo-app") -> URL {
        projectURL(project).appending(path: "\(sessionId).jsonl")
    }

    @discardableResult
    func write(_ bytes: some Collection<UInt8>, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        return url
    }

    func append(_ bytes: some Collection<UInt8>, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(bytes))
    }

    func append(line: String, to url: URL) throws {
        try append(Array((line + "\n").utf8), to: url)
    }
}

enum SampleLines {
    static func user(_ text: String, uuid: String) -> String {
        json([
            "type": "user",
            "uuid": uuid,
            "timestamp": "2026-09-26T10:00:00.000Z",
            "message": ["role": "user", "content": text],
            "version": "2.1.283",
        ])
    }

    static func assistantText(_ text: String, uuid: String) -> String {
        json([
            "type": "assistant",
            "uuid": uuid,
            "timestamp": "2026-09-26T10:00:01.000Z",
            "message": ["model": "claude-opus-5-5", "content": [["type": "text", "text": text]]],
            "gitBranch": "main",
            "version": "2.1.283",
        ])
    }

    static func toolUse(id: String, uuid: String) -> String {
        json([
            "type": "assistant",
            "uuid": uuid,
            "timestamp": "2026-09-26T10:00:02.000Z",
            "message": ["model": "claude-opus-5-5", "content": [["type": "tool_use", "id": id, "name": "Bash", "input": ["command": "ls"]]]],
            "gitBranch": "main",
            "version": "2.1.283",
        ])
    }

    static func toolResult(id: String, uuid: String) -> String {
        json([
            "type": "user",
            "uuid": uuid,
            "timestamp": "2026-09-26T10:00:03.000Z",
            "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": "ok"]]],
            "version": "2.1.283",
        ])
    }

    static func title(_ title: String) -> String {
        json(["type": "ai-title", "aiTitle": title])
    }

    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

actor TranscriptDeltaRecorder {
    private(set) var list: ChatItemList
    private(set) var meta: TranscriptMeta
    private(set) var deltas: [TranscriptDelta] = []
    private(set) var problems: [String] = []
    private(set) var isFinished = false
    private var consumer: Task<Void, Never>?

    private init(page: TranscriptPage) {
        list = ChatItemList(page.items)
        meta = page.meta
    }

    static func start(_ subscription: TranscriptSubscription) async -> TranscriptDeltaRecorder {
        let recorder = TranscriptDeltaRecorder(page: subscription.page)
        await recorder.consume(subscription.deltas)
        return recorder
    }

    private func consume(_ stream: AsyncStream<TranscriptDelta>) {
        consumer = Task { [weak self] in
            for await delta in stream {
                await self?.record(delta)
            }
            await self?.markFinished()
        }
    }

    var items: [ChatItem] {
        list.items
    }

    var updateCount: Int {
        deltas.count { if case .update = $0 { true } else { false } }
    }

    private func record(_ delta: TranscriptDelta) {
        deltas.append(delta)
        switch delta {
        case .append(let items):
            for item in items {
                if list.contains(id: item.id) { problems.append("append duplicado: \(item.id)") }
                list.apply(.append(item))
            }
        case .update(let items):
            for item in items where !list.apply(.update(item)) {
                problems.append("update de item desconhecido: \(item.id)")
            }
        case .meta(let meta):
            self.meta = meta
        }
    }

    private func markFinished() {
        isFinished = true
    }

    func wait(
        timeout: Duration = .seconds(5),
        until condition: @Sendable (_ items: [ChatItem], _ meta: TranscriptMeta, _ finished: Bool) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition(list.items, meta, isFinished) { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition(list.items, meta, isFinished)
    }

    func waitForItems(_ expected: [ChatItem], timeout: Duration = .seconds(5)) async -> Bool {
        await wait(timeout: timeout) { items, _, _ in items == expected }
    }
}

final class OneShot: Sendable {
    private let fired = Mutex(false)

    func claim() -> Bool {
        fired.withLock { value in
            defer { value = true }
            return !value
        }
    }
}

func waitUntil(timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
