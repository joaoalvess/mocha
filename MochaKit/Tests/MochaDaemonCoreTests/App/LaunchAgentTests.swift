import Foundation
import Synchronization
import Testing
@testable import MochaDaemonCore

final class FakeLaunchctl: Sendable {
    private struct State {
        var loaded: Bool
        var bootstrapFailures: Int
    }

    private let state: Mutex<State>

    init(loaded: Bool = false, bootstrapFailures: Int = 0) {
        state = Mutex(State(loaded: loaded, bootstrapFailures: bootstrapFailures))
    }

    func makeRunner() -> FakeProcessRunner {
        FakeProcessRunner { [self] call in handle(call) }
    }

    var loaded: Bool {
        state.withLock { $0.loaded }
    }

    func handle(_ call: ProcessCall) -> ProcessOutput {
        state.withLock { state in
            switch call.arguments.first {
            case "print":
                return state.loaded ? ProcessOutput(output: "state = running") : ProcessOutput(status: 113, output: "", error: "Could not find service")
            case "bootout":
                state.loaded = false
                return ProcessOutput()
            case "bootstrap":
                if state.bootstrapFailures > 0 {
                    state.bootstrapFailures -= 1
                    return ProcessOutput(status: 5, output: "", error: "Bootstrap failed: 5: Input/output error")
                }
                state.loaded = true
                return ProcessOutput()
            default:
                return ProcessOutput(status: 64, output: "", error: "unexpected")
            }
        }
    }
}

@Suite
struct LaunchAgentTests {
    @Test func propertyListRunsTheInstalledBinaryAtLoadAndKeepsItAlive() async throws {
        try await withTemporaryHome { home in
            let agent = LaunchAgent(paths: home.paths, runner: FakeLaunchctl().makeRunner(), userId: 501)
            let plist = try #require(try PropertyListSerialization.propertyList(from: agent.propertyList(), format: nil) as? [String: Any])
            let log = home.paths.logFile.path(percentEncoded: false)

            #expect(plist["Label"] as? String == "com.joaoalves.mochad")
            #expect(plist["ProgramArguments"] as? [String] == [home.paths.installedBinary.path(percentEncoded: false), "run"])
            #expect(plist["RunAtLoad"] as? Bool == true)
            #expect(plist["KeepAlive"] as? Bool == true)
            #expect(plist["StandardOutPath"] as? String == log)
            #expect(plist["StandardErrorPath"] as? String == log)
            #expect(agent.serviceTarget == "gui/501/com.joaoalves.mochad")
        }
    }

    @Test func installWritesThePlistAndBootstrapsTheGuiDomain() async throws {
        try await withTemporaryHome { home in
            let runner = FakeLaunchctl().makeRunner()
            let agent = LaunchAgent(paths: home.paths, runner: runner, userId: 501)

            try await agent.install()

            let plist = home.paths.launchAgentFile.path(percentEncoded: false)
            #expect(runner.commands == ["launchctl print gui/501/com.joaoalves.mochad", "launchctl bootstrap gui/501 \(plist)"])
            #expect(runner.calls.allSatisfy { $0.executable == "/bin/launchctl" })
            #expect(fileMode(home.paths.launchAgentFile) == 0o644)
            #expect(FileManager.default.fileExists(atPath: home.paths.logsDirectory.path(percentEncoded: false)))
            #expect(await agent.isLoaded())
        }
    }

    @Test func reinstallBootsOutTheLoadedServiceFirst() async throws {
        try await withTemporaryHome { home in
            let launchctl = FakeLaunchctl(loaded: true)
            let runner = launchctl.makeRunner()
            let agent = LaunchAgent(paths: home.paths, runner: runner, userId: 501)

            try await agent.install()

            let plist = home.paths.launchAgentFile.path(percentEncoded: false)
            #expect(runner.commands == [
                "launchctl print gui/501/com.joaoalves.mochad",
                "launchctl bootout gui/501/com.joaoalves.mochad",
                "launchctl print gui/501/com.joaoalves.mochad",
                "launchctl bootstrap gui/501 \(plist)",
            ])
            #expect(launchctl.loaded)
        }
    }

    @Test func bootstrapIsRetriedAndThenReported() async throws {
        try await withTemporaryHome { home in
            let flaky = FakeLaunchctl(bootstrapFailures: 1)
            try await LaunchAgent(paths: home.paths, runner: flaky.makeRunner(), userId: 501).install()
            #expect(flaky.loaded)

            let broken = FakeLaunchctl(bootstrapFailures: 3)
            await #expect(throws: LaunchAgentError.bootstrapFailed("Bootstrap failed: 5: Input/output error")) {
                try await LaunchAgent(paths: home.paths, runner: broken.makeRunner(), userId: 501).install()
            }
        }
    }

    @Test func uninstallBootsOutAndRemovesOnlyThePlist() async throws {
        try await withTemporaryHome { home in
            let launchctl = FakeLaunchctl()
            let agent = LaunchAgent(paths: home.paths, runner: launchctl.makeRunner(), userId: 501)
            try await agent.install()
            try home.write("{}", to: "Library/Application Support/Mocha/devices.json", permissions: 0o600)

            #expect(try await agent.uninstall())

            #expect(!launchctl.loaded)
            #expect(!FileManager.default.fileExists(atPath: home.paths.launchAgentFile.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: home.paths.devicesFile.path(percentEncoded: false)))
            #expect(try await agent.uninstall() == false)
        }
    }
}
