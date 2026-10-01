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

    @Test func codexChildThreadIsPushedOverTheLiveCodexChat() {
        let codex = ChatTarget.agent("w3:p5")
        let child = ChatTarget.codexThread("9f5e4d3c-6a7b-4c8d-9e0f-2a3b4c5d6e7f")
        #expect(ChatNavigation.openSubagent(child, stack: stack(codex)) == .show(path: [codex, child], closing: []))
        #expect(ChatNavigation.openSubagent(child, stack: stack(codex, child)) == .stay)
    }

    @Test func codexChildThreadIsPushedOverTheArchivedCodexChat() {
        let archived = ChatTarget.codexThread("a06f5e4d-7b8c-4d9e-8f0a-3b4c5d6e7f80")
        let child = ChatTarget.codexThread("b1706f5e-8c9d-4e0f-9a1b-4c5d6e7f8091")
        #expect(ChatNavigation.openSubagent(child, stack: stack(archived)) == .show(path: [archived, child], closing: []))
        #expect(ChatNavigation.openSubagent(archived, stack: stack(archived, child)) == .show(path: [archived], closing: [child]))
    }

    @Test func codexChildThreadFromTheDetailOverHomeOpensAlone() {
        let child = ChatTarget.codexThread("9f5e4d3c-6a7b-4c8d-9e0f-2a3b4c5d6e7f")
        #expect(ChatNavigation.openSubagent(child, stack: []) == .show(path: [child], closing: []))
    }

    @Test func archivedCodexThreadOpenedNormallyReplacesTheStack() {
        let codex = ChatTarget.agent("w3:p5")
        let archived = ChatTarget.codexThread("a06f5e4d-7b8c-4d9e-8f0a-3b4c5d6e7f80")
        #expect(ChatNavigation.open(archived, stack: stack(codex)) == .show(path: [archived], closing: [codex]))
    }

    @Test func claudeSubagentOpensTheSameWayThroughEitherEntry() {
        #expect(ChatNavigation.openSubagent(loadTest, stack: stack(agent)) == ChatNavigation.open(loadTest, stack: stack(agent)))
        #expect(ChatNavigation.openSubagent(loadTest, stack: stack(agent, loadTest, nested)) == ChatNavigation.open(loadTest, stack: stack(agent, loadTest, nested)))
    }
}
