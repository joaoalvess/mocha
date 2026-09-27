import Foundation
import Testing
@testable import MochaClient

struct AgentsActivityTextTests {
    private static let since = Date(timeIntervalSinceReferenceDate: 780_000_000)

    private static func content(working: Int, waiting: Int, highlight: AgentsActivityContent.Highlight? = nil, pending: AgentsActivityContent.Pending? = nil) -> AgentsActivityContent {
        AgentsActivityContent(working: working, waiting: waiting, highlight: highlight, pending: pending, updatedAt: since)
    }

    private static func highlight(
        agentId: String = "w17:p1",
        status: String,
        workspace: String = "site-pessoal",
        title: String = "Modo escuro e RSS",
        tabTitle: String? = nil,
        model: String? = nil,
        contextLeftPercent: Int? = nil,
        preview: String? = nil,
        activity: String? = nil
    ) -> AgentsActivityContent.Highlight {
        AgentsActivityContent.Highlight(
            agentId: agentId,
            title: title,
            workspaceLabel: workspace,
            status: status,
            since: since,
            tabTitle: tabTitle,
            model: model,
            contextLeftPercent: contextLeftPercent,
            preview: preview,
            activity: activity
        )
    }

    private static func permission(toolName: String?, text: String) -> AgentsActivityContent.Pending {
        AgentsActivityContent.Pending(requestId: "r1", agentId: "w17:p1", kind: .permission, toolName: toolName, text: text, options: [])
    }

