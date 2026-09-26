import Foundation
import MochaDaemonCore
import MochaProtocol

public enum TestGatewayServerError: Error, Sendable {
    case notStarted
}

public actor TestGatewayServer {
    public static let webSocketPath = "/v1"
    public static let badGatewayPath = "/down"
    public static let hostName = "MacBook-Teste"
    public static let daemonVersion = "0.1.0-test"

    public nonisolated let hub: TestGatewayHub
    private let automaticPong: Bool
    private var server: HttpServer?
    public private(set) var port: UInt16?

    public init(automaticPong: Bool = true) {
        self.automaticPong = automaticPong
        hub = TestGatewayHub()
    }

    public func start() async throws {
        let server = HttpServer(binding: .loopback(port: port ?? 0), router: makeRouter())
        try await server.start()
        self.server = server
        port = await server.port
    }

    public func stop() async {
        await server?.stop()
        server = nil
    }

    public func url(path: String = TestGatewayServer.webSocketPath) throws -> URL {
        guard let port, let url = URL(string: "ws://127.0.0.1:\(port)\(path)") else {
            throw TestGatewayServerError.notStarted
        }
        return url
    }

    private func makeRouter() -> HttpRouter {
        var router = HttpRouter()
        let hub = hub
        router.webSocket(Self.webSocketPath, options: WebSocketOptions(automaticPong: automaticPong)) { _, socket in
            await hub.serve(socket)
        }
        router.route(.get, Self.badGatewayPath) { _ in
            HttpResponse(status: HttpStatus(code: 502))
        }
        return router
    }
}

public actor TestGatewayHub {
    public private(set) var hellos: [HelloPayload] = []
    public private(set) var received: [ClientEnvelope] = []
    public private(set) var tokens: Set<String> = []
    public private(set) var connectionCount = 0
    private var pairingCodes: Set<String> = []
    private var sockets: [UUID: WebSocketConnection] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func issuePairingCode() -> String {
        let code = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        pairingCodes.insert(code)
        return code
    }

    public func register(token: String) {
        tokens.insert(token)
    }

    public func revokeAll() async {
        tokens.removeAll()
        for socket in sockets.values {
            try? await send(.error(code: .unauthorized, message: "Este aparelho foi removido do Mac."), id: nil, to: socket)
            await socket.close(code: .policyViolation, reason: "")
        }
    }

    func serve(_ socket: WebSocketConnection) async {
        let id = UUID()
        connectionCount += 1
        sockets[id] = socket
        var isAuthenticated = false
        for await message in socket.messages {
            guard case .text(let text) = message, let envelope = try? decoder.decode(ClientEnvelope.self, from: Data(text.utf8)) else {
                continue
            }
            received.append(envelope)
            if isAuthenticated {
                await handle(envelope, from: socket)
            } else {
                isAuthenticated = await authenticate(envelope, socket: socket)
            }
        }
        sockets[id] = nil
    }

    private func authenticate(_ envelope: ClientEnvelope, socket: WebSocketConnection) async -> Bool {
        guard case .hello(let hello) = envelope.message else {
            try? await send(.error(code: .unauthorized, message: "A primeira mensagem precisa ser hello."), id: envelope.id, to: socket)
            await socket.close(code: .policyViolation, reason: "")
            return false
        }
        hellos.append(hello)
        var issuedToken: String?
        if let code = hello.pairingCode {
            guard pairingCodes.remove(code) != nil else {
                try? await send(.error(code: .pairingExpired, message: "O código de pareamento venceu ou já foi usado."), id: envelope.id, to: socket)
                return false
            }
            let token = UUID().uuidString
            tokens.insert(token)
            issuedToken = token
        } else if let token = hello.deviceToken {
            guard tokens.contains(token) else {
                try? await send(.error(code: .unauthorized, message: "Aparelho não autorizado. Pareie de novo."), id: envelope.id, to: socket)
                return false
            }
        } else {
            try? await send(.error(code: .invalidPayload, message: "Mensagem inválida."), id: envelope.id, to: socket)
            return false
        }
        let host = HostInfo(hostName: TestGatewayServer.hostName, daemonVersion: TestGatewayServer.daemonVersion, herdrConnected: true)
        try? await send(
            .helloOk(HelloOkPayload(host: host, deviceId: "test-device", deviceToken: issuedToken, preferences: DevicePreferences())),
            id: envelope.id,
            to: socket
        )
        try? await send(.tree(workspaces: []), id: envelope.id, to: socket)
        return true
    }

    private func handle(_ envelope: ClientEnvelope, from socket: WebSocketConnection) async {
        switch envelope.message {
        case .hello:
            try? await send(.error(code: .invalidPayload, message: "Esta conexão já fez hello."), id: envelope.id, to: socket)
        case .ping:
            try? await send(.pong, id: envelope.id, to: socket)
        case .unpair:
            try? await send(.ack(), id: envelope.id, to: socket)
            tokens.removeAll()
            await socket.close(code: .normalClosure, reason: "")
        default:
            try? await send(.ack(), id: envelope.id, to: socket)
        }
    }

    private func send(_ message: ServerMessage, id: String?, to socket: WebSocketConnection) async throws {
        let data = try encoder.encode(ServerEnvelope(id: id, message: message))
        try await socket.send(text: String(decoding: data, as: UTF8.self))
    }
}
