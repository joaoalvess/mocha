import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct DaemonInstallerTests {
    static let identity = SigningIdentity(sha1: "6A2D0785CB9649549AD65065E1DA14DB4CED877E", name: "Apple Development: Test (ABCDE12345)", organizationalUnits: ["TEAM123456"])

    static func installer(_ home: TemporaryHome, identities: [SigningIdentity] = [identity]) -> (DaemonInstaller, FakeProcessRunner, FakeLaunchctl) {
        let launchctl = FakeLaunchctl()
        let runner = FakeProcessRunner { call in
            call.executable == LaunchAgent.launchctl ? launchctl.handle(call) : ProcessOutput()
        }
        let installer = DaemonInstaller(
            paths: home.paths,
            runner: runner,
            signer: CodeSigner(runner: runner, identities: FakeIdentities(identities: identities)),
            userId: 501
        )
        return (installer, runner, launchctl)
    }

    static func builtBinary(_ home: TemporaryHome, team: String = "TEAM123456") throws -> URL {
        try home.write("DEVELOPMENT_TEAM = \(team)\n", to: "repo/Config/Signing.xcconfig")
        try home.write("mochad release", to: "repo/MochaKit/.build/release/mochad", permissions: 0o755)
        return home.url.appending(path: "repo/MochaKit/.build/release/mochad")
    }

    @Test func installCopiesSignsWithTheTeamIdentityAndBootstraps() async throws {
        try await withTemporaryHome { home in
            let (installer, runner, launchctl) = Self.installer(home)
            let source = try Self.builtBinary(home)

            let report = try await installer.install(executable: source)

            let installed = home.paths.installedBinary
            #expect(report == InstallReport(binary: installed, copied: true, signing: .signed(identity: Self.identity.name), generatedHookSecret: true))
            #expect(try String(contentsOf: installed, encoding: .utf8) == "mochad release")
            #expect(fileMode(installed) == 0o755)
            #expect(runner.calls.contains(ProcessCall(
                executable: "/usr/bin/codesign",
                arguments: ["--force", "--sign", Self.identity.sha1, "--identifier", "com.joaoalves.mochad", "--options", "runtime", installed.path(percentEncoded: false)]
            )))
            #expect(launchctl.loaded)
            #expect(fileMode(home.paths.supportDirectory) == 0o700)
            #expect(fileMode(home.paths.configFile) == 0o600)
            #expect(try DaemonConfigStore(url: home.paths.configFile).read().hookSecret != nil)
        }
    }

    @Test func missingIdentityInstallsUnsignedAndSaysSo() async throws {
        try await withTemporaryHome { home in
            let (installer, runner, launchctl) = Self.installer(home, identities: [])
            let report = try await installer.install(executable: try Self.builtBinary(home))

            #expect(report.signing == .missingIdentity(team: "TEAM123456"))
            #expect(!runner.calls.contains { $0.executable == "/usr/bin/codesign" })
            #expect(launchctl.loaded)
        }
    }

    @Test func runningTheInstalledBinaryKeepsItAndItsSignature() async throws {
        try await withTemporaryHome { home in
            try home.write("assinado", to: ".local/bin/mochad", permissions: 0o755)
            try home.write(#"{"hookSecret":"existente","apns":{"keyId":"K"}}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let (installer, runner, _) = Self.installer(home)

            let report = try await installer.install(executable: home.paths.installedBinary)

            #expect(report == InstallReport(binary: home.paths.installedBinary, copied: false, signing: .keptExisting, generatedHookSecret: false))
            #expect(!runner.calls.contains { $0.executable == "/usr/bin/codesign" })
            #expect(try String(contentsOf: home.paths.installedBinary, encoding: .utf8) == "assinado")
        }
    }

    @Test func binaryOutsideTheRepositoryHasNoTeam() async throws {
        try await withTemporaryHome { home in
            try home.write("solto", to: "Downloads/mochad", permissions: 0o755)
            let (installer, _, _) = Self.installer(home)
            let report = try await installer.install(executable: home.url.appending(path: "Downloads/mochad"))
            #expect(report.signing == .missingTeam)
        }
    }

    @Test func uninstallStopsTheAgentAndKeepsTheData() async throws {
        try await withTemporaryHome { home in
            let (installer, _, launchctl) = Self.installer(home)
            _ = try await installer.install(executable: try Self.builtBinary(home))

            #expect(try await installer.uninstall())

            #expect(!launchctl.loaded)
            #expect(FileManager.default.fileExists(atPath: home.paths.configFile.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: home.paths.installedBinary.path(percentEncoded: false)))
        }
    }
}
