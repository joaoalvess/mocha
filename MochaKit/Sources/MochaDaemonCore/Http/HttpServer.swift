import Foundation
import Network

public actor HttpServer {
    private struct ActiveConnection {
        let io: ConnectionIO
        let task: Task<Void, Never>
    }

    public nonisolated let binding: HttpBinding
    public private(set) var port: UInt16?

    private let router: HttpRouter
    private let configuration: HttpServerConfiguration
    private let queue = DispatchQueue(label: "com.joaoalves.mocha.http")
    private var listener: NWListener?
    private var listenerEvents: Task<Void, Never>?
    private var acceptLoop: Task<Void, Never>?
    private var readiness: CheckedContinuation<Void, any Error>?
    private var listenerCancellation: CheckedContinuation<Void, Never>?
    private var connections: [UUID: ActiveConnection] = [:]

    public init(
        binding: HttpBinding,
        router: HttpRouter,
        configuration: HttpServerConfiguration = HttpServerConfiguration()
    ) {
        self.binding = binding
        self.router = router
        self.configuration = configuration
    }

    deinit {
        listener?.cancel()
        listenerEvents?.cancel()
        acceptLoop?.cancel()
    }

    public func start() async throws {
        guard listener == nil else { throw HttpServerError.alreadyStarted }
        let parameters = try makeParameters()
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch let error as NWError {
            throw HttpServerError.listenerFailed(error)
        }
        let (states, stateContinuation) = AsyncStream.makeStream(of: NWListener.State.self)
        let (incoming, incomingContinuation) = AsyncStream.makeStream(of: NWConnection.self)
        listener.stateUpdateHandler = { state in
            stateContinuation.yield(state)
            if case .cancelled = state {
                stateContinuation.finish()
                incomingContinuation.finish()
            }
        }
        listener.newConnectionHandler = { connection in
            incomingContinuation.yield(connection)
        }
        self.listener = listener
        listenerEvents = Task { [weak self] in
            for await state in states {
                await self?.listenerStateChanged(state)
            }
        }
        acceptLoop = Task { [weak self] in
            for await connection in incoming {
                await self?.accept(connection)
            }
        }
        do {
            try await withCheckedThrowingContinuation { continuation in
                readiness = continuation
                listener.start(queue: queue)
            }
            try completeBinding(of: listener)
        } catch {
            await stop()
            throw error
        }
        httpLogger.info("listening on \(self.binding.description, privacy: .public)")
    }

    public func stop() async {
        guard let listener else { return }
        self.listener = nil
        readiness?.resume(throwing: CancellationError())
        readiness = nil
        await withCheckedContinuation { continuation in
            listenerCancellation = continuation
            listener.cancel()
        }
        await acceptLoop?.value
        acceptLoop = nil
        listenerEvents = nil
        let active = Array(connections.values)
        connections.removeAll()
        for connection in active {
            connection.task.cancel()
            connection.io.cancel()
        }
        for connection in active {
            await connection.task.value
        }
        removeSocketFile()
        port = nil
        httpLogger.info("stopped \(self.binding.description, privacy: .public)")
    }

    private func makeParameters() throws -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        switch binding {
        case .loopback(let port):
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
            parameters.allowLocalEndpointReuse = true
        case .unixSocket(let path):
            try Self.prepareSocketPath(path)
            parameters.requiredLocalEndpoint = .unix(path: path)
        }
        return parameters
    }

    private func completeBinding(of listener: NWListener) throws {
        switch binding {
        case .loopback:
            port = listener.port?.rawValue
        case .unixSocket(let path):
            guard chmod(path, 0o600) == 0 else { throw HttpServerError.socketPermissionsFailed(errno) }
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            readiness?.resume()
            readiness = nil
        case .failed(let error), .waiting(let error):
            httpLogger.error("listener on \(self.binding.description, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            readiness?.resume(throwing: HttpServerError.listenerFailed(error))
            readiness = nil
        case .cancelled:
            readiness?.resume(throwing: CancellationError())
            readiness = nil
            listenerCancellation?.resume()
            listenerCancellation = nil
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let io = ConnectionIO(connection: connection)
        guard listener != nil else {
            io.cancel()
            return
        }
        let id = UUID()
        let handler = HttpConnection(io: io, router: router, configuration: configuration)
        io.start(on: queue)
        let task = Task { [weak self] in
            await handler.run()
            await self?.connectionFinished(id)
        }
        connections[id] = ActiveConnection(io: io, task: task)
    }

    private func connectionFinished(_ id: UUID) {
        connections[id] = nil
    }

    private func removeSocketFile() {
        guard case .unixSocket(let path) = binding, Self.isSocket(atPath: path) else { return }
        unlink(path)
    }

    private static func prepareSocketPath(_ path: String) throws {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw HttpServerError.socketPathTooLong(path)
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK, unlink(path) == 0 else {
            throw HttpServerError.socketPathOccupied(path)
        }
    }

    private static func isSocket(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFSOCK
    }
}
