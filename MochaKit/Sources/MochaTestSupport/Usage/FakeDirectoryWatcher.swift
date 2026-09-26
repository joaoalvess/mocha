import Foundation
import MochaDaemonCore
import Synchronization

public final class FakeDirectoryWatcher: DirectoryWatching {
    private struct State {
        var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
        var directories: [URL] = []
    }

    private let state = Mutex(State())

    public init() {}

    public func changes(in directory: URL) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.subscribers.removeValue(forKey: id) }
        }
        state.withLock { state in
            state.subscribers[id] = continuation
            state.directories.append(directory)
        }
        return stream
    }

    public func signal() {
        let continuations = state.withLock { Array($0.subscribers.values) }
        for continuation in continuations {
            continuation.yield(())
        }
    }

    public var watchedDirectories: [URL] {
        state.withLock { $0.directories }
    }

    public var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }
}
