import Foundation
import Network
import Synchronization

public enum TunnelPortForwarderError: Error, Equatable, LocalizedError {
    case listenerFailed(String)
    case listenerCancelled

    public var errorDescription: String? {
        switch self {
        case .listenerFailed(let reason):
            "O túnel local não abriu: \(reason)"
        case .listenerCancelled:
            "O túnel local foi fechado."
        }
    }
}

public actor TunnelPortForwarder {
    public let remotePort: Int
    private let openChannel: TunnelChannelOpener
    private let queue = DispatchQueue(label: "com.joaoalves.mocha.tunnel.listener")
    private var listener: NWListener?
    private var listenerEvents: TunnelListenerEvents?
    private var bridges: [UUID: Task<Void, Never>] = [:]
    public private(set) var localPort: UInt16?

    public init(remotePort: Int, openChannel: @escaping TunnelChannelOpener) {
        self.remotePort = remotePort
        self.openChannel = openChannel
    }

    public var activeConnectionCount: Int {
        bridges.count
    }

    public func start(preferredLocalPort: UInt16? = nil) async throws -> UInt16 {
        await stop()
        if let preferredLocalPort, let port = try? await listen(on: preferredLocalPort) {
            return port
        }
        return try await listen(on: nil)
    }

    public func stop() async {
        let events = listenerEvents
        listener?.cancel()
        listener = nil
        listenerEvents = nil
        localPort = nil
        for bridge in bridges.values {
            bridge.cancel()
        }
        bridges.removeAll()
        await events?.waitUntilClosed()
    }

    private func listen(on port: UInt16?) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        )
        let listener = try NWListener(using: parameters)
        let listenerID = ObjectIdentifier(listener)
        let events = TunnelListenerEvents()
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.accept(connection, from: listenerID) }
        }
        self.listener = listener
        listenerEvents = events
        do {
            let boundPort = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    events.armReady(continuation)
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            events.resumeReady(with: listener.port.map { .success($0.rawValue) }
                                ?? .failure(TunnelPortForwarderError.listenerFailed("sem porta")))
                        case .failed(let error):
                            events.resumeReady(with: .failure(TunnelPortForwarderError.listenerFailed(error.localizedDescription)))
                            listener.cancel()
                        case .cancelled:
                            events.resumeReady(with: .failure(TunnelPortForwarderError.listenerCancelled))
                            events.markClosed()
                        default:
                            break
                        }
                    }
                    listener.start(queue: queue)
                }
            } onCancel: {
                listener.cancel()
            }
            localPort = boundPort
            return boundPort
        } catch {
            listener.cancel()
            if self.listener === listener {
                self.listener = nil
                listenerEvents = nil
            }
            await events.waitUntilClosed()
            throw error
        }
    }

    private func accept(_ connection: NWConnection, from source: ObjectIdentifier) {
        guard let listener, ObjectIdentifier(listener) == source else {
            connection.cancel()
            return
        }
        let id = UUID()
        let openChannel = openChannel
        let remotePort = remotePort
        let queue = queue
        bridges[id] = Task { [weak self] in
            await TunnelBridge.run(connection: connection, queue: queue) {
                try await openChannel(remotePort)
            }
            await self?.finish(id)
        }
    }

    private func finish(_ id: UUID) {
        bridges[id] = nil
    }
}

private final class TunnelListenerEvents: Sendable {
    private struct State {
        var ready: CheckedContinuation<UInt16, any Error>?
        var isClosed = false
        var closeWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func armReady(_ continuation: CheckedContinuation<UInt16, any Error>) {
        state.withLock { $0.ready = continuation }
    }

    func resumeReady(with result: Result<UInt16, any Error>) {
        let pending = state.withLock { value in
            defer { value.ready = nil }
            return value.ready
        }
        pending?.resume(with: result)
    }

    func markClosed() {
        let waiters = state.withLock { value in
            value.isClosed = true
            defer { value.closeWaiters.removeAll() }
            return value.closeWaiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilClosed() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isClosed = state.withLock { value in
                if !value.isClosed {
                    value.closeWaiters.append(continuation)
                }
                return value.isClosed
            }
            if isClosed {
                continuation.resume()
            }
        }
    }
}
