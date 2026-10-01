import CryptoKit
import Foundation
import MochaDaemonCore
import Network

public struct FakeCodexRequest: Sendable {
    public let connection: Int
    public let id: OrderedJSON?
    public let method: String
    public let params: OrderedJSON

    public func string(_ key: String) -> String? {
        params[key]?.stringValue
    }
}

public struct FakeCodexResponse: Sendable {
    public let connection: Int
    public let id: OrderedJSON
    public let result: OrderedJSON?
    public let error: OrderedJSON?
}

public enum FakeCodexReply: Sendable {
    case result(OrderedJSON)
    case error(code: Int, message: String)
    case noReply
}

public actor FakeCodexAppServer {
    public static let version = "0.159.2"
    public static let methodNotFound = -32601

    public nonisolated let socketPath: String

    private let queue = DispatchQueue(label: "com.joaoalves.mocha.tests.fake-codex")
    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var nextConnection = 0
    private var handlers: [String: @Sendable (FakeCodexRequest) -> FakeCodexReply] = [:]
    private var recorded: [FakeCodexRequest] = []
    private var responses: [FakeCodexResponse] = []

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public static func temporaryDirectory() throws -> URL {
        let directory = URL(filePath: "/tmp", directoryHint: .isDirectory)
            .appending(path: "mcx-\(UUID().uuidString.prefix(8).lowercased())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func start() async throws {
        guard listener == nil else { return }
        unlink(socketPath)
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .unix(path: socketPath)
        let listener = try NWListener(using: parameters)
        let (states, stateContinuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { state in
            stateContinuation.yield(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
        for await state in states {
            switch state {
            case .ready:
                listener.stateUpdateHandler = nil
                return
            case .failed(let error), .waiting(let error):
                listener.cancel()
                self.listener = nil
                throw error
            case .cancelled:
                self.listener = nil
                throw CancellationError()
            default:
                continue
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        unlink(socketPath)
    }

    public func setHandler(_ method: String, _ handler: (@Sendable (FakeCodexRequest) -> FakeCodexReply)?) {
        handlers[method] = handler
    }

    public func reply(to method: String, with reply: FakeCodexReply) {
        handlers[method] = { _ in reply }
    }

    public func notify(_ method: String, params: OrderedJSON) {
        broadcast(.object([.init("method", .string(method)), .init("params", params)]))
    }

    public func serverRequest(_ method: String, id: Int, params: OrderedJSON) {
        broadcast(.object([.init("id", .number(String(id))), .init("method", .string(method)), .init("params", params)]))
    }

    public func send(_ message: OrderedJSON) {
        broadcast(message)
    }

    public var requests: [FakeCodexRequest] {
        recorded
    }

    public func requests(method: String) -> [FakeCodexRequest] {
        recorded.filter { $0.method == method }
    }

    public var clientResponses: [FakeCodexResponse] {
        responses
    }

    public var openConnections: Int {
        connections.count
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        nextConnection += 1
        let id = nextConnection
        connections[id] = connection
        connection.start(queue: queue)
        Task { await self.serve(id, connection) }
    }

    private func serve(_ id: Int, _ connection: NWConnection) async {
        var buffer = Data()
        let boundary = Data("\r\n\r\n".utf8)
        while buffer.range(of: boundary) == nil {
            let chunk = await Self.receive(connection)
            buffer.append(chunk.bytes)
            if chunk.isEnd, buffer.range(of: boundary) == nil {
                drop(id)
                return
            }
        }
        guard let range = buffer.range(of: boundary),
              let key = Self.webSocketKey(in: String(decoding: buffer[..<range.lowerBound], as: UTF8.self)) else {
            drop(id)
            return
        }
        buffer.removeSubrange(..<range.upperBound)
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        let handshake = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        connection.send(content: Data(handshake.utf8), completion: .idempotent)
        var fragments = Data()
        while true {
            while let frame = Self.takeFrame(from: &buffer) {
                switch frame.opcode {
                case 0, 1:
                    fragments.append(frame.payload)
                    if frame.isFinal {
                        handle(String(decoding: fragments, as: UTF8.self), connection: id)
                        fragments.removeAll()
                    }
                case 8:
                    drop(id)
                    return
                case 9:
                    connection.send(content: Self.frame(frame.payload, opcode: 10), completion: .idempotent)
                default:
                    break
                }
            }
            let chunk = await Self.receive(connection)
            buffer.append(chunk.bytes)
            if chunk.isEnd {
                drop(id)
                return
            }
        }
    }

    private func handle(_ text: String, connection: Int) {
        guard let message = try? OrderedJSON.parse(Data(text.utf8)) else { return }
        guard let method = message["method"]?.stringValue else {
            if let id = message["id"] {
                responses.append(FakeCodexResponse(connection: connection, id: id, result: message["result"], error: message["error"]))
            }
            return
        }
        let request = FakeCodexRequest(connection: connection, id: message["id"], method: method, params: message["params"] ?? .object([]))
        recorded.append(request)
        guard let id = request.id else { return }
        switch handlers[method]?(request) ?? Self.defaultReply(request) {
        case .result(let result):
            send(.object([.init("id", id), .init("result", result)]), to: connection)
        case .error(let code, let text):
            let error = OrderedJSON.object([.init("code", .number(String(code))), .init("message", .string(text))])
            send(.object([.init("error", error), .init("id", id)]), to: connection)
        case .noReply:
            break
        }
    }

    private func broadcast(_ message: OrderedJSON) {
        for id in connections.keys {
            send(message, to: id)
        }
    }

    private func send(_ message: OrderedJSON, to id: Int) {
        connections[id]?.send(content: Self.frame(Data(message.compactSerialized().utf8), opcode: 1), completion: .idempotent)
    }

    private func drop(_ id: Int) {
        connections.removeValue(forKey: id)?.cancel()
    }

    private static func defaultReply(_ request: FakeCodexRequest) -> FakeCodexReply {
        switch request.method {
        case "initialize":
            return .result(.object([
                .init("userAgent", .string("mochad/\(version) (Mac OS 27.0; arm64)")),
                .init("codexHome", .string("/Users/dev/.codex")),
                .init("platformFamily", .string("unix")),
                .init("platformOs", .string("macos")),
            ]))
        case "thread/loaded/list":
            return .result(.object([.init("data", .array([])), .init("nextCursor", .null)]))
        case "thread/resume", "turn/start", "turn/interrupt":
            return .result(.object([]))
        case "thread/unsubscribe":
            return .result(.object([.init("status", .string("unsubscribed"))]))
        default:
            return .error(code: methodNotFound, message: "Method not found: \(request.method)")
        }
    }

    private static func webSocketKey(in head: String) -> String? {
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "sec-websocket-key" {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func takeFrame(from buffer: inout Data) -> (opcode: UInt8, isFinal: Bool, payload: Data)? {
        let bytes = [UInt8](buffer.prefix(14))
        guard bytes.count >= 2 else { return nil }
        let masked = bytes[1] & 0x80 != 0
        var length = Int(bytes[1] & 0x7f)
        var offset = 2
        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = Int(bytes[2]) << 8 | Int(bytes[3])
            offset = 4
        } else if length == 127 {
            guard bytes.count >= 10 else { return nil }
            length = bytes[2..<10].reduce(0) { ($0 << 8) | Int($1) }
            offset = 10
        }
        let maskLength = masked ? 4 : 0
        guard buffer.count >= offset + maskLength + length else { return nil }
        let start = buffer.startIndex
        let mask = [UInt8](buffer[(start + offset)..<(start + offset + maskLength)])
        let raw = [UInt8](buffer[(start + offset + maskLength)..<(start + offset + maskLength + length)])
        let payload = masked ? Data(raw.enumerated().map { $0.element ^ mask[$0.offset & 3] }) : Data(raw)
        buffer.removeSubrange(start..<(start + offset + maskLength + length))
        return (bytes[0] & 0x0f, bytes[0] & 0x80 != 0, payload)
    }

    private static func frame(_ payload: Data, opcode: UInt8) -> Data {
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= Int(UInt16.max) {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        } else {
            frame.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xff))
            }
        }
        frame.append(payload)
        return frame
    }

    private static func receive(_ connection: NWConnection) async -> (bytes: Data, isEnd: Bool) {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { content, _, isComplete, error in
                continuation.resume(returning: (content ?? Data(), isComplete || error != nil))
            }
        }
    }
}
