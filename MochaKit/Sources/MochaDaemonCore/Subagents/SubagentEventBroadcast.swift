import Foundation
import Synchronization

final class SubagentEventBroadcast: Sendable {
    private let subscribers = Mutex<[UUID: AsyncStream<SubagentEvent>.Continuation]>([:])

    func subscribe() -> AsyncStream<SubagentEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SubagentEvent.self, bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            _ = self?.subscribers.withLock { $0.removeValue(forKey: id) }
        }
        subscribers.withLock { $0[id] = continuation }
        return stream
    }

    func publish(_ events: [SubagentEvent]) {
        guard !events.isEmpty else { return }
        subscribers.withLock { subscribers in
            for continuation in subscribers.values {
                for event in events {
                    continuation.yield(event)
                }
            }
        }
    }
}
