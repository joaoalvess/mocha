import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct CodexPaneMatcherTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let project = "/Users/dev/projects/mocha"

    @Test func threadStartedAfterTheTabOpensGoesToTheWaitingPane() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.threadStarted("t-1", cwd: Self.project, at: Self.start.addingTimeInterval(3)) == "w1:p2")
        #expect(matcher.expected.isEmpty)
        #expect(matcher.started.isEmpty)
    }

    @Test func threadThatStartedBeforeTheExpectationIsPickedUpLater() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.threadStarted("t-1", cwd: Self.project, at: Self.start.addingTimeInterval(2)) == nil)
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start.addingTimeInterval(4)) == "t-1")
        #expect(matcher.started.isEmpty)
    }

    @Test func threadOlderThanTheTabIsNotMatched() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.threadStarted("old", cwd: Self.project, at: Self.start.addingTimeInterval(-1)) == nil)
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.threadStarted("new", cwd: Self.project, at: Self.start.addingTimeInterval(1)) == "w1:p2")
    }

    @Test func threadStartedBeforeThePaneWasExpectedStaysUnmatched() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.threadStarted("t-0", cwd: Self.project, at: Self.start.addingTimeInterval(-5)) == nil)
        #expect(matcher.expected.map(\.paneId) == ["w1:p2"])
    }

    @Test func otherDirectoriesDoNotMatch() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.threadStarted("t-1", cwd: "/Users/dev/projects/other", at: Self.start.addingTimeInterval(1)) == nil)
        #expect(matcher.threadStarted("t-2", cwd: Self.project, at: Self.start.addingTimeInterval(2)) == "w1:p2")
    }

    @Test func directoriesAreComparedAfterNormalization() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project + "/", since: Self.start, now: Self.start) == nil)
        #expect(matcher.threadStarted("t-1", cwd: "/Users/dev/projects/./mocha/sub/..", at: Self.start.addingTimeInterval(1)) == "w1:p2")
    }

    @Test func panesInTheSameDirectoryAreServedInOrder() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.expect("w1:p3", cwd: Self.project, since: Self.start.addingTimeInterval(1), now: Self.start.addingTimeInterval(1)) == nil)
        #expect(matcher.threadStarted("t-1", cwd: Self.project, at: Self.start.addingTimeInterval(2)) == "w1:p2")
        #expect(matcher.threadStarted("t-2", cwd: Self.project, at: Self.start.addingTimeInterval(3)) == "w1:p3")
    }

    @Test func expectingThePaneAgainReplacesTheOldExpectation() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.expect("w1:p2", cwd: "/Users/dev/projects/other", since: Self.start, now: Self.start) == nil)
        #expect(matcher.expected.map(\.cwd) == ["/Users/dev/projects/other"])
        #expect(matcher.threadStarted("t-1", cwd: Self.project, at: Self.start.addingTimeInterval(1)) == nil)
    }

    @Test func forgottenPanesAreNoLongerMatched() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        matcher.forget("w1:p2")
        #expect(matcher.threadStarted("t-1", cwd: Self.project, at: Self.start.addingTimeInterval(1)) == nil)
        #expect(matcher.started.map(\.threadId) == ["t-1"])
    }

    @Test func entriesExpireAfterTheWindow() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        let late = Self.start.addingTimeInterval(CodexPaneMatcher.window + 1)
        #expect(matcher.threadStarted("t-1", cwd: Self.project, at: late) == nil)
        #expect(matcher.expected.isEmpty)
        #expect(matcher.expect("w1:p3", cwd: Self.project, since: late, now: late.addingTimeInterval(CodexPaneMatcher.window + 1)) == nil)
        #expect(matcher.started.isEmpty)
    }

    @Test func resetDropsEverything() {
        var matcher = CodexPaneMatcher()
        #expect(matcher.expect("w1:p2", cwd: Self.project, since: Self.start, now: Self.start) == nil)
        #expect(matcher.threadStarted("t-1", cwd: "/Users/dev/projects/other", at: Self.start) == nil)
        matcher.reset()
        #expect(matcher.expected.isEmpty)
        #expect(matcher.started.isEmpty)
    }
}
