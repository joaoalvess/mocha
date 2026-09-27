import Foundation
import Testing
@testable import MochaClient

struct AgentsActivityTextTests {
    private static let since = Date(timeIntervalSinceReferenceDate: 780_000_000)

    private static func content(working: Int, waiting: Int, highlight: AgentsActivityContent.Highlight? = nil, pending: AgentsActivityContent.Pending? = nil) -> AgentsActivityContent {
        AgentsActivityContent(working: working, waiting: waiting, highlight: highlight, pending: pending, updatedAt: since)
    }

    private static func highlight(agentId: String = "w17:p1", status: String, workspace: String = "site-pessoal") -> AgentsActivityContent.Highlight {
        AgentsActivityContent.Highlight(agentId: agentId, title: "Modo escuro e RSS", workspaceLabel: workspace, status: status, since: since)
    }

    @Test(arguments: [
        (2, 1, "2 trabalhando", "1 esperando você", "2 trabalhando · 1 esperando você"),
        (3, 0, "3 trabalhando", nil, "3 trabalhando"),
        (0, 2, nil, "2 esperando você", "2 esperando você"),
        (0, 0, nil, nil, "Tudo pronto"),
    ])
    func summaryCountsWorkingAndWaiting(working: Int, waiting: Int, workingText: String?, waitingText: String?, text: String) {
        let summary = AgentsActivityText.summary(of: Self.content(working: working, waiting: waiting))
        #expect(summary.working == workingText)
        #expect(summary.waiting == waitingText)
        #expect(summary.text == text)
    }

    @Test func toneFollowsTheMostUrgentState() {
        #expect(AgentsActivityText.tone(of: Self.content(working: 2, waiting: 1)) == .waiting)
        #expect(AgentsActivityText.tone(of: Self.content(working: 2, waiting: 0)) == .working)
        #expect(AgentsActivityText.tone(of: Self.content(working: 0, waiting: 0)) == .done)
        let pending = AgentsActivityContent.Pending(requestId: "r", agentId: "a", kind: .question, toolName: nil, text: "?", options: [])
        #expect(AgentsActivityText.tone(of: Self.content(working: 1, waiting: 0, pending: pending)) == .waiting)
    }

    @Test func highlightDetailNamesTheWorkspaceAndState() {
        #expect(AgentsActivityText.highlightDetail(Self.highlight(status: "blocked")) == "site-pessoal · esperando você")
        #expect(AgentsActivityText.highlightDetail(Self.highlight(status: "working")) == "site-pessoal · trabalhando")
        #expect(AgentsActivityText.highlightDetail(Self.highlight(status: "working", workspace: " ")) == "trabalhando")
        #expect(AgentsActivityText.tone(of: Self.highlight(status: "blocked")) == .waiting)
        #expect(AgentsActivityText.tone(of: Self.highlight(status: "working")) == .working)
        #expect(AgentsActivityText.tone(of: Self.highlight(status: "idle")) == .done)
    }

    @Test func compactCountPrefersWaiting() {
        #expect(AgentsActivityText.compactCount(of: Self.content(working: 2, waiting: 1)) == "1")
        #expect(AgentsActivityText.compactCount(of: Self.content(working: 2, waiting: 0)) == "2")
        #expect(AgentsActivityText.compactCount(of: Self.content(working: 0, waiting: 0)) == nil)
    }

    @Test func deepLinkOpensThePendingAgentFirst() throws {
        let highlighted = Self.content(working: 1, waiting: 0, highlight: Self.highlight(agentId: "w2:p3", status: "working"))
        #expect(AgentsActivityText.deepLink(for: highlighted)?.absoluteString == "mocha://agent/w2%3Ap3")
        var pending = highlighted
        pending.pending = AgentsActivityContent.Pending(requestId: "r", agentId: "w17:p1", kind: .question, toolName: nil, text: "?", options: [])
        let url = try #require(AgentsActivityText.deepLink(for: pending))
        #expect(url.absoluteString == "mocha://agent/w17%3Ap1")
        #expect(DeepLink(url) == .agent("w17:p1"))
        #expect(AgentsActivityText.deepLink(for: Self.content(working: 0, waiting: 0)) == nil)
    }

    @Test func permissionHeadlineReusesTheInboxWording() {
        #expect(AgentsActivityText.permissionHeadline(toolName: "Bash") == AgentsActivityPermissionHeadline(toolName: "Shell", verb: "quer rodar", showsPrompt: true))
        #expect(AgentsActivityText.permissionHeadline(toolName: "Edit") == AgentsActivityPermissionHeadline(toolName: "Edit", verb: "quer editar", showsPrompt: false))
        #expect(AgentsActivityText.permissionHeadline(toolName: "mcp__linear__create_issue").verb == "quer usar")
        #expect(AgentsActivityText.permissionHeadline(toolName: nil) == AgentsActivityPermissionHeadline(toolName: "Claude", verb: "quer permissão", showsPrompt: false))
    }

    @Test func subtitleWarnsWhenTheMacStoppedUpdating() {
        #expect(AgentsActivityText.subtitle(isStale: false) == "Mocha")
        #expect(AgentsActivityText.subtitle(isStale: true) == "Mocha · sem notícias do Mac")
    }
}
