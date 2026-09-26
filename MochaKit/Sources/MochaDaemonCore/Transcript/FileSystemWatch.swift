import Darwin
import Dispatch
import Foundation

final class FileSystemWatch {
    static let queue = DispatchQueue(label: "com.joaoalves.mocha.transcript.watch")

    private let source: any DispatchSourceFileSystemObject

    init?(path: String, events: DispatchSource.FileSystemEvent, onEvent: @escaping @Sendable () -> Void) {
        let descriptor = open(path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: Self.queue)
        source.setEventHandler(handler: onEvent)
        source.setCancelHandler { close(descriptor) }
        source.activate()
    }

    deinit {
        source.cancel()
    }

    func cancel() {
        source.cancel()
    }
}
