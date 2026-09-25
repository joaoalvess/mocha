import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct WebSocketRawTests {
    private static func echoRouter(options: WebSocketOptions = WebSocketOptions()) -> HttpRouter {
        var router = HttpRouter()
        router.webSocket("/ws", options: options) { _, socket in
            for await message in socket.messages {
                if case .text(let text) = message {
                    try? await socket.send(text: "echo:" + text)
                }
            }
        }
        return router
    }

    private static func expectClose(_ client: RawClient, code: UInt16) async throws {
        let frame = try await client.readFrame()
        #expect(frame.opcode == 0x8)
        #expect(frame.closeCode == code)
        #expect(!frame.isMasked)
        #expect(try await client.readToEnd().isEmpty)
        #expect(await client.receivedError == nil)
    }

    @Test func handshakeReturnsRFC6455AcceptValue() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, head) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            #expect(head.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
            #expect(head.contains("\r\nUpgrade: websocket\r\n"))
            #expect(head.contains("\r\nConnection: Upgrade\r\n"))
            #expect(head.contains("\r\nSec-WebSocket-Accept: \(RawClient.sampleAccept)\r\n"))
            #expect(!head.contains("Sec-WebSocket-Extensions"))
        }
    }

    @Test func fragmentedTextIsReassembled() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            let text = Array("Hello, wörld".utf8)
            let splitInsideScalar = text.firstIndex(of: 0xC3).map { $0 + 1 } ?? 0
            try await client.send(RawFrameBuilder.frame(opcode: 0x1, payload: Array(text[..<3]), isFinal: false))
            try await client.send(RawFrameBuilder.frame(opcode: 0x0, payload: Array(text[3..<splitInsideScalar]), isFinal: false))
            try await client.send(RawFrameBuilder.frame(opcode: 0x0, payload: Array(text[splitInsideScalar...]), isFinal: true))
            let reply = try await client.readFrame()
            #expect(reply.opcode == 0x1)
            #expect(reply.isFinal)
            #expect(!reply.isMasked)
            #expect(reply.text == "echo:Hello, wörld")
        }
    }

    @Test func pingIsAnsweredWithPong() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.frame(opcode: 0x9, payload: Array("mocha".utf8)))
            let pong = try await client.readFrame()
            #expect(pong.opcode == 0xA)
            #expect(pong.text == "mocha")
            #expect(!pong.isMasked)
        }
    }

    @Test func pingBetweenFragmentsIsAnsweredBeforeTheMessage() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(
                RawFrameBuilder.frame(opcode: 0x1, payload: Array("ab".utf8), isFinal: false)
                    + RawFrameBuilder.frame(opcode: 0x9, payload: Array("p1".utf8))
                    + RawFrameBuilder.frame(opcode: 0x0, payload: Array("cd".utf8), isFinal: true)
            )
            let pong = try await client.readFrame()
            #expect(pong.opcode == 0xA)
            #expect(pong.text == "p1")
            let reply = try await client.readFrame()
            #expect(reply.text == "echo:abcd")
        }
    }

    @Test func unmaskedFrameIsRejectedWith1002() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.frame(opcode: 0x1, payload: Array("hi".utf8), mask: nil))
            try await Self.expectClose(client, code: 1002)
        }
    }

    @Test func invalidUTF8TextIsRejectedWith1007() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.frame(opcode: 0x1, payload: [0x61, 0xC3, 0x28]))
            try await Self.expectClose(client, code: 1007)
        }
    }

    @Test func fragmentedMessageAboveLimitIsRejectedWith1009() async throws {
        try await withRunningServer(Self.echoRouter(options: WebSocketOptions(maxMessageSize: 16))) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.text("0123456789", isFinal: false))
            try await client.send(RawFrameBuilder.frame(opcode: 0x0, payload: Array("0123456789".utf8)))
            try await Self.expectClose(client, code: 1009)
        }
    }

    @Test func controlFrameAbove125BytesIsRejectedWith1002() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.frame(opcode: 0x9, payload: [UInt8](repeating: 0x70, count: 126)))
            try await Self.expectClose(client, code: 1002)
        }
    }

    @Test func continuationWithoutStartIsRejectedWith1002() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.frame(opcode: 0x0, payload: Array("x".utf8)))
            try await Self.expectClose(client, code: 1002)
        }
    }

    @Test func clientCloseIsEchoedAndConnectionEnds() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let (client, _) = try await RawClient.openWebSocket(port: port, path: "/ws")
            defer { client.cancel() }
            try await client.send(RawFrameBuilder.close(code: 4000, reason: "bye"))
            try await Self.expectClose(client, code: 4000)
        }
    }
}
