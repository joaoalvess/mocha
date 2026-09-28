#if DEBUG
import Foundation
import Network
import NIOCore
import Synchronization

enum SSHProbeForwarderError: Error, LocalizedError {
    case listenerFailed(String)
    case listenerCancelled

    var errorDescription: String? {
        switch self {
        case .listenerFailed(let reason):
            "O listener local falhou: \(reason)"
        case .listenerCancelled:
            "O listener local foi cancelado."
        }
    }
}

actor SSHProbePortForwarder {
    typealias ChannelOpener = @Sendable (Int) async throws -> SSHProbeByteChannel

    let remotePort: Int
    private let openChannel: ChannelOpener
    private let queue = DispatchQueue(label: "com.joaoalves.mocha.ssh-probe.listener")
    private var listener: NWListener?
    private var bridges: [UUID: Task<Void, Never>] = [:]

    init(remotePort: Int, openChannel: @escaping ChannelOpener) {
        self.remotePort = remotePort
        self.openChannel = openChannel
    }

    func start(preferredLocalPort: UInt16? = nil) async throws -> UInt16 {
        stop()
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: preferredLocalPort.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.accept(connection) }
        }
        let ready = SSHProbeReadyGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready.arm(continuation)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        ready.resume(with: listener.port.map { .success($0.rawValue) }
                            ?? .failure(SSHProbeForwarderError.listenerFailed("sem porta")))
                    case .failed(let error):
                        ready.resume(with: .failure(SSHProbeForwarderError.listenerFailed(error.localizedDescription)))
                        listener.cancel()
                    case .cancelled:
                        ready.resume(with: .failure(SSHProbeForwarderError.listenerCancelled))
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for bridge in bridges.values {
            bridge.cancel()
        }
        bridges.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        let id = UUID()
        let openChannel = openChannel
        let remotePort = remotePort
        let queue = queue
        bridges[id] = Task { [weak self] in
            await SSHProbeBridge.run(connection: connection, queue: queue) {
                try await openChannel(remotePort)
            }
            await self?.finish(id)
        }
    }

    private func finish(_ id: UUID) {
        bridges[id] = nil
    }
}

private final class SSHProbeReadyGate: Sendable {
    private let continuation = Mutex<CheckedContinuation<UInt16, any Error>?>(nil)

    func arm(_ value: CheckedContinuation<UInt16, any Error>) {
        continuation.withLock { $0 = value }
    }

    func resume(with result: Result<UInt16, any Error>) {
        let pending = continuation.withLock { value in
            defer { value = nil }
            return value
        }
        pending?.resume(with: result)
    }
}

enum SSHProbeBridge {
    static let chunkSize = 64 * 1024

    static func run(
        connection: NWConnection,
        queue: DispatchQueue,
        openChannel: @Sendable () async throws -> SSHProbeByteChannel
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

    static func pump(connection: NWConnection, channel: SSHProbeByteChannel) async throws {
        try await channel.executeThenClose { inbound, outbound in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    while true {
                        let chunk = try await connection.sshProbeReceive(maximumLength: chunkSize)
                        if let data = chunk.data, !data.isEmpty {
                            try await outbound.write(ByteBuffer(bytes: data))
                        }
                        if chunk.isComplete { break }
                    }
                    outbound.finish()
                }
                group.addTask {
                    for try await buffer in inbound {
                        try await connection.sshProbeSend(Data(buffer.readableBytesView))
                    }
                    try await connection.sshProbeSendEndOfStream()
                }
                try await group.waitForAll()
            }
        }
    }
}

struct SSHProbeReceivedChunk: Sendable {
    var data: Data?
    var isComplete: Bool
}

extension NWConnection {
    func sshProbeReceive(maximumLength: Int) async throws -> SSHProbeReceivedChunk {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: SSHProbeReceivedChunk(data: data, isComplete: isComplete))
                }
            }
        }
    }

    func sshProbeSend(_ data: Data) async throws {
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

    func sshProbeSendEndOfStream() async throws {
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
#endif
