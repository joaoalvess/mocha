import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoOfflineTests {
    private static let offline = DemoOptions(
        dropsConnectionAfterTree: true,
        connectDelay: .milliseconds(5),
        echoDelay: .milliseconds(5),
        replyDelay: .milliseconds(5)
    )

    @Test func dropsTheConnectionRightAfterTreeArchivedAndUsage() async throws {
        let harness = try DemoHarness(Self.offline)
        try await harness.connect()

        #expect(try await harness.states.next() == .waitingToRetry(.unreachable))
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-1")
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await harness.states.unread().isEmpty)
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func staysOfflineWhenStartedAgainAndIgnoresTheScript() async throws {
        var options = DemoOptions.script
        options.dropsConnectionAfterTree = true
        let harness = try DemoHarness(options)
        try await harness.connect()
        #expect(try await harness.states.next() == .waitingToRetry(.unreachable))

        await harness.connection.start()
        try await Task.sleep(for: DemoScript.steps[0].delay * DemoOptions.scriptScale * 4)
        #expect(await harness.states.unread().isEmpty)
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func isOffByDefault() {
        #expect(!DemoOptions().dropsConnectionAfterTree)
    }
}