    private static func question(_ text: String, options: [String]) -> AgentsActivityContent.Pending {
        AgentsActivityContent.Pending(requestId: "r2", agentId: "w17:p1", kind: .question, toolName: nil, text: text, options: options)
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

    @Test func highlightToneFollowsItsStatus() {
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

    @Test func headerNamesTheTabBeforeTheWorkspace() {
        let working = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", tabTitle: "M12", model: "claude-opus-5-5"))
        #expect(AgentsActivityText.header(of: working) == AgentsActivityHeader(label: "M12", tone: .working, model: "opus-5-5", context: nil))
        let withoutTab = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", tabTitle: "  "))
        #expect(AgentsActivityText.header(of: withoutTab).label == "site-pessoal")
        let unnamed = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", workspace: ""))
        #expect(AgentsActivityText.header(of: unnamed).label == "Mocha")
        let done = AgentsActivityText.header(of: Self.content(working: 0, waiting: 0))
        #expect(done == AgentsActivityHeader(label: "Mocha", tone: .done, model: nil, context: nil))
    }

    @Test(arguments: [
        ("claude-opus-5-5", "opus-5-5"),
        ("claude-sonnet-4-5-20250929", "sonnet-4-5"),
        ("opus-5-5", "opus-5-5"),
        ("claude-", nil),
        (" ", nil),
    ] as [(String, String?)])
    func headerShowsTheModelWithoutTheClaudePrefix(model: String, expected: String?) {
        let content = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", model: model))
        #expect(AgentsActivityText.header(of: content).model == expected)
    }

    @Test func headerContextFollowsTheHomeRingColorRule() {
        let working = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", contextLeftPercent: 89))
        #expect(AgentsActivityText.header(of: working).context == AgentsActivityContext(leftPercent: 89, isBlocked: false))
        #expect(AgentsActivityText.header(of: working).context?.fraction == 0.89)
        let blocked = Self.content(working: 0, waiting: 1, highlight: Self.highlight(status: "blocked", contextLeftPercent: 140))
        #expect(AgentsActivityText.header(of: blocked).context == AgentsActivityContext(leftPercent: 100, isBlocked: true))
        #expect(AgentsActivityText.header(of: blocked).tone == .waiting)
        var pending = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", contextLeftPercent: -5))
        pending.pending = Self.permission(toolName: "Bash", text: "ls")
        #expect(AgentsActivityText.header(of: pending).context == AgentsActivityContext(leftPercent: 0, isBlocked: true))
        #expect(AgentsActivityText.header(of: pending).tone == .waiting)
    }

    @Test func firstLinePrefersTheActivityThenThePreviewThenTheTitle() {
        let all = Self.highlight(status: "working", preview: "Terminei o parser.", activity: "Bash: npm run build")
        #expect(AgentsActivityText.lines(of: Self.content(working: 1, waiting: 0, highlight: all)) == AgentsActivityLines(headline: "Shell: npm run build", detail: .continuation))
        let preview = Self.highlight(status: "working", preview: "Comecei a 2.C, mas o WP-M12\n ainda não está pronto", activity: " ")
        #expect(AgentsActivityText.lines(of: Self.content(working: 1, waiting: 0, highlight: preview)) == AgentsActivityLines(headline: "Comecei a 2.C, mas o WP-M12 ainda não está pronto", detail: .continuation))
        let title = Self.highlight(status: "blocked", preview: "")
        #expect(AgentsActivityText.lines(of: Self.content(working: 0, waiting: 1, highlight: title)) == AgentsActivityLines(headline: "Modo escuro e RSS", detail: .continuation))
        let empty = Self.highlight(status: "working", title: " ")
        #expect(AgentsActivityText.lines(of: Self.content(working: 2, waiting: 0, highlight: empty)) == AgentsActivityLines(headline: "2 trabalhando", detail: .continuation))
    }

    @Test(arguments: [
        ("Bash: npm run build", "Shell: npm run build"),
        ("Bash", "Shell"),
        ("Read: notas.md", "Read: notas.md"),
        ("Bash: echo a: b", "Shell: echo a: b"),
        ("mcp__linear__create_issue: Bug no feed", "mcp__linear__create_issue: Bug no feed"),
    ])
    func activityShowsTheToolDisplayName(activity: String, expected: String) {
        let content = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working", activity: activity))
        #expect(AgentsActivityText.lines(of: content).headline == expected)
    }

    @Test func allDoneReplacesTheFirstLine() {
        #expect(AgentsActivityText.lines(of: Self.content(working: 0, waiting: 0)) == AgentsActivityLines(headline: "Tudo pronto", detail: nil))
        let finished = Self.content(working: 0, waiting: 0, highlight: Self.highlight(status: "done", preview: "Pronto."))
        #expect(AgentsActivityText.lines(of: finished) == AgentsActivityLines(headline: "Tudo pronto", detail: nil))
        #expect(AgentsActivityText.lines(of: Self.content(working: 1, waiting: 2)) == AgentsActivityLines(headline: "1 trabalhando · 2 esperando você", detail: nil))
    }

    @Test func aPermissionShowsWhatTheToolWantsAndTheCommand() {
        let highlight = Self.highlight(status: "blocked", preview: "ignorada", activity: "ignorada")
        var content = Self.content(working: 0, waiting: 1, highlight: highlight, pending: Self.permission(toolName: "Bash", text: "npm run build"))
        #expect(AgentsActivityText.lines(of: content) == AgentsActivityLines(headline: "Shell quer rodar", detail: .command("$ npm run build")))
        content.pending = Self.permission(toolName: "Edit", text: "Sources/App.swift")
        #expect(AgentsActivityText.lines(of: content) == AgentsActivityLines(headline: "Edit quer editar", detail: .command("Sources/App.swift")))
        content.pending = Self.permission(toolName: nil, text: "  ")
        #expect(AgentsActivityText.lines(of: content) == AgentsActivityLines(headline: "Claude quer permissão", detail: nil))
    }

    @Test func aQuestionFillsBothLinesUnlessItsButtonsNeedTwoRows() {
        var content = Self.content(working: 0, waiting: 1, highlight: Self.highlight(status: "blocked"))
        content.pending = Self.question("Qual formato de feed\nvocê quer?", options: ["RSS 2.0", "Atom"])
        #expect(AgentsActivityText.lines(of: content) == AgentsActivityLines(headline: "Qual formato de feed você quer?", detail: .continuation))
        content.pending = Self.question("Qual formato?", options: ["RSS 2.0", "Atom", "Os dois"])
        #expect(AgentsActivityText.lines(of: content) == AgentsActivityLines(headline: "Qual formato?", detail: nil))
        content.pending = Self.question("Qual formato?", options: ["A", "B", "C", "D"])
        #expect(AgentsActivityText.lines(of: content).detail == nil)
        content.pending = Self.question("Escolha as opções do build", options: [])
        #expect(AgentsActivityText.lines(of: content) == AgentsActivityLines(headline: "Escolha as opções do build", detail: .continuation))
        content.pending = Self.question(" ", options: [])
        #expect(AgentsActivityText.lines(of: content).headline == "Pergunta do Claude")
    }

    @Test(arguments: [
        (3, 1, "working", "+2 trabalhando · 1 esperando você"),
        (2, 2, "blocked", "+2 trabalhando · 1 esperando você"),
        (0, 3, "blocked", "+2 esperando você"),
        (1, 0, "working", nil),
        (0, 1, "blocked", nil),
    ] as [(Int, Int, String, String?)])
    func footnoteCountsOnlyTheOtherAgents(working: Int, waiting: Int, status: String, expected: String?) {
        let content = Self.content(working: working, waiting: waiting, highlight: Self.highlight(status: status))
        #expect(AgentsActivityText.footnote(of: content, isStale: false)?.text == expected)
    }

    @Test func footnoteSplitsTheCountsAndWarnsWhenTheMacStoppedUpdating() {
        let content = Self.content(working: 3, waiting: 1, highlight: Self.highlight(status: "working"))
        #expect(AgentsActivityText.footnote(of: content, isStale: true) == AgentsActivityFootnote(
            working: "+2 trabalhando",
            waiting: "1 esperando você",
            stale: "sem notícias do Mac"
        ))
        let alone = Self.content(working: 1, waiting: 0, highlight: Self.highlight(status: "working"))
        #expect(AgentsActivityText.footnote(of: alone, isStale: true)?.text == "sem notícias do Mac")
        #expect(AgentsActivityText.footnote(of: Self.content(working: 2, waiting: 1), isStale: false) == nil)
        #expect(AgentsActivityText.footnote(of: Self.content(working: 0, waiting: 0), isStale: false) == nil)
    }
}
