import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityPayloadFlowTests {
    private struct SystemContentState: Decodable, Equatable {
        struct Highlight: Decodable, Equatable {
            var agentId: String
            var title: String
            var workspaceLabel: String
            var status: String
            var since: Date
        }

        var working: Int
        var waiting: Int
        var highlight: Highlight?
        var updatedAt: Date
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func contentState(_ aps: [String: Any]) throws -> [String: Any] {
        try #require(aps["content-state"] as? [String: Any])
    }

    private func systemDecoded(_ sent: FakeLiveActivitySender.Sent) throws -> SystemContentState {
        let aps = try #require(try PushTestData.jsonObject(try sent.push.payload())["aps"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: try contentState(aps))
        return try JSONDecoder().decode(SystemContentState.self, from: data)
    }

    @Test func contentStateDatesAreSecondsSince2001AndApsDatesAreUnixSeconds() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working)])
            try await harness.registerUpdateToken(for: device)
            try await harness.advance(10)
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working), LiveActivitySample.agent("w2:p1", .working)])
            try await harness.agents([LiveActivitySample.agent("w1:p1", .idle)])
            try await harness.advance(10)
            try await harness.advance(50)
            #expect(harness.sent.map(\.push.event.name) == ["start", "update", "update", "end"])

            let start = try harness.aps(harness.sent[0])
            #expect(start["timestamp"] as? Int == 1_790_000_000)
            #expect(try contentState(start)["updatedAt"] as? Double == 811_692_800)
            let startHighlight = try #require(try contentState(start)["highlight"] as? [String: Any])
            #expect(startHighlight["since"] as? Double == 811_692_800)
            #expect(start["stale-date"] == nil)

            let update = try harness.aps(harness.sent[1])
            #expect(update["timestamp"] as? Int == 1_790_000_010)
            #expect(update["stale-date"] as? Int == 1_790_000_910)
            #expect(try contentState(update)["updatedAt"] as? Double == 811_692_810)
            let updateHighlight = try #require(try contentState(update)["highlight"] as? [String: Any])
            #expect(updateHighlight["since"] as? Double == 811_692_800)

            let end = try harness.aps(harness.sent[3])
            #expect(end["timestamp"] as? Int == 1_790_000_070)
            #expect(end["dismissal-date"] as? Int == 1_790_000_970)
            #expect(end["stale-date"] == nil)
            #expect(try contentState(end)["updatedAt"] as? Double == 811_692_870)
            #expect(try contentState(end)["highlight"] == nil)

            #expect(
                try systemDecoded(harness.sent[1]) == SystemContentState(
                    working: 2,
                    waiting: 0,
                    highlight: .init(agentId: "w1:p1", title: "Refatorar o parser", workspaceLabel: "demo-app", status: "working", since: at(0)),
                    updatedAt: at(10)
                )
            )
            #expect(try systemDecoded(harness.sent[3]) == SystemContentState(working: 0, waiting: 0, highlight: nil, updatedAt: at(70)))
        }
    }
}
