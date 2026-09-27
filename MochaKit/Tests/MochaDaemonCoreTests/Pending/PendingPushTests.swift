import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PendingPushTests {
    static func deliver(_ harness: PushHarness, _ file: String, requestId: RequestID?) async throws {
        let event = try PushHooks.fixture(.permissionRequest, file)
        await harness.service.handle(ReceivedHook(agentId: "w1:p1", receivedAt: harness.clock.now(), event: event, requestId: requestId))
        await harness.service.waitForDeliveries()
    }

    @Test func aPendingRequestAlertsAtOnceWithItsCategoryAndRequestId() async throws {
        try await withPush { harness in
            try await harness.device()

            try await Self.deliver(harness, "PermissionRequest.bash.json", requestId: "req-bash")
            try await Self.deliver(harness, "PermissionRequest.AskUserQuestion.multi.json", requestId: "req-question")

            #expect(harness.transport.requests.count == 2)
            #expect(harness.transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "apns-priority") == "10" })
            #expect(harness.transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "apns-collapse-id") == "w1:p1" })
            let payloads = try harness.payloads()
            let aps = payloads.compactMap { $0["aps"] as? [String: Any] }
            #expect(aps.map { $0["category"] as? String } == ["PERMISSION", "NEEDS_INPUT"])
            #expect(aps.allSatisfy { $0["interruption-level"] as? String == "time-sensitive" })
            #expect(aps.map { ($0["alert"] as? [String: Any])?["body"] as? String } == ["touch f.txt", "Qual editor?"])
            #expect(aps.map { ($0["alert"] as? [String: Any])?["title"] as? String } == ["Claude precisa de você · Core", "Claude precisa de você · Core"])
            #expect(payloads.map { $0["requestId"] as? String } == ["req-bash", "req-question"])
            #expect(payloads.allSatisfy { $0["kind"] as? String == "needsInput" })
        }
    }

    @Test func secondarySignalsStaySilentWhileTheAgentHasAPendingRequest() async throws {
        var agent = Sample.agent("w1:p1", sessionId: Sample.sessionA)
        agent.pendingCount = 1
        try await withPush(audience: FakePushAudience(agents: [agent])) { harness in
            try await harness.device()

            await harness.deliver(PushHooks.notification())
            await harness.service.agentStatusChanged("w1:p1", to: .blocked)
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()

            #expect(harness.transport.requests.isEmpty)
        }
    }
}
