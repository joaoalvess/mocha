import Foundation
import MochaDaemonCore
import MochaProtocol
import Synchronization

public final class FakeUsageProvider: UsageProviding {
    private struct State {
        var contexts: [String: Double]
        var contextRequests: [String] = []
    }

    private let broadcast: LatestValueBroadcast<UsageSnapshot?>
    private let state: Mutex<State>

    public init(snapshot: UsageSnapshot? = nil, contexts: [String: Double] = [:]) {
        broadcast = LatestValueBroadcast(snapshot)
        state = Mutex(State(contexts: contexts))
    }

    public func events() -> AsyncStream<UsageSnapshot?> {
        broadcast.subscribe()
    }

    public var snapshot: UsageSnapshot? {
        get async { broadcast.value }
    }

    public var currentSnapshot: UsageSnapshot? {
        broadcast.value
    }

    public func contextUsedPercent(forSession sessionId: String) async -> Double? {
        state.withLock { state in
            state.contextRequests.append(sessionId)
            return state.contexts[sessionId]
        }
    }

    public func update(_ snapshot: UsageSnapshot?, contexts: [String: Double]? = nil) {
        if let contexts {
            state.withLock { $0.contexts = contexts }
        }
        broadcast.publish(snapshot)
    }

    public var contextRequests: [String] {
        state.withLock { $0.contextRequests }
    }

    public var subscriberCount: Int {
        broadcast.subscriberCount
    }
}
