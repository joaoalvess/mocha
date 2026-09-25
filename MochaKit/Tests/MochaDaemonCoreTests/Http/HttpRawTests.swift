import Foundation
import Network
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct HttpRawTests {
    private static func router() -> HttpRouter {
        var router = HttpRouter()
        router.route(.get, "/hello") { _ in HttpResponse(body: Data("hello".utf8)) }
        router.route(.post, "/echo", maxBodySize: 1024) { request in HttpResponse(body: request.body) }
        router.webSocket("/ws") { _, _ in }
        return router
    }

    private static func exchange(
        _ request: [UInt8],
        port: UInt16
    ) async throws -> (response: String, error: NWError?) {
        let client = try await RawClient.connect(to: loopbackEndpoint(port))
        defer { client.cancel() }
        try await client.send(request)
        let bytes = try await client.readToEnd()
        return (String(decoding: bytes, as: UTF8.self), await client.receivedError)
    }

    private static func exchange(_ request: String, port: UInt16) async throws -> String {
        try await exchange(Array(request.utf8), port: port).response
    }

    @Test func rawGetReceivesContentLengthAndConnectionClose() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n", port: port)
            #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
            #expect(response.contains("\r\nContent-Length: 5\r\n"))
            #expect(response.contains("\r\nConnection: close\r\n"))
            #expect(response.hasSuffix("\r\n\r\nhello"))
        }
    }

    @Test func chunkedRequestIsRejectedWith411() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange(
                "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n",
                port: port
            )
            #expect(response.hasPrefix("HTTP/1.1 411 Length Required\r\n"))
            #expect(response.contains("\r\nContent-Length: 0\r\n"))
            #expect(response.hasSuffix("\r\nConnection: close\r\n\r\n"))
        }
    }

    @Test(arguments: [
        "GARBAGE\r\n\r\n",
        "GET /hello\r\n\r\n",
        "GET  /hello HTTP/1.1\r\n\r\n",
        "GET hello HTTP/1.1\r\n\r\n",
        "GET /hello HTTP/1.1\r\nBroken header\r\n\r\n",
        "GET /hello HTTP/1.1\r\nName : value\r\n\r\n",
        "GET /hello HTTP/1.1\r\nX-A: 1\r\n folded\r\n\r\n",
        "GET /hello HTTP/1.1\nHost: x\r\n\r\n",
        "POST /echo HTTP/1.1\r\nContent-Length: abc\r\n\r\n",
        "POST /echo HTTP/1.1\r\nContent-Length: 3\r\nContent-Length: 4\r\n\r\nabcd",
    ])
    func malformedRequestIsRejectedWith400(_ request: String) async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange(request, port: port)
            #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        }
    }

    @Test func unsupportedVersionIsRejectedWith505() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange("GET /hello HTTP/2.0\r\n\r\n", port: port)
            #expect(response.hasPrefix("HTTP/1.1 505 HTTP Version Not Supported\r\n"))
        }
    }

    @Test func oversizedHeadIsRejectedWith431() async throws {
        let configuration = HttpServerConfiguration(maxHeadSize: 1024)
        try await withRunningServer(Self.router(), configuration: configuration) { port in
            let request = "GET /hello HTTP/1.1\r\nX-Big: \(String(repeating: "a", count: 4096))\r\n\r\n"
            let response = try await Self.exchange(request, port: port)
            #expect(response.hasPrefix("HTTP/1.1 431 Request Header Fields Too Large\r\n"))
        }
    }

    @Test func plainGetOnWebSocketRouteIsRejectedWith426() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange("GET /ws HTTP/1.1\r\nHost: x\r\n\r\n", port: port)
            #expect(response.hasPrefix("HTTP/1.1 426 Upgrade Required\r\n"))
            #expect(response.contains("\r\nUpgrade: websocket\r\n"))
            #expect(response.contains("\r\nSec-WebSocket-Version: 13\r\n"))
        }
    }

    @Test func wrongWebSocketVersionIsRejectedWith426() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange(
                "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                    + "Sec-WebSocket-Key: \(RawClient.sampleKey)\r\nSec-WebSocket-Version: 8\r\n\r\n",
                port: port
            )
            #expect(response.hasPrefix("HTTP/1.1 426 Upgrade Required\r\n"))
            #expect(response.contains("\r\nSec-WebSocket-Version: 13\r\n"))
        }
    }

    @Test func invalidWebSocketKeyIsRejectedWith400() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange(
                "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                    + "Sec-WebSocket-Key: c2hvcnQ=\r\nSec-WebSocket-Version: 13\r\n\r\n",
                port: port
            )
            #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        }
    }

    @Test func bodyAboveLimitIsDrainedSoClientReadsResponseWithoutReset() async throws {
        try await withRunningServer(Self.router()) { port in
            let body = [UInt8](repeating: 0x61, count: 4 << 20)
            let head = Array("POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            let (response, error) = try await Self.exchange(head + body, port: port)
            #expect(response.hasPrefix("HTTP/1.1 413 Content Too Large\r\n"))
            #expect(response.hasSuffix("\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"))
            #expect(error == nil)
        }
    }

    @Test func absoluteFormTargetIsRouted() async throws {
        try await withRunningServer(Self.router()) { port in
            let response = try await Self.exchange("GET http://127.0.0.1/hello?x=1 HTTP/1.1\r\nHost: x\r\n\r\n", port: port)
            #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HttpUnixSocketTests {
    private static func temporarySocketPath() -> String {
        NSTemporaryDirectory() + "mocha-\(UUID().uuidString.prefix(8)).sock"
    }

    private static func leaveStaleSocket(at path: String) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: parameters)
        let (states, continuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { continuation.yield($0) }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: DispatchQueue(label: "com.joaoalves.mocha.tests.stale-socket"))
        try await withTimeout {
            for await state in states {
                if case .ready = state { return }
                if case .failed(let error) = state { throw error }
            }
        }
        listener.cancel()
    }

    private static func permissions(atPath path: String) -> (isSocket: Bool, mode: mode_t)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (info.st_mode & S_IFMT == S_IFSOCK, info.st_mode & 0o777)
    }

    @Test func servesGetOverUnixSocketReplacingStaleSocket() async throws {
        let path = Self.temporarySocketPath()
        defer { unlink(path) }
        try await Self.leaveStaleSocket(at: path)
        #expect(Self.permissions(atPath: path)?.isSocket == true)

        var router = HttpRouter()
        router.route(.get, "/v1/health") { _ in HttpResponse(body: Data("{\"ok\":true}".utf8)) }
        let server = HttpServer(binding: .unixSocket(path: path), router: router)
        try await server.start()
        let permissions = try #require(Self.permissions(atPath: path))
        #expect(permissions.isSocket)
        #expect(permissions.mode == 0o600)

        let client = try await RawClient.connect(to: .unix(path: path))
        defer { client.cancel() }
        try await client.send("GET /v1/health HTTP/1.1\r\nHost: localhost\r\n\r\n")
        let response = String(decoding: try await client.readToEnd(), as: UTF8.self)
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.hasSuffix("\r\n\r\n{\"ok\":true}"))

        await server.stop()
        #expect(Self.permissions(atPath: path) == nil)
    }

    @Test func refusesToReplaceRegularFile() async throws {
        let path = Self.temporarySocketPath()
        defer { unlink(path) }
        #expect(FileManager.default.createFile(atPath: path, contents: Data("keep".utf8)))
        let server = HttpServer(binding: .unixSocket(path: path), router: HttpRouter())
        await #expect(throws: HttpServerError.socketPathOccupied(path)) {
            try await server.start()
        }
        #expect(FileManager.default.contents(atPath: path) == Data("keep".utf8))
    }

    @Test func rejectsPathLongerThanSunPath() async throws {
        let path = NSTemporaryDirectory() + String(repeating: "m", count: 120) + ".sock"
        let server = HttpServer(binding: .unixSocket(path: path), router: HttpRouter())
        await #expect(throws: HttpServerError.socketPathTooLong(path)) {
            try await server.start()
        }
    }
}
