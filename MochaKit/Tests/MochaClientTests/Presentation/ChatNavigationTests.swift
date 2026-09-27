import MochaProtocol
import Testing
@testable import MochaClient

struct ChatNavigationTests {
    private let agent = ChatTarget.agent("w1:p1")
    private let loadTest = ChatTarget.subagent(sessionId: "s-1", agentId: "a0123456789abcdef")
    private let nested = ChatTarget.subagent(sessionId: "s-1", agentId: "a76543210fedcba98")

    private func stack(_ targets: ChatTarget...) -> [ChatStackEntry] {
        targets.map { ChatStackEntry(route: $0, target: $0) }
    }

    @Test func subagentIsPushedOverTheParentChatWithoutClosingIt() {
        #expect(ChatNavigation.open(loadTest, stack: stack(agent)) == .show(path: [agent, loadTest], closing: []))
    }

    @Test func nestedSubagentIsPushedOverAnotherTranscript() {
        #expect(ChatNavigation.open(nested, stack: stack(agent, loadTest)) == .show(path: [agent, loadTest, nested], closing: []))
    }

    @Test func subagentFromTheDetailOverHomeOpensAlone() {
        #expect(ChatNavigation.open(loadTest, stack: []) == .show(path: [loadTest], closing: []))
    }

    @Test func visibleSubagentStays() {
        #expect(ChatNavigation.open(loadTest, stack: stack(agent, loadTest)) == .stay)
    }

    @Test func agentChatReplacesTheWholeStackAndClosesEveryChat() {
        let other = ChatTarget.agent("w2:p1")
        #expect(ChatNavigation.open(other, stack: stack(agent, loadTest, nested)) == .show(path: [other], closing: [agent, loadTest, nested]))
    }

    @Test func targetAlreadyInTheStackPopsBackToIt() {
        #expect(ChatNavigation.open(agent, stack: stack(agent, loadTest, nested)) == .show(path: [agent], closing: [loadTest, nested]))
        #expect(ChatNavigation.open(loadTest, stack: stack(agent, loadTest, nested)) == .show(path: [agent, loadTest], closing: [nested]))
    }

    @Test func backClosesOnlyTheTopChat() {
        #expect(ChatNavigation.back(stack: stack(agent, loadTest, nested)) == .show(path: [agent, loadTest], closing: [nested]))
        #expect(ChatNavigation.back(stack: stack(agent)) == .show(path: [], closing: [agent]))
        #expect(ChatNavigation.back(stack: []) == .stay)
    }

    @Test func swipingBackClosesEveryChatThatLeftTheStack() {
        let entries = stack(agent, loadTest, nested)
        #expect(ChatNavigation.setPath([agent, loadTest], stack: entries) == .show(path: [agent, loadTest], closing: [nested]))
        #expect(ChatNavigation.setPath([], stack: entries) == .show(path: [], closing: [agent, loadTest, nested]))
        #expect(ChatNavigation.setPath([agent, loadTest, nested], stack: entries) == .stay)
    }

    @Test func closingUsesTheLiveTargetOfAMovedAgent() {
        let entries = [ChatStackEntry(route: agent, target: .agent("w9:p4")), ChatStackEntry(route: loadTest, target: loadTest)]
        #expect(ChatNavigation.setPath([], stack: entries) == .show(path: [], closing: [.agent("w9:p4"), loadTest]))
    }

    @Test func reconnectionReopensTheVisibleChatAndTheOnesBelow() {
        let entries = [ChatStackEntry(route: agent, target: .agent("w9:p4")), ChatStackEntry(route: loadTest, target: loadTest)]
        #expect(ChatNavigation.reopening(stack: entries) == [.agent("w9:p4"), loadTest])
        #expect(ChatNavigation.reopening(stack: []) == [])
    }
}
