import Foundation
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PresenceMonitorTests {
    @Test func currentReadsTheConsoleLockRightAway() async {
        let reader = FakeConsoleLock(.unlocked)
        let monitor = PresenceMonitor(reader: reader, clock: ManualClock())
        #expect(await monitor.current() == .unlocked)
        reader.set(.locked)
        #expect(await monitor.current() == .locked)
    }

    @Test func pollingReportsEachTransitionOnce() async throws {
        let reader = FakeConsoleLock(.unlocked)
        let clock = ManualClock()
        let monitor = PresenceMonitor(reader: reader, clock: clock, interval: .seconds(3))
        var transitions = await monitor.transitions().makeAsyncIterator()
        await monitor.start()
        try await clock.waitForSleepers(1)
        reader.set(.locked)
        clock.advance(by: .seconds(3))
        #expect(await transitions.next() == .locked)
        try await clock.waitForSleepers(1)
        clock.advance(by: .seconds(3))
        try await clock.waitForSleepers(1)
        reader.set(.unknown)
        clock.advance(by: .seconds(3))
        #expect(await transitions.next() == .unknown)
        await monitor.shutdown()
        #expect(await transitions.next() == nil)
    }

    @Test func theFirstReadIsNotATransition() async throws {
        let reader = FakeConsoleLock(.locked)
        let clock = ManualClock()
        let monitor = PresenceMonitor(reader: reader, clock: clock)
        var transitions = await monitor.transitions().makeAsyncIterator()
        await monitor.start()
        try await clock.waitForSleepers(1)
        reader.set(.unlocked)
        clock.advance(by: PresenceMonitor.pollInterval)
        #expect(await transitions.next() == .unlocked)
        await monitor.shutdown()
    }

    @Test func everySubscriberGetsTheTransition() async throws {
        let reader = FakeConsoleLock(.unlocked)
        let monitor = PresenceMonitor(reader: reader, clock: ManualClock())
        await monitor.current()
        var first = await monitor.transitions().makeAsyncIterator()
        var second = await monitor.transitions().makeAsyncIterator()
        reader.set(.locked)
        await monitor.current()
        #expect(await first.next() == .locked)
        #expect(await second.next() == .locked)
        await monitor.shutdown()
    }

    @Test func onlyAnUnlockedConsoleCountsAsAtTheMac() {
        #expect(ConsoleLock.unlocked.isAtMac)
        #expect(!ConsoleLock.locked.isAtMac)
        #expect(!ConsoleLock.unknown.isAtMac)
    }
}

@Suite(.tags(.integration), .enabled(if: PresenceIntegrationGate.isEnabled))
struct ConsoleLockIntegrationTests {
    @Test func theRealRegistryAnswersWithAKnownState() {
        #expect(IORegistryConsoleLockReader().consoleLock() != .unknown)
    }
}

enum PresenceIntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCHA_INTEGRATION"] == "1"
    }
}
