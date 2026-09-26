import Foundation
import Network

public enum LocalControlServerError: Error, Sendable, Equatable {
    case alreadyStarted
    case socketPathTooLong(String)
    case socketPathOccupied(String)
    case listenerFailed(NWError)
    case socketPermissionsFailed(Int32)
}

public actor LocalControlServer {
    private struct ActiveConnection {
        let io: ConnectionIO
        let task: Task<Void, Never>
    }

    public nonisolated let socketPath: String

    private let control: LocalControl
    private let configuration: HttpServerConfiguration
    private let queue = DispatchQueue(label: "com.joaoalves.mocha.local")
    private var listener: NWListener?
    private var acceptLoop: Task<Void, Never>?
    private var connections: [UUID: ActiveConnection] = [:]

    public init(socketPath: String, control: LocalControl, configuration: HttpServerConfiguration = HttpServerConfiguration()) {
        self.socketPath = socketPath
        self.control = control
        self.configuration = configuration
    }

    public func start() async throws {
        guard listener == nil else { throw LocalControlServerError.alreadyStarted }
        try prepareSocketPath()
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .unix(path: socketPath)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch let error as NWError {
            throw LocalControlServerError.listenerFailed(error)
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
        acceptLoop = Task { [weak self] in
            for await connection in incoming {
                await self?.accept(connection)
            }
        }
        listener.start(queue: queue)
        do {
            try await Self.waitUntilReady(states)
            guard chmod(socketPath, 0o600) == 0 else { throw LocalControlServerError.socketPermissionsFailed(errno) }
        } catch {
            await stop()
            throw error
        }
        localControlLogger.info("listening on unix:\(self.socketPath, privacy: .public)")
    }

    public func stop() async {
        guard let listener else { return }
        self.listener = nil
        listener.cancel()
        await acceptLoop?.value
        acceptLoop = nil
        let active = Array(connections.values)
        connections.removeAll()
        for connection in active {
            connection.task.cancel()
            connection.io.cancel()
        }
        for connection in active {
            await connection.task.value
        }
        if Self.isSocket(atPath: socketPath) {
            unlink(socketPath)
        }
    }

    private static func waitUntilReady(_ states: AsyncStream<NWListener.State>) async throws {
        for await state in states {
            switch state {
            case .ready:
                return
            case .failed(let error), .waiting(let error):
                throw LocalControlServerError.listenerFailed(error)
            case .cancelled:
                throw CancellationError()
            case .setup:
                continue
            @unknown default:
                continue
            }
        }
        throw CancellationError()
    }

    private func accept(_ connection: NWConnection) {
        let io = ConnectionIO(connection: connection)
        guard listener != nil else {
            io.cancel()
            return
        }
        let id = UUID()
        let control = control
        let configuration = configuration
        io.start(on: queue)
        let task = Task { [weak self] in
            let router = await control.makeRouter()
            await HttpConnection(io: io, router: router, configuration: configuration).run()
            await self?.connectionFinished(id)
        }
        connections[id] = ActiveConnection(io: io, task: task)
    }

    private func connectionFinished(_ id: UUID) {
        connections[id] = nil
    }

    private func prepareSocketPath() throws {
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw LocalControlServerError.socketPathTooLong(socketPath)
        }
        var info = stat()
        guard lstat(socketPath, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK, unlink(socketPath) == 0 else {
            throw LocalControlServerError.socketPathOccupied(socketPath)
        }
    }

    private static func isSocket(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFSOCK
    }
}
