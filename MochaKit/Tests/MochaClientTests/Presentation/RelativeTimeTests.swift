import Foundation
import Testing
@testable import MochaClient

struct RelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    static let cases: [(elapsed: Int, expected: String)] = [
        (0, "agora"),
        (59, "agora"),
        (60, "há 1 min"),
        (299, "há 4 min"),
        (3_599, "há 59 min"),
        (3_600, "há 1 h"),
        (86_399, "há 23 h"),
        (86_400, "ontem"),
        (172_799, "ontem"),
        (172_800, "há 2 dias"),
        (777_605, "há 9 dias"),
    ]

    @Test(arguments: cases)
    func formatsElapsedTime(elapsed: Int, expected: String) {
        #expect(RelativeTime.text(from: now.addingTimeInterval(-TimeInterval(elapsed)), now: now) == expected)
    }

    @Test func futureDatesReadAsNow() {
        #expect(RelativeTime.text(from: now.addingTimeInterval(90), now: now) == "agora")
    }
}
