import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

func withLocalControl(
    _ harness: HubHarness,
    pairingURL: @escaping LocalControl.PairingURLProvider = { Sample.pairingURL },
    _ body: (LocalControlServer, LocalControlClient) async throws -> Void
) async throws {
    let path = FakeHerdrServer.temporarySocketPath()
    let control = LocalControl(
        hub: harness.hub,
        pairing: harness.pairing,
        devices: harness.devices,
        herdr: harness.herdr,
        transcripts: harness.transcripts,
        pairingURL: pairingURL,
        version: "9.9.9",
        startedAt: Sample.start
    )
    let server = LocalControlServer(socketPath: path, control: control)
    try await server.start()
    do {
        try await body(server, LocalControlClient(socketPath: path))
    } catch {
        await server.stop()
        throw error
    }
    await server.stop()
}

func socketMode(_ path: String) -> (isSocket: Bool, mode: Int)? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return (info.st_mode & S_IFMT == S_IFSOCK, Int(info.st_mode & 0o777))
}

@Suite(.timeLimit(.minutes(1)))
struct LocalControlTests {
    @Test func socketIsOwnerOnlyAndGoesAwayOnStop() async throws {
        try await withHub { harness in
            var socketPath = ""
            try await withLocalControl(harness) { server, client in
                socketPath = server.socketPath
                let mode = try #require(socketMode(server.socketPath))
                #expect(mode.isSocket)
                #expect(mode.mode == 0o600)
                _ = try await client.status()
            }
            #expect(socketMode(socketPath) == nil)
            await #expect(throws: LocalControlError.notRunning) {
                try await LocalControlClient(socketPath: socketPath).status()
            }
        }
    }

    @Test func statusReportsHerdrClientsAndFollowedSessionsWithTranscriptStats() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setStats(
                TranscriptStats(dropped: 1, orphanResults: 2, unknown: ["hologram": 3], claudeVersion: "2.1.283"),
                forSession: Sample.sessionA
            )
        }) { harness in
            let (socket, helloOk) = try await harness.pairedClient(name: "iPhone do João")
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-1")

            try await withLocalControl(harness) { _, client in
                let status = try await client.status()
                #expect(status.version == "9.9.9")
                #expect(status.startedAt == Sample.start)
                #expect(status.herdr == LocalStatus.Herdr(available: true, version: "0.9.1", protocolVersion: 22))
                #expect(status.clients == [LocalStatus.Client(deviceId: helloOk.deviceId, name: "iPhone do João", connectedAt: Sample.start)])
                #expect(status.sessions == [LocalStatus.Session(
                    sessionId: Sample.sessionA,
                    agentId: "w1:p1",
                    claudeVersion: "2.1.283",
                    dropped: 1,
                    orphanResults: 2,
                    unknown: ["hologram": 3]
                )])

                let raw = try await client.send(.get, LocalControl.statusPath)
                let object = try #require(try JSONSerialization.jsonObject(with: raw.body) as? [String: Any])
                let herdr = try #require(object["herdr"] as? [String: Any])
                #expect(herdr["protocol"] as? Int == 22)
                #expect(object["startedAt"] as? String == ProtocolDate.string(from: Sample.start))
            }
        }
    }

    @Test func pairingCodeFromTheLocalChannelPairsAnIPhone() async throws {
        try await withHub { harness in
            try await withLocalControl(harness) { _, client in
                let code = try await client.pairingCode()
                #expect(code.url == Sample.pairingURL)
                let link = PairingLink(url: code.url, code: code.code)
                #expect(link.link.absoluteString.hasPrefix("mocha://pair?"))
                #expect(PairingLink(link.link) == link)

                let socket = harness.connect()
                let reply = try await socket.reply(to: .hello(HelloPayload(pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0")))
                guard case .helloOk = reply else { throw UnexpectedMessage(message: reply) }
            }
        }
    }

    @Test func pairingCodeIs503WhenTheTailscaleHostIsUnknown() async throws {
        try await withHub { harness in
            try await withLocalControl(harness, pairingURL: { throw TailscaleError.missingDNSName }) { _, client in
                await #expect(throws: LocalControlError.unexpectedStatus(503, "tailscale status --json sem Self.DNSName (o Tailscale está conectado?)")) {
                    try await client.pairingCode()
                }
            }
        }
    }

    @Test func deletingADeviceClosesItsConnectionsAndForgetsIt() async throws {
        try await withHub { harness in
            let (socket, helloOk) = try await harness.pairedClient()
            let (bystander, bystanderHello) = try await harness.pairedClient(name: "iPad")

            try await withLocalControl(harness) { _, client in
                let removed = try await client.removeDevice(helloOk.deviceId)
                #expect(removed)
                #expect(try await socket.waitForClose() == .policyViolation)
                #expect(bystander.closeCode == nil)
                #expect(try await harness.devices.devices().map(\.id) == [bystanderHello.deviceId])

                #expect(try await client.removeDevice(helloOk.deviceId) == false)
                #expect(try await client.removeDevice("nao-existe") == false)
                #expect(try await client.removeDevice("com espaço") == false)
            }
        }
    }

    @Test func unknownPathsAndMethodsAreRejected() async throws {
        try await withHub { harness in
            try await withLocalControl(harness) { _, client in
                let missing = try await client.send(.get, "/local/nada")
                #expect(missing.status == 404)
                #expect(try await client.send(.post, LocalControl.statusPath).status == 405)
                #expect(try await client.send(.get, LocalControl.pairingCodePath).status == 405)
            }
        }
    }
}
