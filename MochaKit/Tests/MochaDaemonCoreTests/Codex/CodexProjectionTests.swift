import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexProjectionTests {
    private static let at = Date(timeIntervalSince1970: 1_790_337_600)
    private static let cwd = CodexSample.cwd

    private static func json(_ text: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Data(text.utf8))
    }

    private static func project(_ text: String, isCompleted: Bool = true) throws -> ChatItem? {
        CodexProjection.item(try json(text), at: at, isCompleted: isCompleted, cwd: cwd)
    }

    private static func toolCall(_ text: String, isCompleted: Bool = true) throws -> ToolCall {
        let item = try #require(try project(text, isCompleted: isCompleted))
        guard case .toolCall(let call) = item.kind else {
            Issue.record("esperava toolCall, veio \(item.kind.type)")
            throw CodexServiceError.invalidResponse
        }
        return call
    }

    @Test func pageReadsItemsOldestFirstWithTheTimeOfEachItemAndClosesEachTurn() throws {
        let thread = try #require(try CodexSample.result("thread-read.response.json")["thread"])
        let listed = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-items-list.response.json"))["result"])
        let turnsResult = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-turns-list.response.json"))["result"])
        let turns = Dictionary(uniqueKeysWithValues: (turnsResult["data"]?.arrayValue ?? []).compactMap(CodexTurn.init).map { ($0.id, $0) })

        let page = try #require(CodexProjection.page(thread: thread, listed: listed, turns: turns, newerTurnId: nil))

        #expect(page.threadId == CodexSample.threadId)
        #expect(page.title == "Responder OK1")
        #expect(page.status == .idle)
        #expect(page.activeTurnId == nil)
        #expect(page.before == listed["nextCursor"]?.stringValue)
        #expect(page.items.map(\.kind.type) == ["thinking", "assistantText", "turnFooter", "userPrompt", "thinking", "assistantText", "notice"])
        #expect(page.items[2] == ChatItem(id: "01a0f5a3-9897-7e41-8c29-41d1b3bfc6be#end", at: Date(timeIntervalSince1970: 1_790_827_590), kind: .turnFooter(durationMs: 56_098)))
        #expect(page.items[3].at == Date(timeIntervalSince1970: 1_790_827_621.042))
        #expect(page.items[6].kind == .notice(text: "Interrompido"))
    }

    @Test func anOlderPageDoesNotCloseTheTurnThatContinuesOnTheNewerPage() throws {
        let thread = try #require(try CodexSample.result("thread-read.response.json")["thread"])
        let listed = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-items-list.response.json"))["result"])
        let turns = [
            "01a0f5a4-e9c9-7db2-9616-66d30583af2d": CodexTurn(id: "01a0f5a4-e9c9-7db2-9616-66d30583af2d", status: .completed, durationMs: 1),
        ]

        let page = try #require(CodexProjection.page(thread: thread, listed: listed, turns: turns, newerTurnId: "01a0f5a4-e9c9-7db2-9616-66d30583af2d"))
        #expect(!page.items.contains { $0.id.hasSuffix("#end") })

        let running = try #require(CodexProjection.page(
            thread: thread,
            listed: listed,
            turns: ["01a0f5a4-e9c9-7db2-9616-66d30583af2d": CodexTurn(id: "01a0f5a4-e9c9-7db2-9616-66d30583af2d", status: .inProgress)],
            newerTurnId: nil
        ))
        #expect(running.activeTurnId == "01a0f5a4-e9c9-7db2-9616-66d30583af2d")
        #expect(!running.items.contains { $0.id.hasSuffix("#end") })
    }

    @Test func userMessageJoinsTextsAndKeepsLocalImagePaths() throws {
        let item = try #require(try Self.project(#"""
        {"type":"userMessage","id":"u1","content":[
          {"type":"text","text":"Veja","text_elements":[]},
          {"type":"localImage","path":"/Users/dev/Library/Application Support/Mocha/uploads/a.png"},
          {"type":"image","url":"data:image/png;base64,AAAA"},
          {"type":"text","text":"isto","text_elements":[]}
        ]}
        """#))
        #expect(item.kind == .userPrompt(text: "Veja\nisto", imageCount: 2))
        #expect(item.imagePaths == ["/Users/dev/Library/Application Support/Mocha/uploads/a.png"])
        #expect(CodexProjection.preview(of: item) == MessagePreview(author: .user, text: "Veja isto"))
    }

    @Test func emptyMessagesWaitForTheirTextAndReasoningWithoutSummaryIsThinking() throws {
        #expect(try Self.project(#"{"type":"agentMessage","id":"m1","text":""}"#, isCompleted: false) == nil)
        #expect(try Self.project(#"{"type":"plan","id":"p1","text":""}"#, isCompleted: false) == nil)
        #expect(try Self.project(#"{"type":"agentMessage","id":"m1","text":"Pronto."}"#)?.kind == .assistantText(markdown: "Pronto."))
        #expect(try Self.project(#"{"type":"plan","id":"p1","text":"1. Ler o README"}"#)?.kind == .plan(markdown: "1. Ler o README"))
        #expect(try Self.project(#"{"type":"reasoning","id":"r1","summary":[],"content":[]}"#)?.kind == .thinking(text: nil))
        #expect(try Self.project(#"{"type":"reasoning","id":"r1","summary":["Lendo","o código"],"content":[]}"#)?.kind == .thinking(text: "Lendo\no código"))
    }

    @Test func commandExecutionIsAShellCallWithStatusFromStatusAndExitCode() throws {
        let running = try Self.toolCall(#"""
        {"type":"commandExecution","id":"e1","command":"/bin/zsh -lc 'sleep 40'","status":"inProgress","commandActions":[{"type":"unknown","command":"sleep 40"}],"exitCode":null,"aggregatedOutput":null}
        """#, isCompleted: false)
        #expect(running == ToolCall(toolUseId: "e1", name: "Shell", summary: "sleep 40", inputJSON: #"{"command":"sleep 40"}"#, status: .running))

        let failed = try Self.toolCall(#"""
        {"type":"commandExecution","id":"e2","command":"/bin/zsh -lc 'pwd && ls -l hello.txt'","status":"failed","commandActions":[{"type":"unknown","command":"pwd && ls -l hello.txt"}],"exitCode":1,"aggregatedOutput":"/work\nls: hello.txt: No such file or directory\n"}
        """#)
        #expect(failed.status == .failed)
        #expect(failed.resultPreview == "/work\nls: hello.txt: No such file or directory\n")

        let nonZero = try Self.toolCall(#"{"type":"commandExecution","id":"e3","command":"x","status":"completed","commandActions":[],"exitCode":2}"#)
        #expect(nonZero.status == .failed)
        #expect(nonZero.summary == "x")

        let succeeded = try Self.toolCall(#"{"type":"commandExecution","id":"e4","command":"x","status":"completed","commandActions":[{"command":"cat a"},{"command":"cat b"}],"exitCode":0,"aggregatedOutput":"oi"}"#)
        #expect(succeeded.status == .succeeded)
        #expect(succeeded.summary == "cat a")
        #expect(succeeded.inputJSON == #"{"command":"cat a\ncat b"}"#)

        let declined = try Self.toolCall(#"{"type":"commandExecution","id":"e5","command":"rm -rf x","status":"declined","commandActions":[],"exitCode":null}"#)
        #expect(declined.status == .failed)
    }

    @Test func fileChangeListsPathsRelativeToTheThread() throws {
        let call = try Self.toolCall(#"""
        {"type":"fileChange","id":"f1","status":"completed","changes":[
          {"path":"/Users/dev/Developer/mocha-lab/S9/work/a.txt","kind":{"type":"add"},"diff":"+oi"},
          {"path":"/Users/dev/Developer/mocha-lab/S9/work/src/b.txt","kind":{"type":"update"},"diff":"-a\n+b"}
        ]}
        """#)
        #expect(call.name == "Edit")
        #expect(call.summary == "a.txt, src/b.txt")
        #expect(call.inputJSON == #"{"file_path":"/Users/dev/Developer/mocha-lab/S9/work/a.txt","paths":["/Users/dev/Developer/mocha-lab/S9/work/a.txt","/Users/dev/Developer/mocha-lab/S9/work/src/b.txt"]}"#)
        #expect(call.status == .succeeded)
        #expect(call.resultPreview == "+oi\n-a\n+b")
    }

    @Test func webSearchMcpAndDynamicToolsKeepTheirNames() throws {
        let search = try Self.toolCall(#"{"type":"webSearch","id":"w1","query":"swift testing tags"}"#)
        #expect(search.name == "WebSearch")
        #expect(search.summary == "swift testing tags")

        let mcp = try Self.toolCall(#"""
        {"type":"mcpToolCall","id":"m1","server":"docs","tool":"search","status":"completed","arguments":{"query":"actors"},"result":{"content":[{"type":"text","text":"3 resultados"}]},"error":null}
        """#)
        #expect(mcp.name == "mcp__docs__search")
        #expect(mcp.summary == "actors")
        #expect(mcp.inputJSON == #"{"query":"actors"}"#)
        #expect(mcp.resultPreview == "3 resultados")

        let failedMcp = try Self.toolCall(#"{"type":"mcpToolCall","id":"m2","server":"docs","tool":"search","status":"failed","arguments":{},"result":null,"error":{"message":"timeout"}}"#)
        #expect(failedMcp.status == .failed)
        #expect(failedMcp.resultPreview == "timeout")

        let dynamic = try Self.toolCall(#"{"type":"dynamicToolCall","id":"d1","tool":"lookup","status":"completed","arguments":{"id":"42"},"success":false,"contentItems":[]}"#)
        #expect(dynamic.name == "lookup")
        #expect(dynamic.status == .failed)
    }

    @Test func imageViewCarriesTheImagePath() throws {
        let item = try #require(try Self.project(#"{"type":"imageView","id":"i1","path":"/Users/dev/Developer/mocha-lab/S9/work/shot.png"}"#))
        #expect(item.imagePaths == ["/Users/dev/Developer/mocha-lab/S9/work/shot.png"])
        #expect(item.kind == .toolCall(ToolCall(toolUseId: "i1", name: "Read", summary: "shot.png", inputJSON: #"{"file_path":"/Users/dev/Developer/mocha-lab/S9/work/shot.png"}"#, status: .succeeded)))
    }

    @Test func compactionIsANoticeCollabCallsAreHiddenAndUnknownItemsStayUnsupported() throws {
        #expect(try Self.project(#"{"type":"contextCompaction","id":"c1"}"#)?.kind == .notice(text: "Contexto compactado"))
        #expect(try Self.project(#"{"type":"collabAgentToolCall","id":"c2","tool":"wait","status":"completed"}"#) == nil)
        #expect(try Self.project(#"{"type":"subAgentActivity","id":"s1","kind":"interacted","agentThreadId":"t","agentPath":"/root/x"}"#) == nil)
        #expect(try Self.project(#"{"type":"hookPrompt","id":"h1"}"#)?.kind == .unsupported(type: "hookPrompt"))
    }

    @Test func subagentStartedIsACardThatTheCompletionConcludes() throws {
        let started = try Self.json(#"{"type":"subAgentActivity","id":"call_1","kind":"started","agentThreadId":"child-1","agentPath":"/root/list_directory"}"#)
        let card = try #require(CodexProjection.subagentCard(started, at: Self.at, status: nil))
        #expect(card.kind == .subagent(SubagentCall(toolUseId: "call_1", agentId: "child-1", agentType: "list_directory", description: "list_directory", status: .running, startedAt: Self.at)))

        let completed = try Self.json(#"{"type":"subAgentActivity","id":"done-1","kind":"completed","agentThreadId":"child-1","agentPath":"/root/list_directory"}"#)
        let found = try #require(CodexProjection.subagentOutcome(completed))
        #expect(found.child == "child-1")
        #expect(found.status == .completed)
        let concluded = CodexProjection.withOutcome(card, CodexSubagentOutcome(status: .completed, at: Self.at.addingTimeInterval(2.5)))
        guard case .subagent(let call) = concluded.kind else { throw CodexServiceError.invalidResponse }
        #expect(call.status == .completed)
        #expect(call.durationMs == 2_500)
        #expect(concluded.id == "call_1")

        let interrupted = try Self.json(#"{"type":"subAgentActivity","id":"x","kind":"interrupted","agentThreadId":"child-1","agentPath":"/root/a"}"#)
        #expect(CodexProjection.subagentOutcome(interrupted)?.status == .stopped)
    }

    @Test func turnsCloseWithFooterInterruptionOrError() {
        let end = Date(timeIntervalSince1970: 1_790_827_647)
        #expect(CodexProjection.closingItem(CodexTurn(id: "t1", status: .completed, completedAt: end, durationMs: 1_576), fallback: Self.at)
            == ChatItem(id: "t1#end", at: end, kind: .turnFooter(durationMs: 1_576)))
        #expect(CodexProjection.closingItem(CodexTurn(id: "t2", status: .interrupted, completedAt: end, durationMs: 26_599), fallback: Self.at)?.kind
            == .notice(text: "Interrompido"))
        #expect(CodexProjection.closingItem(CodexTurn(id: "t3", status: .failed, errorMessage: "stream disconnected"), fallback: Self.at)
            == ChatItem(id: "t3#end", at: Self.at, kind: .notice(text: "stream disconnected")))
        #expect(CodexProjection.closingItem(CodexTurn(id: "t4", status: .failed), fallback: Self.at)?.kind == .notice(text: "O turno falhou."))
        #expect(CodexProjection.closingItem(CodexTurn(id: "t5", status: .inProgress), fallback: Self.at) == nil)
    }

    @Test func contextLeftKeepsTheTwelveThousandTokenReserve() {
        #expect(CodexProjection.contextLeftPercent(lastTokens: 20_136, window: 258_400) == 97)
        #expect(CodexProjection.contextLeftPercent(lastTokens: 5_630, window: 258_400) == 100)
        #expect(CodexProjection.contextLeftPercent(lastTokens: 135_200, window: 258_400) == 50)
        #expect(CodexProjection.contextLeftPercent(lastTokens: 300_000, window: 258_400) == 0)
        #expect(CodexProjection.contextLeftPercent(lastTokens: 1_000, window: 12_000) == nil)
    }

    @Test func settingsComeFromTheResumeAndFromSettingsUpdated() throws {
        let resume = try CodexSample.result("thread-resume.response.json")
        let resumed = CodexProjection.settings(resume)
        #expect(resumed == CodexThreadSettings(model: "gpt-6.1-sol", effort: nil, mode: "default"))

        let updated = try Self.json(#"{"model":"gpt-6-luna","effort":"high","collaborationMode":{"mode":"plan","settings":{}}}"#)
        #expect(CodexProjection.settings(updated, fallback: resumed) == CodexThreadSettings(model: "gpt-6-luna", effort: "high", mode: "plan"))

        let partial = try Self.json(#"{"effort":"low"}"#)
        #expect(CodexProjection.settings(partial, fallback: resumed) == CodexThreadSettings(model: "gpt-6.1-sol", effort: "low", mode: "default"))
    }

    @Test func usesDurationAndResetReturnedByCodex() throws {
        let raw = try OrderedJSON.parse(Fixtures.data("codex/rate-limits.json"))
        let snapshot = try #require(CodexProjection.usage(raw))

        #expect(snapshot.provider == .codex)
        #expect(snapshot.windows.map(\.windowDurationMins) == [300, 10080])
        #expect(snapshot.windows.map(\.usedPercent) == [41.5, 16])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1780003000))
        #expect(snapshot.plan == nil)
        #expect(snapshot.account == nil)
    }

    @Test func usageCarriesThePlanAndTheMaskedEmailFromAccountRead() throws {
        let account = CodexProjection.account(try CodexSample.result("account-read.response.json"))
        #expect(account == CodexAccount(plan: "Plus", email: "d•••@e•••.com"))

        let raw = try OrderedJSON.parse(Fixtures.data("codex/rate-limits.json"))
        let snapshot = try #require(CodexProjection.usage(raw, account: account))
        #expect(snapshot.plan == "Plus")
        #expect(snapshot.account == "d•••@e•••.com")

        #expect(CodexProjection.planName("prolite") == "Pro Lite")
        #expect(CodexProjection.planName("enterprise") == "Enterprise")
        #expect(CodexProjection.planName("self_serve_business") == "Self Serve Business")
        #expect(CodexProjection.planName("unknown") == nil)
        #expect(CodexProjection.account(try Self.json(#"{"account":null}"#)) == CodexAccount(plan: nil, email: nil))
    }

    @Test func imagePathsMustBeFilesFromMochaUploads() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-codex-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appending(path: "upload.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)

        let input = try CodexService.promptInput("Analise\n[imagem: \(image.path)]", uploadsDirectory: directory)
        #expect(input.count == 2)
        #expect(input[0]["type"]?.stringValue == "text")
        #expect(input[1]["type"]?.stringValue == "localImage")
        #expect(input[1]["path"]?.stringValue == image.path)

        #expect(throws: CodexServiceError.invalidImage) {
            try CodexService.promptInput("[imagem: /etc/passwd]", uploadsDirectory: directory)
        }
    }
}
