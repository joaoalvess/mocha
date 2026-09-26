import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct FakeTranscriptProviderTests {
    private let session = TranscriptSession(sessionId: "s1")
    private let item = ChatItem(id: "i1", at: Date(timeIntervalSince1970: 1_790_000_000), kind: .userPrompt(text: "oi", imageCount: 0))
    private let meta = TranscriptMeta(title: "Título", model: "claude-opus-5-5", branch: "main", permissionMode: "default")

    @Test func openReturnsTheFixedPageAndCountsCalls() async throws {
        let fake = FakeTranscriptProvider()
        let page = TranscriptPage(items: [item], before: "s1:10", hasMore: true, meta: meta)
        await fake.setPage(page, forSession: "s1")
        let subscription = try await fake.open(session: session, limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page == page)
        #expect(await fake.openRequests == [.init(session: session, limit: 60)])
        #expect(await fake.openCount(forSession: "s1") == 1)
        #expect(await fake.subscriberCount(forSession: "s1") == 1)
    }

    @Test func openWithoutAFixedPageUsesTheMeta() async throws {
        let fake = FakeTranscriptProvider()
        await fake.setMeta(meta, forSession: "s1")
        let subscription = try await fake.open(session: session, limit: 10)
        defer { subscription.cancel() }
        #expect(subscription.page == TranscriptPage(items: [], before: nil, hasMore: false, meta: meta))
    }

    @Test func emittedDeltasReachEverySubscriberOfTheSession() async throws {
        let fake = FakeTranscriptProvider()
        let first = try await fake.open(session: session, limit: 60)
        let second = try await fake.open(session: session, limit: 60)
        let other = try await fake.open(session: TranscriptSession(sessionId: "s2"), limit: 60)
        var firstIterator = first.deltas.makeAsyncIterator()
        var secondIterator = second.deltas.makeAsyncIterator()
        var updated = item
        updated.kind = .userPrompt(text: "editado", imageCount: 0)
        await fake.emit(.append([item]), toSession: "s1")
        await fake.emit(.update([updated]), toSession: "s1")
        await fake.emit(.meta(meta), toSession: "s1")
        for expected in [TranscriptDelta.append([item]), .update([updated]), .meta(meta)] {
            #expect(await firstIterator.next() == expected)
            #expect(await secondIterator.next() == expected)
        }
        other.cancel()
        var otherIterator = other.deltas.makeAsyncIterator()
        #expect(await otherIterator.next() == nil)
        first.cancel()
        second.cancel()
    }

    @Test func cancellationsAreCountedAndOthersKeepReceiving() async throws {
        let fake = FakeTranscriptProvider()
        let first = try await fake.open(session: session, limit: 60)
        let second = try await fake.open(session: session, limit: 60)
        first.cancel()
        await fake.waitForSubscribers(1, forSession: "s1")
        #expect(await fake.cancellationCount == 1)
        await fake.emit(.append([item]), toSession: "s1")
        var iterator = second.deltas.makeAsyncIterator()
        #expect(await iterator.next() == .append([item]))

        let third = try await fake.open(session: session, limit: 60)
        await fake.waitForSubscribers(2, forSession: "s1")
        let consumer = Task { for await _ in third.deltas {} }
        consumer.cancel()
        await fake.waitForSubscribers(1, forSession: "s1")
        #expect(await fake.cancellationCount == 2)
        second.cancel()
    }

    @Test func finishingSubscriptionsEndsStreamsWithoutCountingCancellation() async throws {
        let fake = FakeTranscriptProvider()
        let subscription = try await fake.open(session: session, limit: 60)
        await fake.finishSubscriptions(forSession: "s1")
        var iterator = subscription.deltas.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        #expect(await fake.subscriberCount(forSession: "s1") == 0)
        #expect(await fake.cancellationCount == 0)
    }

    @Test func pagesAreServedByCursorAndUnknownCursorsThrow() async throws {
        let fake = FakeTranscriptProvider()
        let older = TranscriptPage(items: [item], before: nil, hasMore: false, meta: meta)
        await fake.setPage(older, forSession: "s1", before: "s1:10")
        #expect(try await fake.page(session: session, before: "s1:10", limit: 20) == older)
        await #expect(throws: TranscriptError.invalidCursor) {
            try await fake.page(session: session, before: "s1:99", limit: 20)
        }
        #expect(await fake.pageRequests == [
            .init(session: session, before: "s1:10", limit: 20),
            .init(session: session, before: "s1:99", limit: 20),
        ])
        #expect(await fake.pageCount(forSession: "s1") == 2)
    }

    @Test func configuredErrorsAreThrown() async {
        struct Boom: Error {}
        let fake = FakeTranscriptProvider()
        await fake.setOpenError(Boom(), forSession: "s1")
        await fake.setPageError(TranscriptError.invalidCursor, forSession: "s1")
        await #expect(throws: Boom.self) { try await fake.open(session: session, limit: 1) }
        await #expect(throws: TranscriptError.invalidCursor) { try await fake.page(session: session, before: "x", limit: 1) }
        #expect(await fake.openCount(forSession: "s1") == 1)
        #expect(await fake.subscriberCount(forSession: "s1") == 0)
    }

    @Test func homeFieldsTravelThroughMetaPagesAndDeltas() async throws {
        let fake = FakeTranscriptProvider()
        let home = TranscriptMeta(
            title: "receitas-api",
            model: "claude-opus-5-5",
            lastModified: Date(timeIntervalSince1970: 1_790_000_100),
            preview: MessagePreview(author: .assistant, text: "Rodei os testes."),
            activity: ToolActivity(toolName: "Bash", summary: "npm test", status: .running),
            contextTokens: 120_000,
            sessionStartedAt: Date(timeIntervalSince1970: 1_790_000_000),
            turnStartedAt: Date(timeIntervalSince1970: 1_790_000_050),
            turnEndedAt: Date(timeIntervalSince1970: 1_789_999_000)
        )
        await fake.setMeta(home, forSession: "s1")
        #expect(await fake.meta(forSession: session) == home)
        let subscription = try await fake.open(session: session, limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page.meta == home)

        var finished = home
        finished.activity = ToolActivity(toolName: "Bash", summary: "npm test", status: .succeeded)
        finished.turnEndedAt = Date(timeIntervalSince1970: 1_790_000_090)
        await fake.publishMeta(finished, toSession: "s1")
        var iterator = subscription.deltas.makeAsyncIterator()
        #expect(await iterator.next() == .meta(finished))
        #expect(await fake.meta(forSession: session) == finished)
    }

    @Test func metaAndStatsAreFixedPerSession() async {
        let fake = FakeTranscriptProvider()
        let stats = TranscriptStats(dropped: 2, orphanResults: 1, unknown: ["type:x": 3], claudeVersion: "2.1.283")
        await fake.setMeta(meta, forSession: "s1")
        await fake.setStats(stats, forSession: "s1")
        #expect(await fake.meta(forSession: session) == meta)
        #expect(await fake.stats(forSession: session) == stats)
        #expect(await fake.meta(forSession: TranscriptSession(sessionId: "s2")) == nil)
        #expect(await fake.metaRequests.count == 2)
        #expect(await fake.statsRequests == [session])
    }
}
