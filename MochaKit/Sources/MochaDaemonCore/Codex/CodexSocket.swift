import CryptoKit
import Foundation
import Network
import Synchronization

enum CodexSocketError: Error, Sendable {
    case unavailable
    case invalidHandshake
    case invalidFrame
    case messageTooLarge
}

actor CodexSocket {
    private struct Chunk: Sendable {
        let data: Data
        let ended: Bool
    }

    private final class Ready: Sendable {
        private let pending: Mutex<CheckedContinuation<Void, any Error>?>

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            pending = Mutex(continuation)
        }

        func resume(_ result: Result<Void, any Error>) {
            pending.withLock { continuation in
                continuation?.resume(with: result)
                continuation = nil
            }
        }
    }

    private static let maxMessageSize = 16 << 20
    private let connection: NWConnection
    private var buffer = Data()

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func open(path: String) async throws -> CodexSocket {
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let ready = Ready(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        ready.resume(.success(()))
                    case .failed(let error), .waiting(let error):
                        ready.resume(.failure(error))
                        connection.cancel()
                    case .cancelled:
                        ready.resume(.failure(CodexSocketError.unavailable))
                    case .setup, .preparing:
                        break
                    @unknown default:
                        break
                    }
                }
                connection.start(queue: DispatchQueue(label: "com.joaoalves.mocha.codex.socket"))
            }
        } onCancel: {
            connection.cancel()
        }
        let socket = CodexSocket(connection: connection)
        do {
            try await socket.handshake()
            return socket
        } catch {
            connection.cancel()
            throw error
        }
    }

    nonisolated func close() {
        connection.cancel()
    }

    func send(_ text: String) async throws {
        try await write(frame: Data(text.utf8), opcode: 1)
    }

    func read() async throws -> String? {
        var fragments = Data()
        while true {
            guard let header = try await take(2) else { return nil }
            let first = header[0]
            let second = header[1]
            guard first & 0x70 == 0, second & 0x80 == 0 else { throw CodexSocketError.invalidFrame }
            var length = Int(second & 0x7f)
            if length == 126 {
                guard let bytes = try await take(2) else { return nil }
                length = Int(bytes[0]) << 8 | Int(bytes[1])
            } else if length == 127 {
                guard let bytes = try await take(8) else { return nil }
                let value = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                guard value <= Self.maxMessageSize else { throw CodexSocketError.messageTooLarge }
                length = Int(value)
            }
            guard length <= Self.maxMessageSize - fragments.count,
                  let payload = try await take(length) else { throw CodexSocketError.messageTooLarge }
            switch first & 0x0f {
            case 0, 1:
                fragments.append(payload)
                if first & 0x80 != 0 {
                    guard let text = String(data: fragments, encoding: .utf8) else { throw CodexSocketError.invalidFrame }
                    return text
                }
            case 8:
                return nil
            case 9:
                try await write(frame: payload, opcode: 10)
            case 10:
                break
            default:
                throw CodexSocketError.invalidFrame
            }
        }
    }

    private func handshake() async throws {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try await write(Data(request.utf8))
        let boundary = Data("\r\n\r\n".utf8)
        while buffer.range(of: boundary) == nil {
            guard buffer.count < 16_384, let chunk = await receive(), !chunk.ended else { throw CodexSocketError.invalidHandshake }
            buffer.append(chunk.data)
        }
        guard let range = buffer.range(of: boundary) else { throw CodexSocketError.invalidHandshake }
        let headers = String(decoding: buffer[..<range.upperBound], as: UTF8.self)
        buffer.removeSubrange(..<range.upperBound)
        let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
        let expected = Data(digest).base64EncodedString()
        guard headers.hasPrefix("HTTP/1.1 101 "), headers.lowercased().contains("sec-websocket-accept: \(expected.lowercased())") else {
            throw CodexSocketError.invalidHandshake
        }
    }

    private func write(frame payload: Data, opcode: UInt8) async throws {
        guard payload.count <= Self.maxMessageSize else { throw CodexSocketError.messageTooLarge }
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(UInt8(payload.count) | 0x80)
        } else if payload.count <= Int(UInt16.max) {
            frame.append(126 | 0x80)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        } else {
            frame.append(127 | 0x80)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xff))
            }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset & 3] })
        try await write(frame)
    }

    private func write(_ data: Data) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func take(_ count: Int) async throws -> Data? {
        while buffer.count < count {
            guard let chunk = await receive() else { return nil }
            buffer.append(chunk.data)
            if chunk.ended, buffer.count < count { return nil }
        }
        let data = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return data
    }

    private func receive() async -> Chunk? {
        if Task.isCancelled { return nil }
        let connection = self.connection
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, ended, error in
                    continuation.resume(returning: Chunk(data: data ?? Data(), ended: ended || error != nil))
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
