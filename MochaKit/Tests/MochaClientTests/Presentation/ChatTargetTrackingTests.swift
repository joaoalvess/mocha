import MochaProtocol
import Testing
@testable import MochaClient

struct ChatTargetTrackingTests {
    private let workspaces = PresentationSamples.workspaces

    @Test func sameSessionIsUnchanged() {
        #expect(ChatTargetTracking.change(for: .agent("w5:p1"), knownSessionId: "s-login", in: workspaces) == .unchanged)
    }

    @Test func learnsSessionOfAgentOpenedBeforeTheTree() {
        #expect(ChatTargetTracking.change(for: .agent("w5:p1"), knownSessionId: nil, in: workspaces) == .learnedSession("s-login"))
    }

    @Test func detectsSessionSwitchAfterClear() {
        #expect(ChatTargetTracking.change(for: .agent("w5:p1"), knownSessionId: "s-old", in: workspaces) == .sessionSwitched("s-login"))
    }

    @Test func followsAgentThatChangedIdKeepingTheSession() {
        #expect(ChatTargetTracking.change(for: .agent("w9:p1"), knownSessionId: "s-login", in: workspaces) == .agentMoved("w5:p1"))
    }

    @Test func vanishedAgentWithoutMatchIsUnchanged() {
        #expect(ChatTargetTracking.change(for: .agent("w9:p1"), knownSessionId: "s-gone", in: workspaces) == .unchanged)
        #expect(ChatTargetTracking.change(for: .agent("w9:p1"), knownSessionId: nil, in: workspaces) == .unchanged)
    }

    @Test func agentWithoutSessionIsUnchanged() {
        #expect(ChatTargetTracking.change(for: .agent("w1:p2"), knownSessionId: nil, in: workspaces) == .unchanged)
    }

    @Test func archivedSessionTargetIsUnchanged() {
        #expect(ChatTargetTracking.change(for: .session("s-login"), knownSessionId: "s-login", in: workspaces) == .unchanged)
    }
}
