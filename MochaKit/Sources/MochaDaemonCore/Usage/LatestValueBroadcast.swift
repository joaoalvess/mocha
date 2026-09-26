import Foundation
import Synchronization

public final class LatestValueBroadcast<Value: Sendable>: Sendable {
    private struct State {
        var value: Value
        var subscribers: [UUID: AsyncStream<Value>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(_ value: Value) {
        state = Mutex(State(value: value))
    }

    public var value: Value {
        state.withLock { $0.value }
    }

    public var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    public func subscribe() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        state.withLock { state in
            continuation.yield(state.value)
            state.subscribers[id] = continuation
        }
        return stream
    }

    public func publish(_ value: Value) {
        state.withLock { state in
            state.value = value
            for continuation in state.subscribers.values {
                continuation.yield(value)
            }
        }
    }

    public func finish() {
        let continuations = state.withLock { state in
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for continuation in continuations {
            continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        _ = state.withLock { $0.subscribers.removeValue(forKey: id) }
    }
}
