import Foundation
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite
struct DoctorTests {
    static let now = Date(timeIntervalSince1970: 1_790_003_900)
    static let startedAt = Date(timeIntervalSince1970: 1_790_000_000)

    static func running(sessions: [LocalStatus.Session] = [], clients: [LocalStatus.Client] = [], apns: LocalStatus.Apns? = nil) -> LocalStatus {
        LocalStatus(
            version: "0.1.0",
            startedAt: startedAt,
            herdr: LocalStatus.Herdr(available: true, version: "0.9.1", protocolVersion: 22),
            clients: clients,
            sessions: sessions,
            apns: apns
        )
    }

    static func session(_ id: String, version: String?, dropped: Int = 0, unknown: [String: Int] = [:]) -> LocalStatus.Session {
        LocalStatus.Session(sessionId: id, agentId: "w1:p1", claudeVersion: version, dropped: dropped, orphanResults: 0, unknown: unknown)
    }

    static func doctor(
        _ home: TemporaryHome,
        local: FakeLocalControl,
        herdrSocket: String,
        codesign: ProcessOutput = CodesignSamples.adHoc,
        keychain: KeychainItemPresence = .present,
        codex: CodexInspector = CodexInspector(executable: nil, runner: FakeProcessRunner { _ in ProcessOutput() })
    ) -> Doctor {
        let tailscale = TailscaleSamples.runner(serve: "{}")
        return Doctor(
            paths: home.paths,
            herdr: HerdrProbe(socketPath: herdrSocket),
            local: local,
            serve: ServeInspector(tailscale: TailscaleCLI(executable: "/opt/fake/tailscale", runner: tailscale), probe: FakeHttpProbe(.status(200)), gatewayPort: 47421),
            codex: codex,
            signer: CodeSigner(runner: CodesignSamples.runner(codesign), identities: FakeIdentities(identities: [])),
            keyPresence: FakeKeyPresence(result: keychain),
            executable: home.url.appending(path: "build/mochad"),
            now: { now }
        )
    }

    @Test func withoutTheDaemonDoctorSaysMochadParadoAndFails() async throws {
        try await withTemporaryHome { home in
            let missingHerdr = FakeHerdrServer.temporarySocketPath()
            let items = await Self.doctor(home, local: FakeLocalControl(), herdrSocket: missingHerdr).run()

            #expect(items.map(\.title) == ["mochad", "Herdr", "agent.list", "Hooks", "moshi-hook", "Codex", "Serve", "APNs", "Dados", "Transcript"])
            #expect(items[0] == DoctorItem("mochad", .failure, "mochad parado: rode mochad install ou scripts/run-daemon.sh"))
            #expect(items[1] == DoctorItem("Herdr", .failure, "o socket não existe em \(missingHerdr)"))
            #expect(items[3] == DoctorItem("Hooks", .warning, "não instalados: sem ~/.claude/settings.json (mochad install-hooks)"))
            #expect(items[5] == DoctorItem("Codex", .warning, "codex não encontrado; tabs Codex ficam indisponíveis"))
            #expect(items[6].status == .failure)
            #expect(items[6].details == ["rode mochad serve-setup --apply (tailscale serve --bg --https=443 http://127.0.0.1:47421)"])
            #expect(items[9] == DoctorItem("Transcript", .warning, "precisa do daemon (mochad parado)"))
            #expect(DoctorReport.exitCode(items) != 0)
            #expect(DoctorReport.render(items).hasPrefix("❌ mochad: mochad parado"))
        }
    }

    @Test func withTheDaemonTheTranscriptItemComesFromLocalStatus() async throws {
        try await HerdrProbeTests.withServer { server in
            try await withTemporaryHome { home in
                let status = Self.running(sessions: [
                    Self.session("0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64", version: ClaudeCodeVersion.lastValidated),
                    Self.session("5c1e9a7b-4d2f-4b8a-9e3c-6f0a2d8b1c47", version: "99.0.0", unknown: ["hologram": 2]),
                ])
                let items = await Self.doctor(home, local: FakeLocalControl(status: .success(status)), herdrSocket: server.socketPath).run()

                #expect(items[0] == DoctorItem("mochad", .ok, "rodando · 0.1.0 · no ar há 1 h 05 min · 0 clientes"))
                #expect(items[1].status == .ok)
                #expect(items[2] == DoctorItem("agent.list", .ok, "2 agentes, 2 do Claude Code, 0 do Codex"))
                let transcript = items[9]
                #expect(transcript.status == .warning)
                #expect(transcript.summary == "2 sessões acompanhadas (validado até o Claude \(ClaudeCodeVersion.lastValidated))")
                #expect(transcript.details.count == 2)
                #expect(transcript.details[0].hasPrefix("✅ 0b7e4c2a · w1:p1 · Claude \(ClaudeCodeVersion.lastValidated)"))
                #expect(transcript.details[1].hasPrefix("⚠️ 5c1e9a7b · w1:p1 · Claude 99.0.0"))
                #expect(transcript.details[1].contains("desconhecidos: hologram (2)"))
                #expect(transcript.details[1].contains("versão mais nova que a \(ClaudeCodeVersion.lastValidated) validada"))
            }
        }
    }

