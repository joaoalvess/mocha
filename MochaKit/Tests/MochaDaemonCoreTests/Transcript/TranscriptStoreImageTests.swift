import CryptoKit
import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct TranscriptStoreImageTests {
    private static let sessionId = "3f6a1c52-7d0e-4b8a-9c1f-2e5d8a7b6c40"

    private static func pasted(_ text: String, id: Int, bytes: String, uuid: String) -> String {
        SampleLines.json([
            "type": "user",
            "uuid": uuid,
            "timestamp": "2026-09-26T10:00:00.000Z",
            "message": ["role": "user", "content": [
                ["type": "text", "text": "[Image #\(id)]\(text)"],
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": Data(bytes.utf8).base64EncodedString()]],
            ]],
            "imagePasteIds": [id],
            "version": "2.1.286",
        ])
    }

    private struct Harness {
        let sandbox: TranscriptSandbox
        let cache: URL
        let store: TranscriptStore
        let transcript: URL

        var session: TranscriptSession {
            TranscriptSession(sessionId: TranscriptStoreImageTests.sessionId)
        }

        var cachedNames: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: cache.path(percentEncoded: false))) ?? []).sorted()
        }
    }

    private func withHarness(lines: [String], _ body: (Harness) async throws -> Void) async throws {
        let sandbox = try TranscriptSandbox()
        let cache = sandbox.root.appending(path: "cache/transcript-images", directoryHint: .isDirectory)
        let transcript = try sandbox.write(Array(lines.map { $0 + "\n" }.joined().utf8), to: sandbox.sessionURL(Self.sessionId))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath, imageStore: TranscriptImageStore(directory: cache))
        try await body(Harness(sandbox: sandbox, cache: cache, store: store, transcript: transcript))
    }

    private static func storedName(_ bytes: String) -> String {
        SHA256.hash(data: Data(Data(bytes.utf8).base64EncodedString().utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    @Test func chatSubscriptionsWriteThePastedImages() async throws {
        try await withHarness(lines: [Self.pasted("olha", id: 1, bytes: "um", uuid: "u1")]) { harness in
            let subscription = try await harness.store.openChat(session: harness.session, limit: 10)
            defer { subscription.cancel() }
            let item = try #require(subscription.page.items.first)
            #expect(item.kind == .userPrompt(text: "olha", imageCount: 1))
            #expect(item.imagePaths.map { URL(filePath: $0).deletingLastPathComponent().lastPathComponent } == ["transcript-images"])
            #expect(harness.cachedNames == item.imagePaths.map { URL(filePath: $0).lastPathComponent })
        }
    }

    @Test func otherSubscriptionsWriteNothing() async throws {
        try await withHarness(lines: [Self.pasted("olha", id: 1, bytes: "um", uuid: "u1")]) { harness in
            let subscription = try await harness.store.open(session: harness.session, limit: 10)
            defer { subscription.cancel() }
            #expect(subscription.page.items.map(\.imagePaths) == [[]])
            let recorder = await TranscriptDeltaRecorder.start(subscription)
            try harness.sandbox.append(line: Self.pasted("mais", id: 2, bytes: "dois", uuid: "u2"), to: harness.transcript)
            #expect(await recorder.wait { items, _, _ in items.contains { $0.id == "u2" } })
            #expect(await recorder.items.first { $0.id == "u2" }?.imagePaths == [])
            #expect(harness.cachedNames.isEmpty)
        }
    }

    @Test func aChatJoiningAFollowedSessionGetsImagesUntilItLeaves() async throws {
        try await withHarness(lines: [Self.pasted("primeira", id: 1, bytes: "um", uuid: "u1")]) { harness in
            let home = try await harness.store.open(session: harness.session, limit: 1)
            defer { home.cancel() }
            let homeRecorder = await TranscriptDeltaRecorder.start(home)
            #expect(harness.cachedNames.isEmpty)

            let chat = try await harness.store.openChat(session: harness.session, limit: 10)
            let chatRecorder = await TranscriptDeltaRecorder.start(chat)
            #expect(chat.page.items.map(\.imagePaths.count) == [1])
            #expect(harness.cachedNames == [Self.storedName("um")])

            try harness.sandbox.append(line: Self.pasted("segunda", id: 2, bytes: "dois", uuid: "u2"), to: harness.transcript)
            #expect(await chatRecorder.wait { items, _, _ in items.count == 2 })
            #expect(await chatRecorder.items.map(\.imagePaths.count) == [1, 1])
            #expect(harness.cachedNames == [Self.storedName("um"), Self.storedName("dois")].sorted())

            chat.cancel()
            let store = harness.store
            #expect(await waitUntil { await store.subscriberCount(forSession: Self.sessionId) == 1 })
            try harness.sandbox.append(line: Self.pasted("terceira", id: 3, bytes: "três", uuid: "u3"), to: harness.transcript)
            #expect(await homeRecorder.wait { items, _, _ in items.contains { $0.id == "u3" } })
            #expect(await homeRecorder.items.first { $0.id == "u3" }?.imagePaths == [])
            #expect(harness.cachedNames == [Self.storedName("um"), Self.storedName("dois")].sorted())
        }
    }

    @Test func olderPagesUseTheCacheEvenWhileOnlyTheHomeFollowsTheSession() async throws {
        let lines = [
            Self.pasted("primeira", id: 1, bytes: "um", uuid: "u1"),
            Self.pasted("segunda", id: 2, bytes: "dois", uuid: "u2"),
        ]
        try await withHarness(lines: lines) { harness in
            let home = try await harness.store.open(session: harness.session, limit: 1)
            defer { home.cancel() }
            let before = try #require(home.page.before)
            #expect(harness.cachedNames.isEmpty)

            let page = try await harness.store.page(session: harness.session, before: before, limit: 1)

            #expect(page.items.flatMap(\.imagePaths).map { URL(filePath: $0).lastPathComponent } == [Self.storedName("um")])
            #expect(await harness.store.isFollowingFile(forSession: Self.sessionId))
        }
    }

    @Test func olderPagesAlwaysUseTheCache() async throws {
        let lines = [
            Self.pasted("primeira", id: 1, bytes: "um", uuid: "u1"),
            Self.pasted("segunda", id: 2, bytes: "dois", uuid: "u2"),
        ]
        try await withHarness(lines: lines) { harness in
            let subscription = try await harness.store.open(session: harness.session, limit: 1)
            let before = try #require(subscription.page.before)
            subscription.cancel()
            let store = harness.store
            #expect(await waitUntil { await !store.isActive(forSession: Self.sessionId) })
            #expect(harness.cachedNames.isEmpty)

            let page = try await harness.store.page(session: harness.session, before: before, limit: 1)

            #expect(page.items.map(\.id) == ["u1"])
            #expect(page.items.flatMap(\.imagePaths).map { URL(filePath: $0).lastPathComponent } == [Self.storedName("um")])
            #expect(harness.cachedNames.contains(Self.storedName("um")))
        }
    }
}
