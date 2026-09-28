import Darwin
import Foundation
import Network
import Synchronization
import MochaProtocol
import Testing
@testable import MochaDaemonCore

enum WebServersIntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCHA_INTEGRATION"] == "1"
    }
}

@Suite(.tags(.integration), .enabled(if: WebServersIntegrationGate.isEnabled))
struct WebServerScannerIntegrationTests {
    @Test func findsAnHttpServerOnAnEphemeralPortWithItsTitle() async throws {
        var router = HttpRouter()
        router.route(.get, "/") { _ in
            HttpResponse(status: 302, headers: ["Location": "/inicio"])
        }
        router.route(.get, "/inicio") { _ in
            HttpResponse(
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: Data("<html><head><title>Mocha &amp; Teste</title></head><body>oi</body></html>".utf8)
            )
        }
        var jsonRouter = HttpRouter()
        jsonRouter.route(.get, "/") { _ in
            HttpResponse(headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        }
        let server = HttpServer(binding: .loopback(port: 0), router: router)
        let jsonServer = HttpServer(binding: .loopback(port: 0), router: jsonRouter)
        try await server.start()
        try await jsonServer.start()
        let port = try #require(await server.port.map(Int.init))
        let jsonPort = try #require(await jsonServer.port.map(Int.init))
        let ownPath = LibprocProcessListing.executablePath(of: getpid())
        let scanner = WebServerScanner(configuration: .init(
            excludedPorts: [47420, 47421],
            isExcludedExecutable: { $0 != ownPath && WebServerScanner.isSystemExecutable($0) }
        ))
        let clock = ContinuousClock()
        let start = clock.now
        let servers = await scanner.scan()
        let elapsed = clock.now - start
        await server.stop()
        await jsonServer.stop()

        let found = try #require(servers.first { $0.port == port })
        #expect(found.pid == Int(getpid()))
        #expect(found.title == "Mocha & Teste")
        #expect(found.directory == FileManager.default.currentDirectoryPath)
        #expect(!found.process.isEmpty)
        #expect(!servers.contains { $0.port == jsonPort })
        #expect(servers.map(\.port) == servers.map(\.port).sorted())
        #expect(elapsed < .milliseconds(2500))
    }

    @Test func findsAnHttpServerListeningOnlyOnIPv6Loopback() async throws {
        let server = try await IPv6LoopbackHTMLServer.start(html: "<html><head><title>Só IPv6</title></head></html>")
        let ownPath = LibprocProcessListing.executablePath(of: getpid())
        let scanner = WebServerScanner(configuration: .init(
            excludedPorts: [47420, 47421],
            isExcludedExecutable: { $0 != ownPath && WebServerScanner.isSystemExecutable($0) }
        ))
        let servers = await scanner.scan()
        server.cancel()

        let found = try #require(servers.first { $0.port == server.port })
        #expect(found.title == "Só IPv6")
    }
}

private final class IPv6LoopbackHTMLServer: Sendable {
    let port: Int
    private let listener: NWListener

    private init(listener: NWListener, port: Int) {
        self.listener = listener
        self.port = port
    }

    static func start(html: String) async throws -> IPv6LoopbackHTMLServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv6(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let body = Data(html.utf8)
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let port: Int = try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                let value: Result<Int, any Error>?
                switch state {
                case .ready: value = .success(Int(listener.port?.rawValue ?? 0))
                case .failed(let error): value = .failure(error)
                default: value = nil
                }
                guard let value, resumed.withLock({ done in defer { done = true }; return !done }) else { return }
                continuation.resume(with: value)
            }
            listener.start(queue: .global())
        }
        return IPv6LoopbackHTMLServer(listener: listener, port: port)
    }

    func cancel() {
        listener.cancel()
    }
}
