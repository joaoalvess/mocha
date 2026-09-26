import Foundation
import Synchronization

public final class HookEventHub: Sendable {
    public static let subscriberBufferSize = 256

    private let subscribers = Mutex<[UUID: AsyncStream<ReceivedHook>.Continuation]>([:])

    public init() {}

    public var subscriberCount: Int {
        subscribers.withLock { $0.count }
    }

    public func events() -> AsyncStream<ReceivedHook> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ReceivedHook.self,
            bufferingPolicy: .bufferingNewest(Self.subscriberBufferSize)
        )
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        subscribers.withLock { $0[id] = continuation }
        return stream
    }

    public func publish(_ hook: ReceivedHook) {
        subscribers.withLock { subscribers in
            for continuation in subscribers.values {
                continuation.yield(hook)
            }
        }
    }

    public func finish() {
        let continuations = subscribers.withLock { subscribers in
            defer { subscribers.removeAll() }
            return Array(subscribers.values)
        }
        for continuation in continuations {
            continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        _ = subscribers.withLock { $0.removeValue(forKey: id) }
    }
}
