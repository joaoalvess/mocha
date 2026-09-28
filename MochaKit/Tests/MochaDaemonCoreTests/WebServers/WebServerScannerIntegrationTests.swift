import Darwin
import Foundation
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
}
