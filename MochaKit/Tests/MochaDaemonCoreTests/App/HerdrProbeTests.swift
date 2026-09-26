import Foundation
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct HerdrProbeTests {
    static func withServer(_ body: (FakeHerdrServer) async throws -> Void) async throws {
        let server = FakeHerdrServer()
        try await server.loadSnapshot(fixture: "session.snapshot.two-agents-one-tab.response.json")
        try await server.start()
        do {
            try await body(server)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    @Test func pingReportsVersionAndProtocol() async throws {
        try await Self.withServer { server in
            let probe = HerdrProbe(socketPath: server.socketPath)
            let ping = await probe.ping()

            #expect(ping == .reachable(HerdrServerInfo(version: "0.9.1", protocolVersion: 22)))
            #expect(DoctorChecks.herdr(ping, socketPath: server.socketPath) == DoctorItem("Herdr", .ok, "0.9.1 · protocolo 22 · \(server.socketPath)"))
            #expect(await probe.agents() == .counted(total: 2, claude: 2))
            #expect(DoctorChecks.agentList(.counted(total: 2, claude: 2)) == DoctorItem("agent.list", .ok, "2 agentes, 2 do Claude Code"))
        }
    }

    @Test func otherProtocolIsAWarning() async throws {
        try await Self.withServer { server in
            await server.setServerVersion("0.10.0", protocolVersion: 23)
            let item = DoctorChecks.herdr(await HerdrProbe(socketPath: server.socketPath).ping(), socketPath: server.socketPath)
            #expect(item.status == .warning)
            #expect(item.summary.hasPrefix("0.10.0 · protocolo 23"))
            #expect(item.details.first?.contains("o Mocha espera o 22") == true)
        }
    }

    @Test func missingSocketIsAFailure() async throws {
        let path = FakeHerdrServer.temporarySocketPath()
        let probe = HerdrProbe(socketPath: path)
        #expect(await probe.ping() == .missingSocket(path))
        #expect(await probe.agents() == .missingSocket(path))
        #expect(DoctorChecks.herdr(.missingSocket(path), socketPath: path) == DoctorItem("Herdr", .failure, "o socket não existe em \(path)"))
        #expect(DoctorChecks.agentList(.missingSocket(path)).status == .failure)
    }
}
