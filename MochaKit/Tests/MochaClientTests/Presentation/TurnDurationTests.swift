import Foundation
import Testing
@testable import MochaClient

struct TurnDurationTests {
    static let cases: [(seconds: Int, expected: String)] = [
        (0, "0s"),
        (45, "45s"),
        (59, "59s"),
        (60, "1m 0s"),
        (238, "3m 58s"),
        (3_599, "59m 59s"),
        (3_600, "1h 0m"),
        (3_725, "1h 2m"),
        (-5, "0s"),
    ]

    @Test(arguments: cases)
    func formatsSeconds(seconds: Int, expected: String) {
        #expect(TurnDuration.text(seconds: seconds) == expected)
    }

    @Test func formatsMillisecondsRoundingDown() {
        #expect(TurnDuration.text(milliseconds: 45_999) == "45s")
        #expect(TurnDuration.text(milliseconds: 238_400) == "3m 58s")
    }

    @Test func formatsIntervalBetweenDates() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(TurnDuration.text(from: start, to: start.addingTimeInterval(238.9)) == "3m 58s")
        #expect(TurnDuration.text(from: start, to: start.addingTimeInterval(-3)) == "0s")
    }
}
