import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct TranscriptStoreTests {
    private func fixtureStore() -> TranscriptStore {
        TranscriptStore(projectsRoot: TranscriptFixtures.fixturesRoot.path(percentEncoded: false))
    }

    @Test(arguments: TranscriptFixtures.names)
    func openingAFixtureMatchesItsSnapshot(_ name: String) async throws {
        let store = fixtureStore()
        let expected = try TranscriptFixtures.expectedSnapshot(name)
        let subscription = try await store.open(session: TranscriptSession(sessionId: name), limit: 1_000)
        defer { subscription.cancel() }
        #expect(subscription.page.items == expected.items)
        #expect(!subscription.page.hasMore)
        #expect(subscription.page.before == nil)
        let meta = subscription.page.meta
        #expect(TranscriptSnapshot.Meta(meta: meta) == expected.meta)
        #expect(meta.claudeVersion == "2.1.282")
        #expect(meta.lastModified == TranscriptFileStatus.of(path: TranscriptFixtures.path(name))?.modificationDate)
    }

    @Test(arguments: TranscriptFixtures.names)
    func pagingThroughTheStoreRebuildsTheSnapshot(_ name: String) async throws {
        let store = fixtureStore()
        let session = TranscriptSession(sessionId: name)
        let expected = try TranscriptFixtures.expectedSnapshot(name)
        let subscription = try await store.open(session: session, limit: 4)
        defer { subscription.cancel() }
        var pages = [subscription.page.items]
        var cursor = subscription.page.before
        #expect(subscription.page.hasMore == (cursor != nil))
        while let before = cursor {
            #expect(before.hasPrefix("\(name):"))
            let page = try await store.page(session: session, before: before, limit: 4)
            pages.append(page.items)
            cursor = page.before
        }
        #expect(pages.reversed().flatMap { $0 } == expected.items)
    }

    @Test func pagesWorkWithoutAnOpenSubscription() async throws {
        let store = fixtureStore()
        let session = TranscriptSession(sessionId: "tool-calls")
        let subscription = try await store.open(session: session, limit: 3)
        let before = try #require(subscription.page.before)
        subscription.cancel()
        #expect(await waitUntil { await !store.isActive(forSession: "tool-calls") })
        let page = try await store.page(session: session, before: before, limit: 3)
        #expect(page.items.count == 3)
        #expect(page.meta.title == "Corrigir testes do login")
    }

    @Test func pageInTheMiddleOfToolCallsAppliesLaterToolResults() async throws {
        let offsets = try FixtureOffsets.lineOffsets(of: "tool-calls", containing: "EFPuYc\",\"type\":\"tool_result\"")
        let offset = try #require(offsets.first)
        let page = try await fixtureStore().page(session: TranscriptSession(sessionId: "tool-calls"), before: "tool-calls:\(offset)", limit: 3)
        guard case .toolCall(let call) = page.items.last?.kind else {
            Issue.record("a página deveria terminar no Read")
            return
        }
        #expect(call.name == "Read")
        #expect(call.status == .succeeded)
        #expect(page.hasMore)
    }

    @Test func invalidCursorsThrow() async throws {
        let store = fixtureStore()
        let session = TranscriptSession(sessionId: "basic-turn")
        let subscription = try await store.open(session: session, limit: 2)
        defer { subscription.cancel() }
        let valid = try #require(subscription.page.before)
        let offset = try #require(UInt64(valid.split(separator: ":").last ?? ""))
        let invalid = [
            "lixo",
            "basic-turn:",
            "basic-turn:\(offset + 1)",
            "basic-turn:99999999",
            "tool-calls:\(offset)",
            "outra-sessao:0",
        ]
        for cursor in invalid {
            await #expect(throws: TranscriptError.invalidCursor) {
                try await store.page(session: session, before: cursor, limit: 2)
            }
        }
        await #expect(throws: TranscriptError.invalidCursor) {
            try await store.page(session: TranscriptSession(sessionId: "nao-existe"), before: "nao-existe:0", limit: 2)
        }
        _ = try await store.page(session: session, before: valid, limit: 2)
    }

    @Test func metaAndStatsComeFromTheWholeFile() async throws {
        let store = fixtureStore()
        let malformed = TranscriptSession(sessionId: "malformed")
        let meta = try #require(await store.meta(forSession: malformed))
        #expect(meta.title == nil)
        #expect(meta.model == "claude-opus-5-5")
        #expect(meta.branch == "main")
        #expect(meta.permissionMode == "default")
        #expect(meta.claudeVersion == "2.1.282")
        #expect(meta.lastModified == TranscriptFileStatus.of(path: TranscriptFixtures.path("malformed"))?.modificationDate)
        let stats = try #require(await store.stats(forSession: malformed))
        #expect(stats == TranscriptStats(
            dropped: 2,
            orphanResults: 1,
            unknown: ["type:future-thing": 1, "subtype:future_notice": 1, "block:server_tool_use": 1, "block:document": 1],
            claudeVersion: "2.1.282"
        ))
        #expect(await store.stats(forSession: TranscriptSession(sessionId: "basic-turn")) == TranscriptStats(claudeVersion: "2.1.282"))
    }

    @Test(arguments: TranscriptFixtures.names)
    func metaWithoutFollowingMatchesTheSnapshot(_ name: String) async throws {
        let meta = try #require(await fixtureStore().meta(forSession: TranscriptSession(sessionId: name)))
        #expect(TranscriptSnapshot.Meta(meta: meta) == (try TranscriptFixtures.expectedSnapshot(name)).meta)
        #expect(meta.claudeVersion == "2.1.282")
    }

    @Test func missingSessionHasNoMetaNoStatsAndAnEmptyPage() async throws {
        let sandbox = try TranscriptSandbox()
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let session = TranscriptSession(sessionId: "sem-arquivo")
        #expect(await store.meta(forSession: session) == nil)
        #expect(await store.stats(forSession: session) == nil)
        let subscription = try await store.open(session: session, limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page == TranscriptPage(items: [], before: nil, hasMore: false, meta: TranscriptMeta()))
        #expect(await store.isFollowingFile(forSession: "sem-arquivo") == false)
    }

    @Test func metaCacheFollowsFileChanges() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(Array((SampleLines.title("Primeiro") + "\n").utf8), to: sandbox.sessionURL("s1"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let session = TranscriptSession(sessionId: "s1")
        #expect(await store.meta(forSession: session)?.title == "Primeiro")
        try sandbox.append(line: SampleLines.title("segundo-titulo"), to: url)
        #expect(await store.meta(forSession: session)?.title == "segundo-titulo")
        try sandbox.append(line: SampleLines.json(["type": "coisa-nova"]), to: url)
        #expect(await store.stats(forSession: session)?.unknown == ["type:coisa-nova": 1])
    }

    @Test func malformedSessionKeepsWorkingAfterBadLines() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("malformed"), to: sandbox.sessionURL("m1"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "m1"), limit: 1_000)
        defer { subscription.cancel() }
        let expected = try TranscriptFixtures.expectedSnapshot("malformed")
        #expect(subscription.page.items == expected.items)
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        try sandbox.append(Array("\"}]},\"uuid\":\"fim\",\"timestamp\":\"2026-09-25T15:00:20.000Z\"}\n".utf8), to: url)
        try sandbox.append(line: SampleLines.user("depois do conserto", uuid: "u-depois"), to: url)
        let arrived = await recorder.wait { items, _, _ in items.count == expected.items.count + 2 }
        #expect(arrived)
        let tail = await recorder.items.suffix(2).map(\.kind)
        #expect(tail == [.assistantText(markdown: "parcial"), .userPrompt(text: "depois do conserto", imageCount: 0)])
        #expect(await recorder.problems.isEmpty)
    }
}

enum FixtureOffsets {
    static func lineOffsets(of name: String, containing marker: String) throws -> [UInt64] {
        let bytes = try TranscriptFixtures.bytes(name)
        var offsets: [UInt64] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            if String(decoding: bytes[start..<index], as: UTF8.self).contains(marker) {
                offsets.append(UInt64(start))
            }
            start = index + 1
        }
        return offsets
    }
}
