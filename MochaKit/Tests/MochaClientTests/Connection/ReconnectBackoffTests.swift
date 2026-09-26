import Testing
@testable import MochaClient

struct ReconnectBackoffTests {
    @Test func followsTheSpecSequenceWithoutJitter() {
        var backoff = ReconnectBackoff()
        let delays = (0..<7).map { _ in backoff.nextDelay(jitter: 1) }
        #expect(delays == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(8), .seconds(8)])
    }

    @Test func appliesTheJitterAndCapsAtEightSeconds() {
        var low = ReconnectBackoff()
        var high = ReconnectBackoff()
        let lows = (0..<5).map { _ in low.nextDelay(jitter: 0.8) }
        let highs = (0..<5).map { _ in high.nextDelay(jitter: 1.2) }
        #expect(lows == [.milliseconds(400), .milliseconds(800), .milliseconds(1600), .milliseconds(3200), .milliseconds(6400)])
        #expect(highs == [.milliseconds(600), .milliseconds(1200), .milliseconds(2400), .milliseconds(4800), .seconds(8)])
    }

    @Test func clampsJitterOutsideTheRange() {
        var backoff = ReconnectBackoff()
        let aboveRange = backoff.nextDelay(jitter: 5)
        let belowRange = backoff.nextDelay(jitter: 0)
        #expect(aboveRange == .milliseconds(600))
        #expect(belowRange == .milliseconds(800))
    }

    @Test func resetStartsOverFromHalfASecond() {
        var backoff = ReconnectBackoff()
        _ = backoff.nextDelay(jitter: 1)
        _ = backoff.nextDelay(jitter: 1)
        _ = backoff.nextDelay(jitter: 1)
        backoff.reset()
        #expect(backoff.failures == 0)
        let first = backoff.nextDelay(jitter: 1)
        #expect(first == .milliseconds(500))
    }

    @Test func randomJitterStaysInRange() {
        for _ in 0..<200 {
            #expect(ReconnectBackoff.jitterRange.contains(ReconnectBackoff.randomJitter()))
        }
    }
}
