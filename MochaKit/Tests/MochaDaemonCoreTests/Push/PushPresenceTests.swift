import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PushPresenceTests {
    @Test func atTheMacAlertsAreSilencedAndTheMostUrgentUnseenOneGoesOnLock() async throws {
        let audience = FakePushAudience(agents: [Sample.agent("w1:p1", sessionId: Sample.sessionA), Sample.agent("w2:p1", status: .blocked)])
        audience.setHerdrStatus(.done, for: "w1:p1")
        try await withPush(audience: audience) { harness in
            try await harness.device()
            await harness.service.presenceChanged(to: .unlocked)
            await harness.deliver(PushHooks.stop("parser pronto"))
            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"), agent: "w2:p1")
            #expect(harness.transport.requests.isEmpty)

            await harness.service.presenceChanged(to: .locked)
            await harness.service.waitForDeliveries()
            #expect(try harness.payloads().map { $0["agentId"] as? String } == ["w2:p1"])
            #expect(try harness.payloads().map { $0["kind"] as? String } == ["needsInput"])

            await harness.service.presenceChanged(to: .unlocked)
            await harness.service.presenceChanged(to: .locked)
            await harness.service.waitForDeliveries()
            #expect(harness.transport.requests.count == 1)
        }
    }

    @Test func aTurnDoneSeenOnTheMacDoesNotGoOnLock() async throws {
        let audience = FakePushAudience()
        audience.setHerdrStatus(.idle, for: "w1:p1")
        try await withPush(audience: audience) { harness in
            try await harness.device()
            await harness.service.presenceChanged(to: .unlocked)
            await harness.deliver(PushHooks.stop())
            await harness.service.presenceChanged(to: .locked)
            await harness.service.waitForDeliveries()
            #expect(harness.transport.requests.isEmpty)
        }
    }

    @Test func theToggleIsPerDeviceAndAnUnknownLockCountsAsAway() async throws {
        let audience = FakePushAudience()
        audience.setHerdrStatus(.done, for: "w1:p1")
        try await withPush(audience: audience) { harness in
            let phone = try await harness.device("iPhone")
            try await harness.device("iPad", token: PushHarness.otherToken)
            #expect(try await harness.devices.setPreferences(DevicePreferences(turnDoneAlerts: true, silenceWhileAtMac: false), for: phone.id))
            await harness.service.presenceChanged(to: .unlocked)
            await harness.deliver(PushHooks.stop())
            #expect(harness.transport.requests.compactMap { $0.url?.lastPathComponent } == [PushTestData.deviceToken])

            await harness.service.presenceChanged(to: .unknown)
            await harness.service.waitForDeliveries()
            #expect(harness.transport.requests.compactMap { $0.url?.lastPathComponent } == [PushTestData.deviceToken, PushHarness.otherToken])

            await harness.deliver(PushHooks.stop())
            #expect(harness.transport.requests.count == 4)
        }
    }
}
