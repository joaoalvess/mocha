import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct AgentsActivityTextTests {
    private static let since = Date(timeIntervalSinceReferenceDate: 780_000_000)

    private static func content(
        _ status: AgentStatus = .working,
        workspaceLabel: String = "Core",
        model: String? = "claude-opus-5-5",
        contextLeftPercent: Int? = 42,
        preview: String? = nil,
        activity: String? = nil,
        prompt: String? = nil,
        outcome: String? = nil,
        pending: AgentsActivityContent.Pending? = nil
    ) -> AgentsActivityContent {
        AgentsActivityContent(
            agentId: "w1:p1",
            status: status.rawValue,
            title: "Refatorar o parser",
            workspaceLabel: workspaceLabel,
            since: since,
            model: model,
            contextLeftPercent: contextLeftPercent,
            preview: preview,
            activity: activity,
            prompt: prompt,
            outcome: outcome,
            pending: pending,
            updatedAt: since
        )
    }

    private static func permission(_ toolName: String? = "Bash", text: String = "npm run build") -> AgentsActivityContent.Pending {
        AgentsActivityContent.Pending(requestId: "req-1", kind: .permission, toolName: toolName, text: text, options: [])
    }

    private static func question(_ options: [String]) -> AgentsActivityContent.Pending {
        AgentsActivityContent.Pending(requestId: "req-1", kind: .question, toolName: nil, text: "Qual banco?", options: options)
    }

    @Test func toneFollowsTheStatusAndAPendingRequest() {
        #expect(AgentsActivityText.tone(of: Self.content(.working)) == .working)
        #expect(AgentsActivityText.tone(of: Self.content(.blocked)) == .waiting)
        #expect(AgentsActivityText.tone(of: Self.content(.idle)) == .done)
        #expect(AgentsActivityText.tone(of: Self.content(.working, pending: Self.permission())) == .waiting)
    }

    @Test func theHeaderNamesTheProjectThenTheModel() {
        let header = AgentsActivityText.header(of: Self.content())
        #expect(header == AgentsActivityHeader(
            project: "Core",
            tone: .working,
            model: ModelName.abbreviated("claude-opus-5-5"),
            context: AgentsActivityContext(leftPercent: 42, isBlocked: false)
        ))
        #expect(AgentsActivityText.header(of: Self.content(model: nil)).model == nil)
        #expect(AgentsActivityText.header(of: Self.content(workspaceLabel: "  ")).project == AgentsActivityText.appName)
    }

    @Test func aPendingRequestKeepsTheHeaderGreenAndHighlightsTheSecondLine() {
        let content = Self.content(.blocked, pending: Self.permission())
        let header = AgentsActivityText.header(of: content)
        #expect(header.tone == .working)
        #expect(header.context?.isBlocked == false)
        #expect(AgentsActivityText.header(of: Self.content(.blocked)).tone == .waiting)
        #expect(AgentsActivityText.lines(of: content).emphasizesDetail)
        #expect(AgentsActivityText.lines(of: Self.content(.blocked, pending: Self.question(["Postgres", "SQLite"]))).emphasizesDetail)
        #expect(!AgentsActivityText.lines(of: Self.content(.working, preview: "Pronto.")).emphasizesDetail)
    }

    @Test func anOutcomeNamesTheDecisionAboveTheLastPrompt() {
        let lines = AgentsActivityText.lines(of: Self.content(.working, preview: "Vou seguir.", prompt: "faz o plano", outcome: "allowed"))
        #expect(lines == AgentsActivityLines(headline: "Aprovado", detail: .text("Você: faz o plano")))
        #expect(AgentsActivityText.lines(of: Self.content(outcome: "denied")).headline == "Negado")
        #expect(AgentsActivityText.lines(of: Self.content(outcome: "answered")).headline == "Respondido")
        #expect(AgentsActivityText.lines(of: Self.content(preview: "Vou seguir.", outcome: "outro")).headline == "Vou seguir.")
    }

    @Test func theContextIsClampedAndTurnsAmberWhileWaiting() {
        #expect(AgentsActivityText.header(of: Self.content(contextLeftPercent: 130)).context == AgentsActivityContext(leftPercent: 100, isBlocked: false))
        #expect(AgentsActivityText.header(of: Self.content(.blocked, contextLeftPercent: -3)).context == AgentsActivityContext(leftPercent: 0, isBlocked: true))
        #expect(AgentsActivityText.header(of: Self.content(contextLeftPercent: nil)).context == nil)
    }

    @Test func aBusyAgentShowsItsPreviewThenItsActivityThenItsTitle() {
        let preview = AgentsActivityText.lines(of: Self.content(preview: "Rodando  os\ntestes", activity: "Bash: npm test"))
        #expect(preview == AgentsActivityLines(headline: "Rodando os testes", detail: .continuation))
        #expect(AgentsActivityText.lines(of: Self.content(activity: "Bash: npm test")).headline == "Shell: npm test")
        #expect(AgentsActivityText.lines(of: Self.content()).headline == "Refatorar o parser")
    }

    @Test func aBusyAgentShowsItsLastPromptUnderTheHeadline() {
        let lines = AgentsActivityText.lines(of: Self.content(preview: "20 s de 60.", prompt: "Faz\n dnv"))
        #expect(lines == AgentsActivityLines(headline: "20 s de 60.", detail: .text("Você: Faz dnv")))
        #expect(AgentsActivityText.lines(of: Self.content(.blocked, prompt: "Faz dnv")).detail == .text("Você: Faz dnv"))
        #expect(AgentsActivityText.lines(of: Self.content(preview: "20 s de 60.", prompt: " \n ")).detail == .continuation)
    }

    @Test func anIdleAgentShowsItsLastMessageAndPromptLikeABusyOne() {
        let lines = AgentsActivityText.lines(of: Self.content(.idle, preview: "Rodei os testes.", prompt: "Roda os testes"))
        #expect(lines == AgentsActivityLines(headline: "Rodei os testes.", detail: .text("Você: Roda os testes")))
        #expect(AgentsActivityText.lines(of: Self.content(.idle)) == AgentsActivityLines(headline: "Refatorar o parser", detail: .continuation))
    }

    @Test func aPermissionShowsWhatTheToolWantsAndTheCommand() {
        let lines = AgentsActivityText.lines(of: Self.content(.blocked, pending: Self.permission()))
        let headline = AgentsActivityText.permissionHeadline(toolName: "Bash")
        #expect(lines == AgentsActivityLines(headline: headline.toolName + " " + headline.verb, detail: .command("$ npm run build"), emphasizesDetail: true))
        #expect(AgentsActivityText.permissionHeadline(toolName: " ").verb == AgentsActivityText.permissionFallbackVerb)
    }

    @Test func aPlanAsksToFollowThePlanWithItsFirstLine() {
        let lines = AgentsActivityText.lines(of: Self.content(.blocked, pending: Self.permission("ExitPlanMode", text: "Criar o arquivo f.txt")))
        #expect(lines == AgentsActivityLines(headline: "Sair do modo plano", detail: .text("Criar o arquivo f.txt"), emphasizesDetail: true))
    }

    @Test func aQuestionFillsBothLinesUnlessItsButtonsNeedTwoRows() {
        #expect(AgentsActivityText.lines(of: Self.content(.blocked, pending: Self.question(["Postgres", "SQLite"]))).detail == .continuation)
        #expect(AgentsActivityText.lines(of: Self.content(.blocked, pending: Self.question(["a", "b", "c"]))).detail == nil)
    }

    @Test func theFootnoteOnlyWarnsWhenTheMacStoppedUpdating() {
        #expect(AgentsActivityText.footnote(isStale: true) == AgentsActivityText.staleNote)
        #expect(AgentsActivityText.footnote(isStale: false) == nil)
    }

    @Test func theDeepLinkOpensTheAgent() throws {
        #expect(AgentsActivityText.deepLink(forAgent: "w1:p1") == DeepLink.agent("w1:p1").url)
        #expect(AgentsActivityText.deepLink(forAgent: "") == nil)
    }
}
