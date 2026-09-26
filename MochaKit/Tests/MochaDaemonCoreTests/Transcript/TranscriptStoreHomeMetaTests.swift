import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct TranscriptStoreHomeMetaTests {
    private static func toolUse(id: String, command: String, uuid: String) -> String {
        SampleLines.json([
            "type": "assistant",
            "uuid": uuid,
            "timestamp": "2026-09-26T10:00:02.000Z",
            "message": [
                "model": "claude-opus-5-5",
                "content": [["type": "tool_use", "id": id, "name": "Bash", "input": ["command": command]]],
                "usage": ["input_tokens": 5, "cache_creation_input_tokens": 50, "cache_read_input_tokens": 500],
            ],
            "gitBranch": "main",
            "version": "2.1.283",
        ])
    }

    private static func metas(in deltas: [TranscriptDelta]) -> [TranscriptMeta] {
        deltas.compactMap { delta in
            if case .meta(let meta) = delta { return meta }
            return nil
        }
    }

    @Test func appendedToolUseAndResultEmitMetaWithTheNewActivity() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("home"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "home"), limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page.meta.activity == nil)
        #expect(subscription.page.meta.contextTokens == 19_212)
        let recorder = await TranscriptDeltaRecorder.start(subscription)

        try sandbox.append(line: Self.toolUse(id: "toolu_home", command: "npm test\n--watch", uuid: "a-home"), to: url)
        let running = ToolActivity(toolName: "Bash", summary: "npm test", status: .running)
        #expect(await recorder.wait { _, meta, _ in meta.activity == running })
        #expect(await recorder.meta.contextTokens == 555)

        try sandbox.append(line: SampleLines.toolResult(id: "toolu_home", uuid: "r-home"), to: url)
        let succeeded = ToolActivity(toolName: "Bash", summary: "npm test", status: .succeeded)
        #expect(await recorder.wait { _, meta, _ in meta.activity == succeeded })

        let metas = Self.metas(in: await recorder.deltas)
        #expect(metas.map(\.activity) == [running, succeeded])
        #expect(metas.allSatisfy { $0.lastModified != nil })
        #expect(await recorder.problems.isEmpty)
    }

    @Test func linesThatChangeNoMetaFieldEmitNoMeta() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("quieto"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "quieto"), limit: 60)
        defer { subscription.cancel() }
        let title = try #require(subscription.page.meta.title)
        let recorder = await TranscriptDeltaRecorder.start(subscription)

        try sandbox.append(line: SampleLines.json(["type": "mode", "mode": "normal"]), to: url)
        try sandbox.append(line: SampleLines.title(title), to: url)
        try await Task.sleep(for: .milliseconds(150))
        try sandbox.append(line: SampleLines.user("novo turno", uuid: "u-novo"), to: url)
        #expect(await recorder.wait { items, _, _ in items.last?.id == "u-novo" })
        try await Task.sleep(for: .milliseconds(100))

        let metas = Self.metas(in: await recorder.deltas)
        #expect(metas.count == 1)
        #expect(metas.first?.preview == MessagePreview(author: .user, text: "novo turno"))
        #expect(metas.first?.turnStartedAt == ProtocolDate.date(from: "2026-09-26T10:00:00.000Z"))
    }

    @Test func metaOfAFollowedSessionComesFromTheLiveState() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("tool-calls"), to: sandbox.projectURL().appending(path: "aninhado/viva.jsonl"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let bySessionId = TranscriptSession(sessionId: "viva")
        #expect(await store.meta(forSession: bySessionId) == nil)

        let subscription = try await store.open(
            session: TranscriptSession(sessionId: "viva", transcriptPath: url.path(percentEncoded: false)),
            limit: 60
        )
        try sandbox.append(line: Self.toolUse(id: "toolu_viva", command: "make", uuid: "a-viva"), to: url)
        let live = try #require(await store.meta(forSession: bySessionId))
        #expect(live.activity == ToolActivity(toolName: "Bash", summary: "make", status: .running))
        #expect(live.title == "Corrigir testes do login")
        #expect(live.lastModified == TranscriptFileStatus.of(path: url.path(percentEncoded: false))?.modificationDate)

        subscription.cancel()
        #expect(await waitUntil { await !store.isActive(forSession: "viva") })
        #expect(await store.meta(forSession: bySessionId) == nil)
    }

    @Test func pageMetaCarriesTheHomeFields() async throws {
        let store = TranscriptStore(projectsRoot: TranscriptFixtures.fixturesRoot.path(percentEncoded: false))
        let session = TranscriptSession(sessionId: "tool-calls")
        let subscription = try await store.open(session: session, limit: 3)
        let before = try #require(subscription.page.before)
        subscription.cancel()
        let page = try await store.page(session: session, before: before, limit: 3)
        let expected = try TranscriptFixtures.expectedSnapshot("tool-calls").meta
        #expect(TranscriptSnapshot.Meta(meta: page.meta) == expected)
    }
}
