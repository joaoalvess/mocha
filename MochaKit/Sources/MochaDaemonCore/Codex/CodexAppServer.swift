import Foundation

enum CodexAppServerError: Error, Sendable, Equatable {
    case unavailable
    case rejected(String)
    case invalidResponse
}

struct CodexServerEvent: Sendable {
    let connectionId: UUID
    let method: String
    let params: OrderedJSON
    let requestId: OrderedJSON?
}

actor CodexAppServer {
    nonisolated let events: AsyncStream<CodexServerEvent>

    private let continuation: AsyncStream<CodexServerEvent>.Continuation
    private let socketPath: String
    private let requestTimeout: Duration
    private var socket: CodexSocket?
    private var connectionId: UUID?
    private var receiver: Task<Void, Never>?
    private var nextId = 1
    private var waiters: [Int: CheckedContinuation<OrderedJSON, any Error>] = [:]

    init(socketPath: String, requestTimeout: Duration = .seconds(30)) {
        self.socketPath = socketPath
        self.requestTimeout = requestTimeout
        (events, continuation) = AsyncStream.makeStream(of: CodexServerEvent.self)
    }

    var isConnected: Bool { socket != nil }

    @discardableResult
    func connect() async throws -> OrderedJSON {
        guard socket == nil else { return .object([]) }
        let opened = try await CodexSocket.open(path: socketPath)
        let generation = UUID()
        socket = opened
        connectionId = generation
        receiver = Task { [weak self] in
            await self?.receive(on: opened, generation: generation)
        }
        do {
            let result = try await request("initialize", params: .object([
                .init("clientInfo", .object([.init("name", .string("mochad")), .init("version", .string(DaemonVersion.current))])),
                .init("capabilities", .object([.init("experimentalApi", .bool(true))])),
            ]))
            try await notify("initialized", params: .object([]))
            return result
        } catch {
            disconnect(generation: generation)
            throw error
        }
    }

    func shutdown() {
        receiver?.cancel()
        receiver = nil
        if let generation = connectionId { disconnect(generation: generation) }
        continuation.finish()
    }

    func request(_ method: String, params: OrderedJSON) async throws -> OrderedJSON {
        guard let socket, let generation = connectionId else { throw CodexAppServerError.unavailable }
        let id = nextId
        let timeout = requestTimeout
        nextId += 1
        let frame = OrderedJSON.object([
            .init("id", .number(String(id))),
            .init("method", .string(method)),
            .init("params", params),
        ]).compactSerialized()
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                do {
                    try await socket.send(frame)
                } catch {
                    await self?.fail(id: id, generation: generation, error: error)
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.fail(id: id, generation: generation, error: CodexAppServerError.unavailable)
            }
        }
    }

    func notify(_ method: String, params: OrderedJSON) async throws {
        guard let socket else { throw CodexAppServerError.unavailable }
        let frame = OrderedJSON.object([.init("method", .string(method)), .init("params", params)]).compactSerialized()
        try await socket.send(frame)
    }

    func respond(to requestId: OrderedJSON, on generation: UUID, result: OrderedJSON) async throws {
        guard connectionId == generation, let socket else { throw CodexAppServerError.unavailable }
        let frame = OrderedJSON.object([.init("id", requestId), .init("result", result)]).compactSerialized()
        try await socket.send(frame)
    }

    private func receive(on socket: CodexSocket, generation: UUID) async {
        do {
            while let text = try await socket.read() {
                guard connectionId == generation else { break }
                let message = try OrderedJSON.parse(Data(text.utf8))
                if let id = message["id"], let method = message["method"]?.stringValue {
                    continuation.yield(CodexServerEvent(
                        connectionId: generation, method: method, params: message["params"] ?? .object([]), requestId: id
                    ))
                } else if let id = message["id"], let number = id.numberValue, let value = Int(number) {
                    let waiter = waiters.removeValue(forKey: value)
                    if let error = message["error"] {
                        waiter?.resume(throwing: CodexAppServerError.rejected(error["message"]?.stringValue ?? "App Server recusou o pedido"))
                    } else if let result = message["result"] {
                        waiter?.resume(returning: result)
                    } else {
                        waiter?.resume(throwing: CodexAppServerError.invalidResponse)
                    }
                } else if let method = message["method"]?.stringValue {
                    continuation.yield(CodexServerEvent(
                        connectionId: generation, method: method, params: message["params"] ?? .object([]), requestId: nil
                    ))
                }
            }
        } catch {}
        disconnect(generation: generation)
    }

    private func fail(id: Int, generation: UUID, error: any Error) {
        guard connectionId == generation, let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.resume(throwing: error)
        disconnect(generation: generation)
    }

    private func disconnect(generation: UUID) {
        guard connectionId == generation else { return }
        socket?.close()
        socket = nil
        connectionId = nil
        receiver?.cancel()
        receiver = nil
        let pending = waiters
        waiters.removeAll()
        for waiter in pending.values { waiter.resume(throwing: CodexAppServerError.unavailable) }
        continuation.yield(CodexServerEvent(connectionId: generation, method: "mocha/disconnected", params: .object([]), requestId: nil))
    }
}

extension OrderedJSON {
    var numberValue: String? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        numberValue.flatMap(Int.init)
    }

    var doubleValue: Double? {
        numberValue.flatMap(Double.init)
    }
}
