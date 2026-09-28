import Foundation
import Network

enum TunnelBridge {
    static let chunkSize = 64 * 1024

    static func run(
        connection: NWConnection,
        queue: DispatchQueue,
        openChannel: @Sendable () async throws -> any TunnelChannel
    ) async {
        connection.start(queue: queue)
        await withTaskCancellationHandler {
            do {
                let channel = try await openChannel()
                try await pump(connection: connection, channel: channel)
            } catch {}
            connection.cancel()
        } onCancel: {
            connection.cancel()
        }
    }

    static func pump(connection: NWConnection, channel: any TunnelChannel) async throws {
        try await channel.exchange { inbound, outbound in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    while true {
                        let chunk = try await connection.tunnelReceive(maximumLength: chunkSize)
                        if let data = chunk.data, !data.isEmpty {
                            try await outbound.write(data)
                        }
                        if chunk.isComplete { break }
                    }
                    outbound.finish()
                }
                group.addTask {
                    try await inbound.forEachChunk { data in
                        try await connection.tunnelSend(data)
                    }
                    try await connection.tunnelSendEndOfStream()
                }
                try await group.waitForAll()
            }
        }
    }
}

struct TunnelReceivedChunk: Sendable {
    var data: Data?
    var isComplete: Bool
}

extension NWConnection {
    func tunnelReceive(maximumLength: Int) async throws -> TunnelReceivedChunk {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: TunnelReceivedChunk(data: data, isComplete: isComplete))
                    }
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func tunnelSend(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func tunnelSendEndOfStream() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
