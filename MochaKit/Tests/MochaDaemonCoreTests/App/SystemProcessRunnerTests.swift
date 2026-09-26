import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SystemProcessRunnerTests {
    @Test func extraEnvironmentIsAddedToTheInheritedOne() async throws {
        let output = try await SystemProcessRunner().run("/usr/bin/env", [], environment: ["MOCHA_TEST_FLAG": "1"], timeout: .seconds(10))
        let lines = output.outputText.split(separator: "\n")
        #expect(output.succeeded)
        #expect(lines.contains("MOCHA_TEST_FLAG=1"))
        #expect(lines.contains { $0.hasPrefix("HOME=") })
    }

    @Test func failureKeepsStatusAndStandardError() async throws {
        let output = try await SystemProcessRunner().run("/bin/sh", ["-c", "echo saída; echo falhou >&2; exit 3"], timeout: .seconds(10))
        #expect(output.status == 3)
        #expect(output.outputText == "saída\n")
        #expect(output.message == "falhou")
    }

    @Test func slowProcessIsTerminated() async throws {
        let started = ContinuousClock.now
        await #expect(throws: ProcessRunnerError.timedOut("/bin/sleep 30")) {
            try await SystemProcessRunner().run("/bin/sleep", ["30"], timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func missingExecutableIsReported() async throws {
        await #expect(throws: ProcessRunnerError.notExecutable("/nao/existe/tailscale")) {
            try await SystemProcessRunner().run("/nao/existe/tailscale", [], timeout: .seconds(1))
        }
    }
}
