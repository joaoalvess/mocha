import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexThreadStateTests {
    private static func replay(_ names: [String]) throws -> CodexLiveReplay {
        var replay = CodexLiveReplay(resume: try CodexSample.result("thread-resume.response.json"))
        for name in names {
            for message in try CodexLiveReplay.messages(name) {
                replay.apply(message)
            }
        }
        return replay
    }

    private static func state(_ names: [String]) throws -> CodexThreadState {
        try #require(try replay(names).states[CodexSample.threadId])
    }

    private static func replaying(_ name: String, until stop: (OrderedJSON) -> Bool) throws -> CodexThreadState {
        var replay = CodexLiveReplay(resume: try CodexSample.result("thread-resume.response.json"))
        for message in try CodexLiveReplay.messages(name) {
            replay.apply(message)
            if stop(message) { break }
        }
        return try #require(replay.states[CodexSample.threadId])
    }

    @Test func theResumeGivesTitleBranchSessionStartAndSettings() throws {
        var state = CodexThreadState(threadId: CodexSample.threadId)
        state.absorb(resume: try CodexSample.result("thread-resume.response.json"))

        #expect(state.summary.title == "Responder OK1")
        #expect(state.summary.threadPreview == "Responda só: OK1")
        #expect(state.summary.branch == "s9-branch")
        #expect(state.summary.sessionStartedAt == Date(timeIntervalSince1970: 1_790_827_194))
        #expect(state.summary.lastActivityAt == Date(timeIntervalSince1970: 1_790_827_211))
        #expect(state.settings == CodexThreadSettings(model: "gpt-6.1-sol", effort: nil, mode: "default"))
        #expect(state.cwd == CodexSample.cwd)
    }

    @Test func theTitleFallsBackToThePreviewAndFollowsRenames() throws {
        var state = CodexThreadState(threadId: CodexSample.threadId)
        let thread = try OrderedJSON.parse(Data(#"{"id":"t","cwd":"/w","name":null,"preview":"Liste os arquivos"}"#.utf8))
        state.absorb(thread: thread)
        #expect(state.summary.title == "Liste os arquivos")

        _ = state.apply("thread/name/updated", try OrderedJSON.parse(Data(#"{"threadId":"t","threadName":"Arquivos do projeto"}"#.utf8)), now: CodexLiveReplay.now)
        #expect(state.summary.title == "Arquivos do projeto")
    }

    @Test func aCompletedTurnSetsPreviewPromptTimesContextAndTheLastMessage() throws {
        let state = try Self.state(["basic-turn"])

        #expect(state.summary.preview == MessagePreview(author: .assistant, text: "OK2"))
        #expect(state.summary.prompt == "Responda só: OK2")
        #expect(state.lastAgentMessage == "OK2")
        #expect(state.summary.turnStartedAt == Date(timeIntervalSince1970: 1_790_827_270))
        #expect(state.summary.turnEndedAt == Date(timeIntervalSince1970: 1_790_827_272))
        #expect(state.summary.lastActivityAt == Date(timeIntervalSince1970: 1_790_827_272.081))
        #expect(state.summary.contextUsedTokens == 20_136)
        #expect(state.summary.contextLeftPercent == 97)
        #expect(state.activeTurnId == nil)
        #expect(state.closedTurns["01a0f59f-9171-7672-873f-2cb30bf0915d"]?.durationMs == 1_576)
    }

    @Test func whileTheTurnRunsTheActivityIsTheCommandInProgress() throws {
        let running = try Self.replaying("command-turn") { message in
            message["method"]?.stringValue == "item/started" && message["params"]?["item"]?["type"]?.stringValue == "commandExecution"
        }
        #expect(running.activeTurnId == "01a0f5a1-4002-74e3-99de-cad3477bac9a")
        #expect(running.summary.turnEndedAt == nil)
        #expect(running.summary.activity == ToolActivity(toolName: "Shell", summary: "printf 'oi' > hello.txt", status: .running))
        #expect(running.summary.prompt == "Implemente o plano.")

        let done = try Self.state(["command-turn"])
        #expect(done.summary.activity == ToolActivity(toolName: "Shell", summary: "cat hello.txt", status: .succeeded))
        #expect(done.summary.contextUsedTokens == 23_020)
        #expect(done.settings == CodexThreadSettings(model: "gpt-6-luna", effort: "high", mode: "default"))
    }

    @Test func settingsUpdatedChangesModelEffortAndModeAndIsPublished() throws {
        let replay = try Self.replay(["plan-turn"])
        let state = try #require(replay.states[CodexSample.threadId])
        #expect(state.settings == CodexThreadSettings(model: "gpt-6-luna", effort: "high", mode: "plan"))
        #expect(replay.events.first == .settings(threadId: CodexSample.threadId, settings: CodexThreadSettings(model: "gpt-6-luna", effort: "high", mode: "plan")))

        var repeated = state
        let params = try #require(try CodexLiveReplay.messages("plan-turn").first?["params"])
        #expect(repeated.apply("thread/settings/updated", params, now: CodexLiveReplay.now).isEmpty)
    }

    @Test func aTurnSeenOnlyFromItsItemsStillOpensAndTheCompletionGivesItsStart() throws {
        var state = CodexThreadState(threadId: CodexSample.threadId)
        state.absorb(resume: try CodexSample.result("thread-resume.response.json"))
        let messages = try CodexLiveReplay.messages("basic-turn").filter { $0["method"]?.stringValue != "turn/started" }
        for message in messages.prefix(4) {
            guard let method = message["method"]?.stringValue, let params = message["params"] else { continue }
            _ = state.apply(method, params, now: CodexLiveReplay.now)
        }
        #expect(state.activeTurnId == "01a0f59f-9171-7672-873f-2cb30bf0915d")
        #expect(state.summary.turnEndedAt == nil)
        #expect(state.summary.turnStartedAt == Date(timeIntervalSince1970: 1_790_827_270.581))

        for message in messages.dropFirst(4) {
            guard let method = message["method"]?.stringValue, let params = message["params"] else { continue }
            _ = state.apply(method, params, now: CodexLiveReplay.now)
        }
        #expect(state.activeTurnId == nil)
        #expect(state.summary.turnStartedAt == Date(timeIntervalSince1970: 1_790_827_270))
    }

    @Test func aLateItemOfAnInterruptedTurnDoesNotReopenIt() throws {
        let replay = try Self.replay(["interrupted-turn"])
        let state = try #require(replay.states[CodexSample.threadId])
        #expect(state.activeTurnId == nil)
        #expect(state.summary.turnEndedAt == Date(timeIntervalSince1970: 1_790_827_647))
        #expect(replay.turnEnds.map(\.status) == ["interrupted"])
        let command = replay.chat(CodexSample.threadId).first { $0.id == "exec-f8463abb-8d46-412a-b723-6e3e75d4a917" }
        guard case .toolCall(let call) = command?.kind else {
            Issue.record("o comando do turno interrompido sumiu")
            return
        }
        #expect(call.status == .succeeded)
        #expect(command?.at == Date(timeIntervalSince1970: 1_790_827_624.4))
    }

    @Test func subagentCardsFollowTheChildAndIgnoreTheCollabWait() throws {
        let replay = try Self.replay(["subagent-turn"])
        let parent = replay.chat(CodexSample.threadId)
        let cards = parent.filter { $0.kind.type == "subagent" }
        #expect(cards.count == 1)
        guard case .subagent(let call) = cards.first?.kind else { return }
        #expect(call.agentId == CodexSample.otherThreadId)
        #expect(call.status == .completed)
        #expect(call.agentType == "list_directory")
        #expect(call.durationMs != nil)
        #expect(!parent.contains { $0.id == "call_6SK2Mv288IWJcHkyNP9oL7Qt" })
        #expect(replay.chat(CodexSample.otherThreadId).map(\.kind.type) == ["thinking", "toolCall", "assistantText", "turnFooter"])
        #expect(replay.states[CodexSample.threadId]?.cards[CodexSample.otherThreadId] == cards.first)
    }

    @Test func hydrationAfterTheResumeFillsTheSummaryFromTheLatestItemsAndTurns() throws {
        var state = CodexThreadState(threadId: CodexSample.threadId)
        state.absorb(resume: try CodexSample.result("thread-resume.response.json"))
        let listed = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-items-list.response.json"))["result"])
        let turnsResult = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-turns-list.response.json"))["result"])
        state.hydrate(turns: (turnsResult["data"]?.arrayValue ?? []).compactMap(CodexTurn.init), entries: CodexProjection.entries(listed))

        #expect(state.summary.preview == MessagePreview(author: .assistant, text: "Vou executar sleep 40 no terminal."))
        #expect(state.summary.prompt == "Rode sleep 40 no terminal e depois responda FIM.")
        #expect(state.lastAgentMessage == "Vou executar `sleep 40` no terminal.")
        #expect(state.summary.turnStartedAt == Date(timeIntervalSince1970: 1_790_827_620))
        #expect(state.summary.turnEndedAt == Date(timeIntervalSince1970: 1_790_827_647))
        #expect(state.summary.lastActivityAt == Date(timeIntervalSince1970: 1_790_827_623.147))
        #expect(state.activeTurnId == nil)

        var running = CodexThreadState(threadId: CodexSample.threadId)
        running.hydrate(turns: [CodexTurn(id: "t-ativo", status: .inProgress, startedAt: Date(timeIntervalSince1970: 1_790_827_700))], entries: [])
        #expect(running.activeTurnId == "t-ativo")
        #expect(running.summary.turnEndedAt == nil)
    }

    @Test func summaryAndChatMetaCarryEveryCodexField() throws {
        let state = try Self.state(["plan-turn", "command-turn", "basic-turn"])
        let agent = CodexChatSnapshotTests.agent(state)

        #expect(agent.sessionId == CodexSample.threadId)
        #expect(agent.title == "Responder OK1")
        #expect(agent.status == .idle)
        #expect(agent.controlAvailable == true)
        #expect(agent.model == "gpt-6-luna")
        #expect(agent.effort == "high")
        #expect(agent.permissionMode == "default")
        #expect(agent.branch == "s9-branch")
        #expect(agent.preview == MessagePreview(author: .assistant, text: "OK2"))
        #expect(agent.activity == ToolActivity(toolName: "Shell", summary: "cat hello.txt", status: .succeeded))
        #expect(agent.sessionStartedAt == Date(timeIntervalSince1970: 1_790_827_194))
        #expect(agent.turnStartedAt == Date(timeIntervalSince1970: 1_790_827_270))
        #expect(agent.turnEndedAt == Date(timeIntervalSince1970: 1_790_827_272))
        #expect(agent.lastActivityAt == Date(timeIntervalSince1970: 1_790_827_388.453))
        #expect(agent.contextLeftPercent == 97)
        #expect(agent.contextUsedTokens == 20_136)

        let meta = TreeComposer.agentChatMeta(summary: agent, meta: nil)
        #expect(meta == ChatMeta(
            title: "Responder OK1",
            workspaceLabel: "work",
            model: "gpt-6-luna",
            branch: "s9-branch",
            status: .idle,
            permissionMode: "default",
            effort: "high"
        ))
    }

    @Test func withoutABoundThreadTheTabKeepsHerdrFieldsAndNoControl() {
        let agent = CodexChatSnapshotTests.agent(nil)
        #expect(agent.controlAvailable == false)
        #expect(agent.sessionId == nil)
        #expect(agent.branch == "main")
        #expect(agent.title == "codex")
    }

    @Test func suspendDropsOnlyTheLivePart() throws {
        var state = try Self.replaying("command-turn") { message in
            message["method"]?.stringValue == "item/started" && message["params"]?["item"]?["type"]?.stringValue == "commandExecution"
        }
        state.suspend()
        #expect(state.activeTurnId == nil)
        #expect(state.summary.title == "Responder OK1")
        #expect(state.settings.model == "gpt-6-luna")
        #expect(state.summary.activity == ToolActivity(toolName: "Shell", summary: "printf 'oi' > hello.txt", status: .running))
    }
}
