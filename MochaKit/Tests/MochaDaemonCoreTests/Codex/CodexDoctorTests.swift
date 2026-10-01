import Foundation
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexDoctorTests {
    @Test func theProbeReadsInitializeAndAccountWithoutTheEmail() async throws {
        try await withCodexServer { harness in
            await harness.server.reply(to: "account/read", with: .result(try CodexSample.result("account-read.response.json")))

            let probe = await CodexInspector.appServer(at: harness.server.socketPath)
            #expect(probe == .reachable(CodexServerInfo(version: FakeCodexAppServer.version, signedIn: true, plan: "plus")))
            let item = DoctorChecks.codex(executable: "/opt/fake/codex", version: FakeCodexAppServer.version, server: probe)
            #expect(item == DoctorItem("Codex", .ok, "0.159.2 · /opt/fake/codex · App Server no ar · conta plus"))
            #expect(!item.summary.contains("@"))
            let initialize = try #require(await harness.server.requests(method: "initialize").first)
            #expect(initialize.params["capabilities"]?["experimentalApi"] == .bool(true))
            _ = try await eventually { await harness.server.openConnections == 0 ? true : nil }
        }
    }

    @Test func aRefusedInitializeIsAFailure() async throws {
        try await withCodexServer { harness in
            await harness.server.reply(to: "initialize", with: .error(code: -32600, message: "Not initialized"))

            let probe = await CodexInspector.appServer(at: harness.server.socketPath)
            #expect(probe == .failed("o initialize foi recusado: Not initialized"))
            let item = DoctorChecks.codex(executable: "/opt/fake/codex", version: "0.159.2", server: probe)
            #expect(item == DoctorItem("Codex", .failure, "0.159.2 · /opt/fake/codex · App Server não respondeu ao initialize", details: ["o initialize foi recusado: Not initialized"]))
        }
    }

    @Test func aSilentAppServerTimesOut() async throws {
        try await withCodexServer { harness in
            await harness.server.reply(to: "initialize", with: .noReply)

            let probe = await CodexInspector.appServer(at: harness.server.socketPath, timeout: .milliseconds(200))
            guard case .failed = probe else {
                Issue.record("expected a failure, got \(probe)")
                return
            }
            #expect(DoctorChecks.codex(executable: "/opt/fake/codex", version: nil, server: probe).status == .failure)
        }
    }

    @Test func anAppServerWithoutLoginIsAWarning() async throws {
        try await withCodexServer { harness in
            await harness.server.reply(to: "account/read", with: .result(.object([.init("account", .null), .init("requiresOpenaiAuth", .bool(true))])))

            let probe = await CodexInspector.appServer(at: harness.server.socketPath)
            #expect(probe == .reachable(CodexServerInfo(version: "0.159.2", signedIn: false, plan: nil)))
            let item = DoctorChecks.codex(executable: "/opt/fake/codex", version: "0.159.2", server: probe)
            #expect(item.status == .warning)
            #expect(item.details == ["sem login no Codex: rode codex login"])
        }
    }

    @Test func theMissingSocketIsAFailureAndTheStatusLineSaysSo() async {
        let path = "/tmp/mocha-sem-codex-\(UUID().uuidString.prefix(8)).sock"
        let probe = await CodexInspector.appServer(at: path)
        #expect(probe == .missingSocket(path))
        #expect(DoctorChecks.codex(executable: "/opt/fake/codex", version: "0.159.2", server: probe).status == .failure)
        #expect(DoctorChecks.codexServerLine(probe) == "❌ fora do ar (sem o socket \(path))")
        #expect(DoctorChecks.codexServerLine(.reachable(CodexServerInfo(version: "0.159.2", signedIn: true, plan: nil))) == "no ar · 0.159.2")
    }

    @Test func theVersionComesFromTheUserAgent() throws {
        let userAgent = try CodexSample.result("initialize.response.json")["userAgent"]?.stringValue
        #expect(CodexInspector.version(fromUserAgent: userAgent) == "0.159.2")
        #expect(CodexInspector.version(fromUserAgent: "sem-barra") == nil)
        #expect(CodexInspector.version(fromUserAgent: nil) == nil)
    }
}
