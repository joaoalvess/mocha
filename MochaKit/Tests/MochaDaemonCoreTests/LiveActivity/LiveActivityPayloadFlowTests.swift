import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityPayloadFlowTests {
    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func contentState(_ aps: [String: Any]) throws -> [String: Any] {
        try #require(aps["content-state"] as? [String: Any])
    }

    @Test func contentStateDatesAreSecondsSince2001AndApsDatesAreUnixSeconds() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working)])
            try await harness.registerUpdateToken(for: device)
            try await harness.advance(10)
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o lexer")])
            try await harness.agents([])
            try await harness.advance(10)
            #expect(harness.sent.map(\.push.event.name) == ["start", "update", "end"])

            let start = try harness.aps(harness.sent[0])
            #expect(start["timestamp"] as? Int == 1_790_000_000)
            #expect(start["stale-date"] as? Int == 1_790_000_900)
            #expect(try contentState(start)["updatedAt"] as? Double == 811_692_800)
            #expect(try contentState(start)["since"] as? Double == 811_692_800)

            let update = try harness.aps(harness.sent[1])
            #expect(update["timestamp"] as? Int == 1_790_000_010)
            #expect(update["stale-date"] as? Int == 1_790_000_910)
            #expect(try contentState(update)["updatedAt"] as? Double == 811_692_810)
            #expect(try contentState(update)["since"] as? Double == 811_692_800)

            let end = try harness.aps(harness.sent[2])
            #expect(end["timestamp"] as? Int == 1_790_000_020)
            #expect(end["dismissal-date"] as? Int == 1_790_000_020)
            #expect(end["stale-date"] == nil)
            #expect(try contentState(end)["updatedAt"] as? Double == 811_692_820)

            #expect(try LiveActivityAppContentState.decoding(harness.sent[1].push) == LiveActivityAppContentState(
                status: "working",
                title: "Refatorar o lexer",
                workspaceLabel: "demo-app",
                since: at(0),
                updatedAt: at(10)
            ))
            #expect(try LiveActivityAppContentState.decoding(harness.sent[2].push).title == "Refatorar o lexer")
        }
    }
}
