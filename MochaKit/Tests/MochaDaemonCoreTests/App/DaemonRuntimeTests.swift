import Foundation
import MochaTestSupport
import Network
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct DaemonRuntimeTests {
    static func options(_ home: TemporaryHome, herdrSocket: String) -> DaemonOptions {
        DaemonOptions(
            paths: home.paths,
            herdrSocketPath: herdrSocket,
            projectsRoot: home.url.appending(path: "projects").path(percentEncoded: false),
            pairingURL: { Sample.pairingURL }
        )
    }

    static func freePort() async throws -> UInt16 {
        let probe = HttpServer(binding: .loopback(port: 0), router: HttpRouter())
        try await probe.start()
        let port = try #require(await probe.port)
        await probe.stop()
        return port
    }

    static func get(_ path: String, port: UInt16) async throws -> String {
        let client = try await RawClient.connect(to: loopbackEndpoint(port))
        defer { client.cancel() }
        try await client.send("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        return String(decoding: try await client.readToEnd(), as: UTF8.self)
    }

    @Test func portInUseFailsFastWithoutTakingTheLocalSocket() async throws {
        try await withRunningServer(HttpRouter()) { port in
            try await withTemporaryHome(short: true) { home in
                try home.write(#"{"gatewayPort": \#(port)}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
                let runtime = DaemonRuntime(options: Self.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath()))

                await #expect(throws: DaemonStartError.portInUse(port)) {
                    try await runtime.start()
                }
                #expect(socketMode(home.paths.controlSocket.path(percentEncoded: false)) == nil)
            }
        }
    }

    @Test func runServesTheGatewayAndTheLocalChannelAndStopsCleanly() async throws {
        try await HerdrProbeTests.withServer { herdr in
            try await withTemporaryHome(short: true) { home in
                let port = try await Self.freePort()
                try home.write(#"{"gatewayPort": \#(port), "note": "mantenha"}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
                let runtime = DaemonRuntime(options: Self.options(home, herdrSocket: herdr.socketPath))

                let started = try await runtime.start()

                #expect(started.gatewayPort == port)
                #expect(started.generatedHookSecret)
                #expect(started.herdrSocket == herdr.socketPath)
                #expect(started.controlSocket == home.paths.controlSocket.path(percentEncoded: false))
                #expect(socketMode(started.controlSocket)?.mode == 0o600)
                let config = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: home.paths.configFile)) as? [String: Any])
                #expect(config["note"] as? String == "mantenha")
                #expect(config["hookSecret"] is String)

                let health = try await Self.get("/v1/health", port: port)
                #expect(health.hasPrefix("HTTP/1.1 200 OK\r\n"))

                let client = LocalControlClient(socketPath: started.controlSocket)
                let status = try await eventually {
                    let status = try? await client.status()
                    return status?.herdr.available == true ? status : nil
                }
                #expect(status.version == DaemonVersion.current)
                #expect(status.herdr == LocalStatus.Herdr(available: true, version: "0.9.1", protocolVersion: 22))
                #expect(try await client.pairingCode().url == Sample.pairingURL)

                await runtime.stop()

                #expect(socketMode(started.controlSocket) == nil)
                await #expect(throws: LocalControlError.notRunning) {
                    try await client.status()
                }
            }
        }
    }

    @Test func secondStartKeepsTheHookSecret() async throws {
        try await withTemporaryHome(short: true) { home in
            let port = try await Self.freePort()
            try home.write(#"{"gatewayPort": \#(port)}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let options = Self.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath())

            let first = DaemonRuntime(options: options)
            #expect(try await first.start().generatedHookSecret)
            await first.stop()
            let second = DaemonRuntime(options: options)
            #expect(try await second.start().generatedHookSecret == false)
            await second.stop()
        }
    }
}
