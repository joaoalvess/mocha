import Foundation
import MochaProtocol
import MochaTestSupport
import Network
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct DaemonRuntimeTests {
    static func options(_ home: TemporaryHome, herdrSocket: String, hookPort: UInt16? = 0) -> DaemonOptions {
        DaemonOptions(
            paths: home.paths,
            herdrSocketPath: herdrSocket,
            projectsRoot: home.url.appending(path: "projects").path(percentEncoded: false),
            pairingURL: { Sample.pairingURL },
            hookPort: hookPort,
            codexExecutable: { nil }
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

    @Test func hookPortInUseFailsFastAndReleasesTheGateway() async throws {
        try await withRunningServer(HttpRouter()) { hookPort in
            try await withTemporaryHome(short: true) { home in
                let gatewayPort = try await Self.freePort()
                try home.write(
                    #"{"gatewayPort": \#(gatewayPort), "hookPort": \#(hookPort)}"#,
                    to: "Library/Application Support/Mocha/config.json",
                    permissions: 0o600
                )
                let runtime = DaemonRuntime(options: Self.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath(), hookPort: nil))

                await #expect(throws: DaemonStartError.portInUse(hookPort)) {
                    try await runtime.start()
                }
                #expect(socketMode(home.paths.controlSocket.path(percentEncoded: false)) == nil)
                let probe = HttpServer(binding: .loopback(port: gatewayPort), router: HttpRouter())
                try await probe.start()
                await probe.stop()
            }
        }
    }

    @Test func runServesTheHookRoutesWithTheSecretFromTheConfig() async throws {
        try await withTemporaryHome(short: true) { home in
            let port = try await Self.freePort()
            try home.write(#"{"gatewayPort": \#(port), "hookSecret": "segredo-do-config"}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let runtime = DaemonRuntime(options: Self.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath()))
            let events = runtime.hookEvents.events()

            let started = try await runtime.start()

            #expect(started.hookPort != 0)
            #expect(started.hookPort != DaemonConfig.defaultHookPort)
            #expect(started.generatedHookSecret == false)
            let body = try Fixtures.data("hooks/Stop.json")
            let rejected = try await sendRequest("POST", port: started.hookPort, target: "/hooks/Stop", headers: ["X-Mocha-Pane": "w1C:p2"], body: body)
            #expect(rejected.status == 401)
            let accepted = try await sendRequest(
                "POST",
                port: started.hookPort,
                target: "/hooks/Stop",
                headers: ["X-Mocha-Pane": "w1C:p2", "X-Mocha-Hook-Secret": "segredo-do-config", "Content-Type": "application/json"],
                body: body
            )
            #expect(accepted.status == 200)
            #expect(String(decoding: accepted.body, as: UTF8.self) == "{}")
            var iterator = events.makeAsyncIterator()
            let received = try #require(await iterator.next())
            #expect(received.agentId == "w1C:p2")
            #expect(received.event.name == .stop)

            await runtime.stop()

            #expect(await iterator.next() == nil)
        }
    }

    @Test func aStopHookBecomesAnAlertForTheRegisteredDevice() async throws {
        try await withTemporaryHome(short: true) { home in
            let port = try await Self.freePort()
            try home.write(#"{"gatewayPort": \#(port), "hookSecret": "segredo-do-config"}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            _ = try await DeviceStore(fileURL: home.paths.devicesFile).register(
                name: "iPhone",
                token: "t",
                at: Date(),
                apns: ApnsRegistration(token: PushTestData.deviceToken, env: .sandbox)
            )
            let key = try PushTestData.signingKey()
            let transport = FakeApnsTransport()
            var options = Self.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath())
            options.apnsCredentials = { ApnsCredentials(config: ApnsConfig(teamId: PushTestData.teamId, keyId: PushTestData.keyId, bundleId: PushTestData.bundleId), key: key) }
            options.apnsTransport = transport
            let runtime = DaemonRuntime(options: options)

            let started = try await runtime.start()
            let accepted = try await sendRequest(
                "POST",
                port: started.hookPort,
                target: "/hooks/Stop",
                headers: ["X-Mocha-Pane": "w1C:p2", "X-Mocha-Hook-Secret": "segredo-do-config", "Content-Type": "application/json"],
                body: try Fixtures.data("hooks/Stop.json")
            )
            #expect(accepted.status == 200)

            let request = try await eventually { transport.requests.first }
            #expect(request.url?.host() == "api.sandbox.push.apple.com")
            let payload = try PushTestData.jsonObject(try #require(request.httpBody))
            let alert = try #require((payload["aps"] as? [String: Any])?["alert"] as? [String: Any])
            #expect(alert["title"] as? String == "Claude terminou")
            #expect(alert["body"] as? String == "pronto")
            #expect(payload["agentId"] as? String == "w1C:p2")

            await runtime.stop()
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
