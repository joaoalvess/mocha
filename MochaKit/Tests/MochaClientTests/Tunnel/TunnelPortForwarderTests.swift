import Foundation
import Network
import Synchronization
import Testing
@testable import MochaClient

@Suite(.timeLimit(.minutes(1)))
struct TunnelPortForwarderTests {
    @Test func echoesBytesInBothDirectionsThroughTheFakeChannel() async throws {
        let recorder = OpenedPorts()
        let forwarder = TunnelPortForwarder(remotePort: 5173) { port in
            recorder.record(port)
            return EchoTunnelChannel()
        }
        let localPort = try await forwarder.start()
        let reply = try await LoopbackClient.exchange(port: localPort, sending: Data("olá, túnel".utf8))
        #expect(String(decoding: reply, as: UTF8.self) == "olá, túnel")
        #expect(recorder.ports == [5173])
        await forwarder.stop()
    }

    @Test func opensOneChannelPerAcceptedConnection() async throws {
        let recorder = OpenedPorts()
        let forwarder = TunnelPortForwarder(remotePort: 3000) { port in
            recorder.record(port)
            return EchoTunnelChannel()
        }
        let localPort = try await forwarder.start()
        async let first = LoopbackClient.exchange(port: localPort, sending: Data("um".utf8))
        async let second = LoopbackClient.exchange(port: localPort, sending: Data("dois".utf8))
        let replies = try await [first, second].map { String(decoding: $0, as: UTF8.self) }
        #expect(Set(replies) == ["um", "dois"])
        #expect(recorder.ports == [3000, 3000])
        await forwarder.stop()
    }

    @Test func servesTheStaticPageOverHTTP() async throws {
        let forwarder = TunnelPortForwarder(remotePort: 5173) { port in
            StaticPageTunnelChannel(title: "Portal do cliente", port: port)
        }
        let localPort = try await forwarder.start()
        let request = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(localPort)\r\n\r\n"
        let reply = String(decoding: try await LoopbackClient.exchange(port: localPort, sending: Data(request.utf8)), as: UTF8.self)
        #expect(reply.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(reply.contains("<title>Portal do cliente</title>"))
        #expect(reply.contains("localhost:5173"))
        await forwarder.stop()
    }

    @Test func servesTheStaticPageWhileTheClientKeepsItsSideOpen() async throws {
        let forwarder = TunnelPortForwarder(remotePort: 5173) { port in
            StaticPageTunnelChannel(title: "Portal do cliente", port: port)
        }
        let localPort = try await forwarder.start()
        let request = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(localPort)\r\n\r\n"
        let reply = String(
            decoding: try await LoopbackClient.exchange(port: localPort, sending: Data(request.utf8), closesAfterSending: false),
            as: UTF8.self
        )
        #expect(reply.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(reply.contains("<title>Portal do cliente</title>"))
        await forwarder.stop()
    }

    @Test func answersNotFoundOutsideTheRootPath() async throws {
        let forwarder = TunnelPortForwarder(remotePort: 5173) { _ in
            StaticPageTunnelChannel(html: "<title>x</title>")
        }
        let localPort = try await forwarder.start()
        let request = "GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let reply = String(decoding: try await LoopbackClient.exchange(port: localPort, sending: Data(request.utf8)), as: UTF8.self)
        #expect(reply.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        await forwarder.stop()
    }

    @Test func closesTheConnectionWhenTheChannelCannotOpen() async throws {
        let forwarder = TunnelPortForwarder(remotePort: 22) { _ in
            throw TunnelTestError.refused
        }
        let localPort = try await forwarder.start()
        let reply = try? await LoopbackClient.exchange(port: localPort, sending: Data("x".utf8))
        #expect(reply?.isEmpty ?? true)
        await forwarder.stop()
    }

    @Test func reopensOnThePreferredPortAfterStopping() async throws {
        let forwarder = TunnelPortForwarder(remotePort: 8080) { _ in EchoTunnelChannel() }
        let firstPort = try await forwarder.start()
        await forwarder.stop()
        #expect(await forwarder.localPort == nil)
        let secondPort = try await forwarder.start(preferredLocalPort: firstPort)
        #expect(secondPort == firstPort)
        let reply = try await LoopbackClient.exchange(port: secondPort, sending: Data("de novo".utf8))
        #expect(String(decoding: reply, as: UTF8.self) == "de novo")
        await forwarder.stop()
    }

    @Test func fallsBackToAnEphemeralPortWhenThePreferredOneIsTaken() async throws {
        let holder = TunnelPortForwarder(remotePort: 1) { _ in EchoTunnelChannel() }
        let takenPort = try await holder.start()
        let forwarder = TunnelPortForwarder(remotePort: 2) { _ in EchoTunnelChannel() }
        let port = try await forwarder.start(preferredLocalPort: takenPort)
        #expect(port != takenPort)
        await forwarder.stop()
        await holder.stop()
    }

    @Test func refusesConnectionsAfterStopping() async throws {
        let forwarder = TunnelPortForwarder(remotePort: 8080) { _ in EchoTunnelChannel() }
        let localPort = try await forwarder.start()
        await forwarder.stop()
        await #expect(throws: (any Error).self) {
            _ = try await LoopbackClient.exchange(port: localPort, sending: Data("x".utf8))
        }
    }
}

private enum TunnelTestError: Error {
    case refused
}

private final class OpenedPorts: Sendable {
    private let storage = Mutex<[Int]>([])

    func record(_ port: Int) {
        storage.withLock { $0.append(port) }
    }

    var ports: [Int] {
        storage.withLock { $0 }
    }
}

private struct EchoTunnelChannel: TunnelChannel {
    func exchange(_ body: @Sendable (any TunnelChannelInbound, any TunnelChannelOutbound) async throws -> Void) async throws {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        try await body(AsyncStreamTunnelInbound(stream), AsyncStreamTunnelOutbound(continuation))
    }
}

private enum LoopbackClient {
    static func exchange(port: UInt16, sending payload: Data, closesAfterSending: Bool = true) async throws -> Data {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: try #require(NWEndpoint.Port(rawValue: port)),
            using: .tcp
        )
        let queue = DispatchQueue(label: "tunnel-test-client")
        try await ready(connection, queue: queue)
        defer { connection.cancel() }
        try await connection.tunnelSend(payload)
        if closesAfterSending {
            try await connection.tunnelSendEndOfStream()
        }
        var received = Data()
        while true {
            let chunk = try await connection.tunnelReceive(maximumLength: 64 * 1024)
            if let data = chunk.data { received.append(data) }
            if chunk.isComplete { break }
        }
        return received
    }

    private static func ready(_ connection: NWConnection, queue: DispatchQueue) async throws {
        let gate = Mutex<CheckedContinuation<Void, any Error>?>(nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            gate.withLock { $0 = continuation }
            connection.stateUpdateHandler = { state in
                let pending: CheckedContinuation<Void, any Error>?
                switch state {
                case .ready:
                    pending = gate.withLock { value in defer { value = nil }; return value }
                    pending?.resume()
                case .failed(let error), .waiting(let error):
                    pending = gate.withLock { value in defer { value = nil }; return value }
                    guard let pending else { return }
                    pending.resume(throwing: error)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
