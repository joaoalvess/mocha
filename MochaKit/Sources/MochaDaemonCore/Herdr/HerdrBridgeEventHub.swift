import Foundation
import MochaProtocol
import Synchronization

public final class HerdrBridgeEventHub: Sendable {
    public static let subscriberBufferSize = 256

    private struct State {
        var tree: [WorkspaceNode]
        var available: Bool
        var subscribers: [UUID: AsyncStream<HerdrBridgeEvent>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(tree: [WorkspaceNode] = [], available: Bool = false) {
        state = Mutex(State(tree: tree, available: available))
    }

    public var tree: [WorkspaceNode] {
        state.withLock { $0.tree }
    }

    public var isAvailable: Bool {
        state.withLock { $0.available }
    }

    public var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    public func subscribe() -> AsyncStream<HerdrBridgeEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: HerdrBridgeEvent.self,
            bufferingPolicy: .bufferingNewest(Self.subscriberBufferSize)
        )
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        state.withLock { state in
            continuation.yield(.snapshot(tree: state.tree, available: state.available))
            state.subscribers[id] = continuation
        }
        return stream
    }

    public func publish(_ event: HerdrBridgeEvent) {
        state.withLock { state in
            switch event {
            case .snapshot(let tree, let available):
                state.tree = tree
                state.available = available
            case .treeChanged(let tree):
                state.tree = tree
            case .availability(let available):
                state.available = available
            case .agentStatus, .sessionChanged, .paneMoved:
                break
            }
            for continuation in state.subscribers.values {
                continuation.yield(event)
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
