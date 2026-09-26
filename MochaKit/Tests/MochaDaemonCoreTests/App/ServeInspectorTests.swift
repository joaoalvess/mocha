import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct ServeInspectorTests {
    static let target = "http://127.0.0.1:47421"
    static let executable = "/opt/fake/tailscale"

    static func inspector(serve: String, probe: FakeHttpProbe, enable: ProcessOutput = ProcessOutput()) -> (ServeInspector, FakeProcessRunner) {
        let runner = TailscaleSamples.runner(serve: serve, enable: enable)
        let inspector = ServeInspector(
            tailscale: TailscaleCLI(executable: executable, runner: runner),
            probe: probe,
            gatewayPort: 47421
        )
        return (inspector, runner)
    }

    @Test func readyWhenTheHandlerProxiesToTheGatewayAndHealthIs200() async throws {
        let probe = FakeHttpProbe(.status(200))
        let (inspector, runner) = Self.inspector(serve: TailscaleSamples.serve(proxy: Self.target), probe: probe)

        #expect(await inspector.diagnose() == .ready(host: TailscaleSamples.host))
        #expect(runner.calls.allSatisfy { $0.executable == Self.executable && $0.environment == ["TAILSCALE_BE_CLI": "1"] })
        #expect(runner.commands == ["tailscale status --json", "tailscale serve status --json"])
        #expect(probe.requests.map(\.url.absoluteString) == ["https://mac.example.ts.net/v1/health"])
        #expect(probe.requests.map(\.timeout) == [ServeInspector.doctorHealthTimeout])
    }

    @Test func distinguishesMissingHandlerUnixTarget502AndTLSTimeout() async throws {
        let cases: [(serve: String, probe: HttpProbeResult, expected: ServeDiagnosis, status: DoctorStatus, text: String)] = [
            ("{}", .status(200), .missingHandler(host: TailscaleSamples.host), .failure, "tailscale serve --bg --https=443 http://127.0.0.1:47421"),
            (
                TailscaleSamples.serve(proxy: "unix:/Users/dev/Library/Application Support/Mocha/gateway.sock"),
                .status(200),
                .unixTarget(host: TailscaleSamples.host, target: "unix:/Users/dev/Library/Application Support/Mocha/gateway.sock"),
                .failure,
                "a extensão do Tailscale não abre socket Unix"
            ),
            (TailscaleSamples.serve(proxy: Self.target), .status(502), .gatewayNotListening(host: TailscaleSamples.host), .failure, "Serve ativo, gateway sem escutar"),
            (TailscaleSamples.serve(proxy: Self.target), .timedOut, .certificatePending(host: TailscaleSamples.host), .warning, "certificado sendo emitido; tente de novo em 1 min"),
            (
                TailscaleSamples.serve(proxy: "http://127.0.0.1:3000"),
                .status(200),
                .unexpectedTarget(host: TailscaleSamples.host, target: "http://127.0.0.1:3000"),
                .failure,
                "e não para http://127.0.0.1:47421"
            ),
        ]
        for sample in cases {
            let (inspector, _) = Self.inspector(serve: sample.serve, probe: FakeHttpProbe(sample.probe))
            let diagnosis = await inspector.diagnose()
            #expect(diagnosis == sample.expected)
            let item = DoctorChecks.serve(diagnosis, setupCommand: inspector.setupCommand, expectedTarget: inspector.expectedTarget)
            #expect(item.status == sample.status)
            #expect((([item.summary] + item.details).joined(separator: "\n")).contains(sample.text))
        }
    }

    @Test func handlerOnAnotherHostCountsAsMissing() async throws {
        let serve = #"{"Web":{"other.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:47421"}}}}}"#
        let (inspector, _) = Self.inspector(serve: serve, probe: FakeHttpProbe(.status(200)))
        #expect(await inspector.diagnose() == .missingHandler(host: TailscaleSamples.host))
    }

    @Test func missingTailscaleIsReported() async throws {
        let runner = FakeProcessRunner { call in throw ProcessRunnerError.notExecutable(call.executable) }
        let inspector = ServeInspector(tailscale: TailscaleCLI(executable: Self.executable, runner: runner), probe: FakeHttpProbe(.status(200)), gatewayPort: 47421)
        #expect(await inspector.diagnose() == .tailscaleUnavailable("Tailscale não encontrado em \(Self.executable)"))
    }

    @Test func applyRunsServeThenChecksTheHandlerAndWarmsUpForNinetySeconds() async throws {
        let probe = FakeHttpProbe(.status(200))
        let (inspector, runner) = Self.inspector(serve: TailscaleSamples.serve(proxy: Self.target), probe: probe)

        #expect(await inspector.apply() == .ready(host: TailscaleSamples.host))
        #expect(runner.commands == [
            "tailscale serve --bg --https=443 http://127.0.0.1:47421",
            "tailscale status --json",
            "tailscale serve status --json",
        ])
        #expect(probe.requests.map(\.timeout) == [.seconds(90)])
    }

    @Test func applyReportsAFailedServeCommand() async throws {
        let probe = FakeHttpProbe(.status(200))
        let (inspector, runner) = Self.inspector(
            serve: "{}",
            probe: probe,
            enable: ProcessOutput(status: 1, output: "", error: "serve: access denied")
        )
        #expect(await inspector.apply() == .tailscaleUnavailable("tailscale serve --bg --https=443 http://127.0.0.1:47421 falhou: serve: access denied"))
        #expect(runner.commands == ["tailscale serve --bg --https=443 http://127.0.0.1:47421"])
        #expect(probe.requests.isEmpty)
    }

    @Test func removeTurnsOffOnlyTheHttpsHandler() async throws {
        let (inspector, runner) = Self.inspector(serve: "{}", probe: FakeHttpProbe(.status(200)))
        try await inspector.remove()
        #expect(runner.commands == ["tailscale serve --https=443 off"])
        #expect(inspector.removeCommand == "tailscale serve --https=443 off")
    }

    @Test func pairingURLComesFromTheDNSNameWithoutTheTrailingDot() async throws {
        let runner = TailscaleSamples.runner(serve: "{}")
        let url = try await TailscaleCLI(executable: Self.executable, runner: runner).webSocketURL()
        #expect(url.absoluteString == "wss://mac.example.ts.net/v1")
    }

    @Test func defaultExecutableIsTheAppBundleBinary() {
        #expect(TailscaleCLI().executable == "/Applications/Tailscale.app/Contents/MacOS/tailscale")
    }
}
