import Foundation
import Network
import Testing

enum RawClientError: Error {
    case unexpectedEnd
    case connectionFailed(NWError)
    case notReady
}

struct RawFrame: Sendable, Equatable {
    let isFinal: Bool
    let opcode: UInt8
    let isMasked: Bool
    let payload: [UInt8]

    var closeCode: UInt16? {
        guard opcode == 0x8, payload.count >= 2 else { return nil }
        return UInt16(payload[0]) << 8 | UInt16(payload[1])
    }

    var text: String {
        String(decoding: payload, as: UTF8.self)
    }
}

enum RawFrameBuilder {
    static let defaultMask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]

    static func frame(opcode: UInt8, payload: [UInt8], isFinal: Bool = true, mask: [UInt8]? = defaultMask) -> [UInt8] {
        var bytes: [UInt8] = [(isFinal ? 0x80 : 0x00) | opcode]
        let maskBit: UInt8 = mask == nil ? 0x00 : 0x80
        if payload.count < 126 {
            bytes.append(maskBit | UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            bytes.append(maskBit | 126)
            bytes.append(UInt8(truncatingIfNeeded: payload.count >> 8))
            bytes.append(UInt8(truncatingIfNeeded: payload.count))
        } else {
            bytes.append(maskBit | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: payload.count >> shift))
            }
        }
        if let mask {
            bytes.append(contentsOf: mask)
            bytes.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        } else {
            bytes.append(contentsOf: payload)
        }
        return bytes
    }

    static func text(_ text: String, isFinal: Bool = true) -> [UInt8] {
        frame(opcode: 0x1, payload: Array(text.utf8), isFinal: isFinal)
    }

    static func close(code: UInt16, reason: String = "") -> [UInt8] {
        frame(opcode: 0x8, payload: [UInt8(code >> 8), UInt8(code & 0xFF)] + Array(reason.utf8))
    }
}

actor RawClient {
    private struct Chunk: Sendable {
        let bytes: Data
        let isEnd: Bool
        let error: NWError?
    }

    static let sampleKey = "dGhlIHNhbXBsZSBub25jZQ=="
    static let sampleAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

    private let connection: NWConnection
    private var buffer: [UInt8] = []
    private var ended = false
    private(set) var receivedError: NWError?

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func connect(to endpoint: NWEndpoint) async throws -> RawClient {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let (states, continuation) = AsyncStream.makeStream(of: NWConnection.State.self)
        connection.stateUpdateHandler = { continuation.yield($0) }
        connection.start(queue: DispatchQueue(label: "com.joaoalves.mocha.tests.raw-client"))
        do {
            try await withTimeout {
                for await state in states {
                    switch state {
                    case .ready:
                        return
                    case .failed(let error), .waiting(let error):
                        throw RawClientError.connectionFailed(error)
                    case .cancelled:
                        throw RawClientError.notReady
                    default:
                        continue
                    }
                }
                throw RawClientError.notReady
            }
        } catch {
            connection.cancel()
            throw error
        }
        return RawClient(connection: connection)
    }

    static func openWebSocket(port: UInt16, path: String) async throws -> (client: RawClient, head: String) {
        let client = try await connect(to: loopbackEndpoint(port))
        try await client.send(
            "GET \(path) HTTP/1.1\r\n"
                + "Host: 127.0.0.1:\(port)\r\n"
                + "Upgrade: websocket\r\n"
                + "Connection: keep-alive, Upgrade\r\n"
                + "Sec-WebSocket-Key: \(sampleKey)\r\n"
                + "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        return (client, try await client.readHead())
    }

    func send(_ text: String) async throws {
        try await send(Array(text.utf8))
    }

    func send(_ bytes: [UInt8]) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func readHead() async throws -> String {
        while true {
            if let end = indexOfHeadEnd() {
                let head = Array(buffer[..<(end + 4)])
                buffer.removeFirst(end + 4)
                return String(decoding: head, as: UTF8.self)
            }
            try await fill()
        }
    }

    func readExactly(_ count: Int) async throws -> [UInt8] {
        while buffer.count < count {
            try await fill()
        }
        let bytes = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return bytes
    }

    func readToEnd() async throws -> [UInt8] {
        while !ended {
            try await fill()
        }
        let bytes = buffer
        buffer.removeAll()
        return bytes
    }

    func readFrame() async throws -> RawFrame {
        let header = try await readExactly(2)
        var length = Int(header[1] & 0x7F)
        if length == 126 {
            let extended = try await readExactly(2)
            length = Int(extended[0]) << 8 | Int(extended[1])
        } else if length == 127 {
            let extended = try await readExactly(8)
            length = extended.reduce(0) { $0 << 8 | Int($1) }
        }
        let isMasked = header[1] & 0x80 != 0
        let mask = isMasked ? try await readExactly(4) : []
        var payload = try await readExactly(length)
        if isMasked {
            payload = payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
        }
        return RawFrame(isFinal: header[0] & 0x80 != 0, opcode: header[0] & 0x0F, isMasked: isMasked, payload: payload)
    }

    nonisolated func cancel() {
        connection.cancel()
    }

    private func indexOfHeadEnd() -> Int? {
        guard buffer.count >= 4 else { return nil }
        for index in 0...(buffer.count - 4)
        where buffer[index] == 13 && buffer[index + 1] == 10 && buffer[index + 2] == 13 && buffer[index + 3] == 10 {
            return index
        }
        return nil
    }

    private func fill() async throws {
        guard !ended else { throw RawClientError.unexpectedEnd }
        let chunk = try await receiveChunk()
        buffer.append(contentsOf: chunk.bytes)
        if let error = chunk.error {
            receivedError = error
        }
        if chunk.isEnd {
            ended = true
        }
    }

    private func receiveChunk() async throws -> Chunk {
        let connection = self.connection
        return try await withTimeout {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
                        continuation.resume(returning: Chunk(bytes: content ?? Data(), isEnd: isComplete || error != nil, error: error))
                    }
                }
            } onCancel: {
                connection.cancel()
            }
        }
    }
}
