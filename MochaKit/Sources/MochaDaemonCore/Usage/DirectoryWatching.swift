import Darwin
import Dispatch
import Foundation

public protocol DirectoryWatching: Sendable {
    func changes(in directory: URL) -> AsyncStream<Void>
}

public struct DispatchDirectoryWatcher: DirectoryWatching {
    static let queue = DispatchQueue(label: "com.joaoalves.mocha.usage.watch")

    public var retryInterval: Duration

    public init(retryInterval: Duration = .seconds(60)) {
        self.retryInterval = retryInterval
    }

    public func changes(in directory: URL) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let path = directory.fileSystemPath
        let retryInterval = retryInterval
        let task = Task {
            var descriptor = open(path, O_EVTONLY | O_CLOEXEC)
            let appearedLater = descriptor < 0
            while descriptor < 0 {
                guard (try? await Task.sleep(for: retryInterval)) != nil else { return }
                descriptor = open(path, O_EVTONLY | O_CLOEXEC)
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: Self.queue)
            source.setEventHandler {
                continuation.yield(())
            }
            source.setCancelHandler { [descriptor] in
                close(descriptor)
            }
            source.activate()
            if appearedLater {
                continuation.yield(())
            }
            await Self.waitForCancellation()
            source.cancel()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    private static func waitForCancellation() async {
        let (never, finish) = AsyncStream.makeStream(of: Void.self)
        await withTaskCancellationHandler {
            for await _ in never {}
        } onCancel: {
            finish.finish()
        }
    }
}