    @Test func transcriptItemIsOkForValidatedSessionsAndWarnsOnDroppedLines() {
        let clean = DoctorChecks.transcript(.success(Self.running(sessions: [Self.session("aaaaaaaa-1", version: "2.1.200")])))
        #expect(clean.status == .ok)
        let empty = DoctorChecks.transcript(.success(Self.running()))
        #expect(empty == DoctorItem("Transcript", .ok, "nenhuma sessão acompanhada agora (validado até o Claude \(ClaudeCodeVersion.lastValidated))"))
        let dropped = DoctorChecks.transcript(.success(Self.running(sessions: [Self.session("bbbbbbbb-2", version: nil, dropped: 3)])))
        #expect(dropped.status == .warning)
        #expect(dropped.details[0].contains("linhas descartadas"))
    }

    @Test func apnsItemCombinesConfigSignatureAndKeychain() {
        let config = ApnsConfig(teamId: "TEAM123456", keyId: "ABCDEFGHIJ")
        let ready = DoctorChecks.apns(config: .success(config), signature: .teamSigned, binary: "~/.local/bin/mochad", keychain: { _ in .present })
        #expect(ready.status == .ok)
        #expect(ready.summary == "pronto")
        #expect(ready.details == [
            "✅ config presente (key ABCDEFGHIJ, team TEAM123456)",
            "✅ chave ABCDEFGHIJ no Keychain",
            "✅ ~/.local/bin/mochad assinado pelo time (com.joaoalves.mochad)",
        ])

        let adHoc = DoctorChecks.apns(config: .success(config), signature: .otherSignature("ad-hoc"), binary: "~/.local/bin/mochad", keychain: { _ in .present })
        #expect(adHoc.status == .warning)
        #expect(adHoc.details[2] == "⚠️ ~/.local/bin/mochad sem a assinatura do time (ad-hoc): o Keychain vai pedir autorização")

        let missingKey = DoctorChecks.apns(config: .success(config), signature: .teamSigned, binary: "mochad", keychain: { _ in .missing })
        #expect(missingKey.status == .failure)

        let noConfig = DoctorChecks.apns(config: .success(nil), signature: .teamSigned, binary: "mochad", keychain: { _ in .present })
        #expect(noConfig.status == .warning)
        #expect(noConfig.details.count == 2)
    }

    @Test func apnsItemShowsTheConfigurationErrorsFromLocalStatus() async throws {
        try await withTemporaryHome { home in
            let issue = ApnsConfigurationIssue(environment: .production, status: 403, reason: "BadEnvironmentKeyInToken", at: Self.startedAt)
            let status = Self.running(apns: LocalStatus.Apns(configurationErrors: [issue]))
            let herdrSocket = FakeHerdrServer.temporarySocketPath()
            let apns = await Self.doctor(home, local: FakeLocalControl(status: .success(status)), herdrSocket: herdrSocket).run()[7]

            #expect(apns.title == "APNs")
            #expect(apns.status == .failure)
            #expect(apns.summary == "com pendências")
            #expect(apns.details.last == "❌ o APNs production recusou o último envio com 403 BadEnvironmentKeyInToken: a chave não vale para production; importe uma chave desse ambiente (mochad apns import)")

            let clean = await Self.doctor(home, local: FakeLocalControl(status: .success(Self.running(apns: LocalStatus.Apns(configurationErrors: [])))), herdrSocket: herdrSocket).run()[7]
            #expect(clean.status == .warning)
            #expect(!clean.details.contains { $0.hasPrefix("❌") })
        }
    }

    @Test func doctorChecksTheInstalledBinarySignatureWhenItExists() async throws {
        try await withTemporaryHome { home in
            try home.write("x", to: ".local/bin/mochad", permissions: 0o755)
            let codesign = CodesignSamples.runner(CodesignSamples.teamSigned)
            let doctor = Doctor(
                paths: home.paths,
                herdr: HerdrProbe(socketPath: FakeHerdrServer.temporarySocketPath()),
                local: FakeLocalControl(),
                serve: ServeInspector(tailscale: TailscaleCLI(executable: "/opt/fake/tailscale", runner: TailscaleSamples.runner(serve: "{}")), probe: FakeHttpProbe(.status(200)), gatewayPort: 47421),
                codex: CodexInspector(executable: nil, runner: FakeProcessRunner { _ in ProcessOutput() }),
                signer: CodeSigner(runner: codesign, identities: FakeIdentities(identities: [])),
                keyPresence: FakeKeyPresence(result: .present),
                executable: home.url.appending(path: "build/mochad")
            )
            let apns = await doctor.run()[7]
            #expect(codesign.commands == ["codesign -dr - \(home.paths.installedBinary.path(percentEncoded: false))"])
            #expect(apns.details.contains("✅ ~/.local/bin/mochad assinado pelo time (com.joaoalves.mochad)"))
        }
    }

    @Test func codexItemReadsTheVersionAndProbesTheAppServerSocket() async throws {
        try await withTemporaryHome(short: true) { home in
            let runner = FakeProcessRunner { _ in ProcessOutput(output: "codex-cli 0.157.1\n") }
            let codex = CodexInspector(executable: "/opt/fake/codex", runner: runner)
            let herdrSocket = FakeHerdrServer.temporarySocketPath()
            let socket = home.paths.codexSocket.path(percentEncoded: false)
            let down = await Self.doctor(home, local: FakeLocalControl(), herdrSocket: herdrSocket, codex: codex).run()[5]
            #expect(runner.commands == ["codex --version"])
            #expect(down == DoctorItem(
                "Codex",
                .failure,
                "0.157.1 · /opt/fake/codex · App Server fora do ar",
                details: ["sem o socket \(socket); o mochad sobe o App Server, rode o mochad e confira de novo"]
            ))

            try home.write("", to: "Library/Application Support/Mocha/codex.sock")
            let stale = await Self.doctor(home, local: FakeLocalControl(), herdrSocket: herdrSocket, codex: codex).run()[5]
            #expect(stale.status == .failure)
            #expect(stale.summary == "0.157.1 · /opt/fake/codex · App Server não respondeu ao initialize")
        }
    }

    @Test func codexItemWarnsAboutAVersionNewerThanTheValidatedOne() {
        let server = CodexServerProbe.reachable(CodexServerInfo(version: "0.160.0", signedIn: true, plan: "plus"))
        let item = DoctorChecks.codex(executable: "/opt/fake/codex", version: "0.160.0", server: server)
        #expect(item.status == .warning)
        #expect(item.details == ["versão mais nova que a \(CodexExecutable.lastValidatedVersion) validada"])
    }

    @Test func dataItemFlagsOpenPermissions() async throws {
        try await withTemporaryHome { home in
            #expect(DoctorChecks.dataDirectory(home.paths).status == .warning)
            try home.paths.createSupportDirectory()
            try home.write("{}", to: "Library/Application Support/Mocha/devices.json", permissions: 0o600)
            #expect(DoctorChecks.dataDirectory(home.paths) == DoctorItem("Dados", .ok, "~/Library/Application Support/Mocha 700, arquivos 600"))

            try home.write("{}", to: "Library/Application Support/Mocha/config.json", permissions: 0o644)
            let open = DoctorChecks.dataDirectory(home.paths)
            #expect(open.status == .warning)
            #expect(open.details.count == 1)
            #expect(open.details[0].hasPrefix("chmod 600"))
        }
    }

    @Test func claudeCodeVersionComparison() {
        #expect(ClaudeCodeVersion.isNewer("2.1.284", than: "2.1.283"))
        #expect(ClaudeCodeVersion.isNewer("2.2.0", than: "2.1.283"))
        #expect(ClaudeCodeVersion.isNewer("3", than: "2.1.283"))
        #expect(!ClaudeCodeVersion.isNewer("2.1.283", than: "2.1.283"))
        #expect(!ClaudeCodeVersion.isNewer("2.1.99", than: "2.1.283"))
        #expect(!ClaudeCodeVersion.isNewer("2.1.283-beta.1", than: "2.1.283"))
        #expect(!ClaudeCodeVersion.isNewer(ClaudeCodeVersion.lastValidated))
    }

    @Test func elapsedText() {
        #expect(ElapsedText.since(Self.startedAt, now: Self.startedAt.addingTimeInterval(20)) == "menos de 1 min")
        #expect(ElapsedText.since(Self.startedAt, now: Self.startedAt.addingTimeInterval(59 * 60)) == "59 min")
        #expect(ElapsedText.since(Self.startedAt, now: Self.now) == "1 h 05 min")
        #expect(ElapsedText.since(Self.startedAt, now: Self.startedAt.addingTimeInterval(26 * 3600)) == "1 d 2 h")
    }
}
