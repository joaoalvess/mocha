import MochaProtocol
import Testing
@testable import MochaClient

struct ForegroundReporterTests {
    @Test func reportsOpeningSwitchingAndClosingAChat() {
        var reporter = ForegroundReporter()
        #expect(reporter.message(agentId: nil, isActive: true) == .setForeground(agentId: nil, isActive: true))
        #expect(reporter.message(agentId: "w1:p1", isActive: true) == .setForeground(agentId: "w1:p1", isActive: true))
        #expect(reporter.message(agentId: "w2:p1", isActive: true) == .setForeground(agentId: "w2:p1", isActive: true))
        #expect(reporter.message(agentId: nil, isActive: true) == .setForeground(agentId: nil, isActive: true))
    }

    @Test func reportsGoingToTheBackgroundOnce() {
        var reporter = ForegroundReporter()
        _ = reporter.message(agentId: "w1:p1", isActive: true)
        #expect(reporter.message(agentId: "w1:p1", isActive: false) == .setForeground(agentId: "w1:p1", isActive: false))
        #expect(reporter.message(agentId: "w1:p1", isActive: false) == nil)
    }

    @Test func repeatedStateIsNotSentAgain() {
        var reporter = ForegroundReporter()
        _ = reporter.message(agentId: "w1:p1", isActive: true)
        #expect(reporter.message(agentId: "w1:p1", isActive: true) == nil)
    }

    @Test func newConnectionGetsTheCurrentStateAgain() {
        var reporter = ForegroundReporter()
        _ = reporter.message(agentId: "w1:p1", isActive: true)
        reporter.connectionClosed()
        #expect(reporter.message(agentId: "w1:p1", isActive: true) == .setForeground(agentId: "w1:p1", isActive: true))
    }
}
