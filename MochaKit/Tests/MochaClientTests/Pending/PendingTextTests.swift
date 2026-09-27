import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct PendingTextTests {
    @Test func headersFollowTheKind() {
        #expect(PendingText.header(for: PendingFixtures.permission("a").kind) == "Precisa de você")
        #expect(PendingText.header(for: .question(questions: [PendingFixtures.formatQuestion])) == "Pergunta do Claude")
    }

    @Test func shellPermissionShowsTheCommandWithThePrompt() {
        let text = PendingText.permission(toolName: "Bash", summary: "npm run build", inputJSON: #"{"command":"npm run build","description":"Build"}"#)
        #expect(text.toolName == "Shell")
        #expect(text.verb == "quer rodar")
        #expect(text.detail == "npm run build")
        #expect(text.showsPrompt)
        #expect(text.fullInput == "{\n  \"command\" : \"npm run build\",\n  \"description\" : \"Build\"\n}")
    }

    @Test func otherToolsShowTheSummaryWithoutPrompt() {
        let text = PendingText.permission(toolName: "Write", summary: "src/pages/feed.xml.ts", inputJSON: #"{"file_path":"/Users/dev/site/src/pages/feed.xml.ts"}"#)
        #expect(text.toolName == "Write")
        #expect(text.verb == "quer escrever")
        #expect(text.detail == "src/pages/feed.xml.ts")
        #expect(!text.showsPrompt)
        #expect(text.fullInput.contains(#""file_path" : "/Users/dev/site/src/pages/feed.xml.ts""#))
    }

    @Test func blankSummaryHasNoDetail() {
        #expect(PendingText.permission(toolName: "mcp__linear__create_issue", summary: "  ", inputJSON: "{}").detail == nil)
    }

    @Test(arguments: [
        ("Bash", "quer rodar"),
        ("Read", "quer ler"),
        ("Edit", "quer editar"),
        ("MultiEdit", "quer editar"),
        ("NotebookEdit", "quer editar"),
        ("Write", "quer escrever"),
        ("WebFetch", "quer abrir"),
        ("WebSearch", "quer buscar"),
        ("Grep", "quer buscar"),
        ("mcp__linear__create_issue", "quer usar"),
    ])
    func verbs(tool: String, verb: String) {
        #expect(PendingText.verb(forTool: tool) == verb)
    }

    @Test func truncatedInputIsShownRaw() {
        let truncated = #"{"command":"echo "#
        #expect(PendingText.formattedInput(truncated) == truncated)
        #expect(PendingText.formattedInput("\"texto\"") == "\"texto\"")
    }

    @Test(arguments: [
        (0.0, "agora"),
        (0.4, "agora"),
        (12.0, "há 12 s"),
        (59.9, "há 59 s"),
        (60.0, "há 1 min"),
        (3_599.0, "há 59 min"),
        (7_300.0, "há 2 h"),
        (-5.0, "agora"),
    ])
    func age(seconds: TimeInterval, text: String) {
        #expect(PendingText.age(from: PendingFixtures.start, now: PendingFixtures.start.addingTimeInterval(seconds)) == text)
    }

    @Test func inboxMetaJoinsWorkspaceAndAge() {
        let now = PendingFixtures.start.addingTimeInterval(12)
        #expect(PendingText.inboxMeta(workspace: "site-pessoal", createdAt: PendingFixtures.start, now: now) == "site-pessoal · há 12 s")
        #expect(PendingText.inboxMeta(workspace: " ", createdAt: PendingFixtures.start, now: now) == "há 12 s")
        #expect(PendingText.inboxMeta(workspace: nil, createdAt: PendingFixtures.start, now: now) == "há 12 s")
    }

    @Test func countTexts() {
        #expect(PendingText.inboxCount(2) == "· 2")
        #expect(PendingText.badge(0) == nil)
        #expect(PendingText.badge(2) == "2")
        #expect(PendingText.badge(99) == "99")
        #expect(PendingText.badge(140) == "99+")
    }

    @Test func failureNoticesOnlyForUndeliveredAnswers() {
        #expect(PendingText.failureNotice(for: .accepted) == nil)
        #expect(PendingText.failureNotice(for: .gone) == nil)
        #expect(PendingText.failureNotice(for: .unreachable)?.title == "Não consegui falar com o Mac")
        #expect(PendingText.failureNotice(for: .unexpectedStatus(502))?.title == "Não consegui falar com o Mac")
        #expect(PendingText.failureNotice(for: .unauthorized) == PendingNotice(title: "Não consegui falar com o Mac", body: "Este iPhone não está mais pareado."))
        #expect(PendingText.failureNotice(for: .notPaired)?.body == "Este iPhone não está mais pareado.")
        #expect(PendingText.failureNotice(for: .refused)?.title == "O Mac recusou a resposta")
    }
}
