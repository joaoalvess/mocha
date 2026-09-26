import Foundation
import Network
import Synchronization

actor HerdrSocketConnection {
    private struct Chunk: Sendable {
        let bytes: Data
        let isEnd: Bool
    }

    private final class ReadinessContinuation: Sendable {
        private let continuation: Mutex<CheckedContinuation<Void, any Error>?>

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = Mutex(continuation)
        }

        func resume(with result: Result<Void, any Error>) {
            let pending = continuation.withLock { value in
                defer { value = nil }
                return value
            }
            pending?.resume(with: result)
        }
    }

    private let connection: NWConnection
    private var buffer = Data()
    private var ended = false

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func open(path: String, queue: DispatchQueue) async throws -> HerdrSocketConnection {
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let readiness = ReadinessContinuation(continuation)
                connection.stateUpdateHandler = { [weak connection] state in
                    switch state {
                    case .ready:
                        readiness.resume(with: .success(()))
                    case .failed(let error), .waiting(let error):
                        connection?.cancel()
                        readiness.resume(with: .failure(HerdrClientError.connectionFailed(String(describing: error))))
                    case .cancelled:
                        readiness.resume(with: .failure(HerdrClientError.connectionFailed("cancelled")))
                    case .setup, .preparing:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
        return HerdrSocketConnection(connection: connection)
    }

    func write(_ data: Data) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: HerdrClientError.connectionFailed(String(describing: error)))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func readLine() async -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                return line
            }
            if ended {
                return nil
            }
            let chunk = await receive()
            buffer.append(chunk.bytes)
            if chunk.isEnd {
                ended = true
            }
        }
    }

    nonisolated func close() {
        connection.cancel()
    }

    private func receive() async -> Chunk {
        guard !Task.isCancelled else {
            close()
            return Chunk(bytes: Data(), isEnd: true)
        }
        let connection = self.connection
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { content, _, isComplete, error in
                    continuation.resume(returning: Chunk(bytes: content ?? Data(), isEnd: isComplete || error != nil))
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
