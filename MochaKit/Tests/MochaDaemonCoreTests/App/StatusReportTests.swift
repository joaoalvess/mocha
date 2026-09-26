import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct StatusReportTests {
    static let serveMissing = DoctorChecks.serve(
        .missingHandler(host: "mac.example.ts.net"),
        setupCommand: "tailscale serve --bg --https=443 http://127.0.0.1:47421",
        expectedTarget: "http://127.0.0.1:47421"
    )
    static let serveReady = DoctorChecks.serve(.ready(host: "mac.example.ts.net"), setupCommand: "", expectedTarget: "http://127.0.0.1:47421")

    @Test func withoutTheDaemonStatusSaysMochadParadoAndPingsHerdrDirectly() {
        let report = StatusReport.make(
            local: .failure(.notRunning),
            herdrPing: .reachable(HerdrServerInfo(version: "0.9.1", protocolVersion: 22)),
            serve: Self.serveMissing,
            now: DoctorTests.now
        )
        #expect(report.exitCode != 0)
        #expect(report.text == """
            mochad parado: rode mochad install ou scripts/run-daemon.sh
            Herdr (ping direto): 0.9.1 · protocolo 22
            Serve: ❌ sem handler em mac.example.ts.net:443
              rode mochad serve-setup --apply (tailscale serve --bg --https=443 http://127.0.0.1:47421)
            """)
    }

    @Test func missingHerdrSocketIsShownWithoutTheDaemon() {
        let report = StatusReport.make(local: .failure(.notRunning), herdrPing: .missingSocket("/tmp/herdr.sock"), serve: Self.serveReady, now: DoctorTests.now)
        #expect(report.text.contains("Herdr (ping direto): ❌ o socket não existe em /tmp/herdr.sock"))
    }

    @Test func withTheDaemonStatusListsHerdrClientsAndServe() {
        let status = LocalStatus(
            version: "0.1.0",
            startedAt: DoctorTests.startedAt,
            herdr: LocalStatus.Herdr(available: true, version: "0.9.1", protocolVersion: 21),
            clients: [LocalStatus.Client(deviceId: "dev-1", name: "iPhone do João", connectedAt: DoctorTests.now.addingTimeInterval(-120))],
            sessions: []
        )
        let report = StatusReport.make(local: .success(status), herdrPing: nil, serve: Self.serveReady, now: DoctorTests.now)

        #expect(report.exitCode == 0)
        let lines = report.text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "mochad 0.1.0 · no ar há 1 h 05 min")
        #expect(lines[1].hasPrefix("Herdr: conectado · 0.9.1 · protocolo 21 ⚠️"))
        #expect(lines[2] == "Clientes: 1")
        #expect(lines[3] == "  iPhone do João · dev-1 · conectado há 2 min")
        #expect(lines[4] == "Serve: ✅ https://mac.example.ts.net → http://127.0.0.1:47421, /v1/health 200")
    }

    @Test func unavailableHerdrAndNoClients() {
        let status = LocalStatus(version: "0.1.0", startedAt: DoctorTests.startedAt, herdr: LocalStatus.Herdr(available: false), clients: [], sessions: [])
        let report = StatusReport.make(local: .success(status), herdrPing: nil, serve: Self.serveReady, now: DoctorTests.now)
        #expect(report.text.contains("Herdr: indisponível (o daemon tenta de novo a cada 2 s)"))
        #expect(report.text.contains("Clientes: nenhum conectado"))
    }
}
