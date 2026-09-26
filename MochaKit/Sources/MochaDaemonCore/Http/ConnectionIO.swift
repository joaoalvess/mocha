import Foundation
import Network

struct ConnectionIO: Sendable {
    struct Chunk: Sendable {
        let bytes: Data
        let isEnd: Bool
    }

    let connection: NWConnection

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
    }

    func receive(maximumLength: Int) async -> Chunk {
        guard !Task.isCancelled else {
            cancel()
            return Chunk(bytes: Data(), isEnd: true)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { content, _, isComplete, error in
                    continuation.resume(returning: Chunk(bytes: content ?? Data(), isEnd: isComplete || error != nil))
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func enqueue(_ data: Data, closingWrite: Bool = false, completion: @escaping @Sendable (Bool) -> Void) {
        connection.send(
            content: data,
            contentContext: closingWrite ? .finalMessage : .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { error in completion(error == nil) }
        )
    }

    func send(_ data: Data, closingWrite: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            enqueue(data, closingWrite: closingWrite) { continuation.resume(returning: $0) }
        }
    }

    func scheduleCancellation(after duration: Duration) -> Task<Void, Never> {
        Task { [self] in
            if (try? await Task.sleep(for: duration)) != nil {
                cancel()
            }
        }
    }

    func cancel() {
        connection.cancel()
    }
}
