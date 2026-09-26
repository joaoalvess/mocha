import Foundation
import MochaDaemonCore
import MochaProtocol
import Synchronization

public struct FakeArchiveCall: Sendable, Equatable {
    public let sessionId: String
    public let date: Date

    public init(sessionId: String, date: Date) {
        self.sessionId = sessionId
        self.date = date
    }
}

public final class FakeSessionArchive: SessionArchiving {
    private struct State {
        var userArchived: [String: Date]
        var endedCalls: [ArchivedSession] = []
        var archiveCalls: [FakeArchiveCall] = []
        var turnStartedCalls: [FakeArchiveCall] = []
        var resumedCalls: [String] = []
    }

    private let broadcast: LatestValueBroadcast<[ArchivedSession]>
    private let state: Mutex<State>

    public init(sessions: [ArchivedSession] = [], userArchived: [String: Date] = [:]) {
        broadcast = LatestValueBroadcast(sessions)
        state = Mutex(State(userArchived: userArchived))
    }

    public func events() -> AsyncStream<[ArchivedSession]> {
        broadcast.subscribe()
    }

    public var sessions: [ArchivedSession] {
        get async { broadcast.value }
    }

    public var currentSessions: [ArchivedSession] {
        broadcast.value
    }

    public func session(_ sessionId: String) async -> ArchivedSession? {
        broadcast.value.first { $0.id == sessionId }
    }

    public func sessionEnded(_ session: ArchivedSession) async {
        state.withLock { $0.endedCalls.append(session) }
        broadcast.publish([session] + broadcast.value.filter { $0.id != session.id })
    }

    public func archive(sessionId: String, at date: Date) async {
        state.withLock { state in
            state.archiveCalls.append(FakeArchiveCall(sessionId: sessionId, date: date))
            state.userArchived[sessionId] = date
        }
    }

    public func archivedAt(sessionId: String) async -> Date? {
        state.withLock { $0.userArchived[sessionId] }
    }

    public func turnStarted(sessionId: String, at date: Date) async {
        state.withLock { state in
            state.turnStartedCalls.append(FakeArchiveCall(sessionId: sessionId, date: date))
            if let archivedAt = state.userArchived[sessionId], archivedAt < date {
                state.userArchived[sessionId] = nil
            }
        }
    }

    public func sessionResumed(sessionId: String) async {
        state.withLock { $0.resumedCalls.append(sessionId) }
        let sessions = broadcast.value
        guard sessions.contains(where: { $0.id == sessionId }) else { return }
        broadcast.publish(sessions.filter { $0.id != sessionId })
    }

    public func setSessions(_ sessions: [ArchivedSession]) {
        broadcast.publish(sessions)
    }

    public var endedCalls: [ArchivedSession] {
        state.withLock { $0.endedCalls }
    }

    public var archiveCalls: [FakeArchiveCall] {
        state.withLock { $0.archiveCalls }
    }

    public var turnStartedCalls: [FakeArchiveCall] {
        state.withLock { $0.turnStartedCalls }
    }

    public var resumedCalls: [String] {
        state.withLock { $0.resumedCalls }
    }

    public var userArchived: [String: Date] {
        state.withLock { $0.userArchived }
    }

    public var subscriberCount: Int {
        broadcast.subscriberCount
    }
}
