import MochaDaemonCore
import MochaProtocol
import Synchronization

public final class FakeLiveActivitySender: LiveActivityPushSending {
    public struct Sent: Sendable, Equatable {
        public let push: AgentActivityPush
        public let token: String
        public let environment: ApnsEnvironment
        public let priority: ApnsPriority
    }

    private struct State {
        var sent: [Sent] = []
        var outcomes: [LiveActivityDelivery] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var sent: [Sent] {
        state.withLock { $0.sent }
    }

    public func respond(with outcomes: LiveActivityDelivery...) {
        state.withLock { $0.outcomes.append(contentsOf: outcomes) }
    }

    public func sendLiveActivity(
        _ push: AgentActivityPush,
        to token: String,
        environment: ApnsEnvironment,
        priority: ApnsPriority
    ) async -> LiveActivityDelivery {
        state.withLock { state in
            state.sent.append(Sent(push: push, token: token, environment: environment, priority: priority))
            return state.outcomes.isEmpty ? .delivered : state.outcomes.removeFirst()
        }
    }
}
