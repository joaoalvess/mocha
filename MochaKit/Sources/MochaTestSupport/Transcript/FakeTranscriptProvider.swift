import Foundation
import MochaDaemonCore
import MochaProtocol

public actor FakeTranscriptProvider: TranscriptProviding {
    public struct OpenRequest: Sendable, Equatable {
        public var session: TranscriptSession
        public var limit: Int

        public init(session: TranscriptSession, limit: Int) {
            self.session = session
            self.limit = limit
        }
    }

    public struct PageRequest: Sendable, Equatable {
        public var session: TranscriptSession
        public var before: String
        public var limit: Int

        public init(session: TranscriptSession, before: String, limit: Int) {
            self.session = session
            self.before = before
            self.limit = limit
        }
    }

    private struct SubscriberWaiter {
        let sessionId: String
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var openPages: [String: TranscriptPage] = [:]
    private var olderPages: [String: [String: TranscriptPage]] = [:]
    private var metas: [String: TranscriptMeta] = [:]
    private var statistics: [String: TranscriptStats] = [:]
    private var openErrors: [String: any Error] = [:]
    private var pageErrors: [String: any Error] = [:]
    private var subscribers: [String: [UUID: AsyncStream<TranscriptDelta>.Continuation]] = [:]
    private var waiters: [SubscriberWaiter] = []

    public private(set) var openRequests: [OpenRequest] = []
    public private(set) var pageRequests: [PageRequest] = []
    public private(set) var metaRequests: [TranscriptSession] = []
    public private(set) var statsRequests: [TranscriptSession] = []
    public private(set) var cancellationCount = 0

    public init() {}

    public func setPage(_ page: TranscriptPage, forSession sessionId: String) {
        openPages[sessionId] = page
    }

    public func setPage(_ page: TranscriptPage, forSession sessionId: String, before cursor: String) {
        olderPages[sessionId, default: [:]][cursor] = page
    }

    public func setMeta(_ meta: TranscriptMeta?, forSession sessionId: String) {
        metas[sessionId] = meta
    }

    public func setStats(_ stats: TranscriptStats?, forSession sessionId: String) {
        statistics[sessionId] = stats
    }

    public func setOpenError(_ error: (any Error)?, forSession sessionId: String) {
        openErrors[sessionId] = error
    }

    public func setPageError(_ error: (any Error)?, forSession sessionId: String) {
        pageErrors[sessionId] = error
    }

    public func publishMeta(_ meta: TranscriptMeta, toSession sessionId: String) {
        metas[sessionId] = meta
        emit(.meta(meta), toSession: sessionId)
    }

    public func emit(_ delta: TranscriptDelta, toSession sessionId: String) {
        for continuation in subscribers[sessionId, default: [:]].values {
            continuation.yield(delta)
        }
    }

    public func finishSubscriptions(forSession sessionId: String) {
        let finished = subscribers.removeValue(forKey: sessionId) ?? [:]
        for continuation in finished.values {
            continuation.finish()
        }
        resumeWaiters()
    }

    public func subscriberCount(forSession sessionId: String) -> Int {
        subscribers[sessionId]?.count ?? 0
    }

    public func openCount(forSession sessionId: String) -> Int {
        openRequests.count { $0.session.sessionId == sessionId }
    }

    public func pageCount(forSession sessionId: String) -> Int {
        pageRequests.count { $0.session.sessionId == sessionId }
    }

    public func waitForSubscribers(_ count: Int, forSession sessionId: String) async {
        guard subscriberCount(forSession: sessionId) != count else { return }
        await withCheckedContinuation { continuation in
            waiters.append(SubscriberWaiter(sessionId: sessionId, count: count, continuation: continuation))
        }
    }

    public func open(session: TranscriptSession, limit: Int) async throws -> TranscriptSubscription {
        openRequests.append(OpenRequest(session: session, limit: limit))
        if let error = openErrors[session.sessionId] {
            throw error
        }
        let page = openPages[session.sessionId] ?? TranscriptPage(
            items: [],
            before: nil,
            hasMore: false,
            meta: metas[session.sessionId] ?? TranscriptMeta()
        )
        let (deltas, continuation) = AsyncStream.makeStream(of: TranscriptDelta.self)
        let id = UUID()
        let sessionId = session.sessionId
        subscribers[sessionId, default: [:]][id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id, sessionId: sessionId) }
        }
        resumeWaiters()
        return TranscriptSubscription(page: page, deltas: deltas, onCancel: { continuation.finish() })
    }

    public func page(session: TranscriptSession, before: String, limit: Int) async throws -> TranscriptPage {
        pageRequests.append(PageRequest(session: session, before: before, limit: limit))
        if let error = pageErrors[session.sessionId] {
            throw error
        }
        guard let page = olderPages[session.sessionId]?[before] else {
            throw TranscriptError.invalidCursor
        }
        return page
    }

    public func meta(forSession session: TranscriptSession) async -> TranscriptMeta? {
        metaRequests.append(session)
        return metas[session.sessionId]
    }

    public func stats(forSession session: TranscriptSession) async -> TranscriptStats? {
        statsRequests.append(session)
        return statistics[session.sessionId]
    }

    private func removeSubscriber(_ id: UUID, sessionId: String) {
        guard subscribers[sessionId]?.removeValue(forKey: id) != nil else { return }
        cancellationCount += 1
        resumeWaiters()
    }

    private func resumeWaiters() {
        var pending: [SubscriberWaiter] = []
        for waiter in waiters {
            if subscriberCount(forSession: waiter.sessionId) == waiter.count {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        waiters = pending
    }
}
