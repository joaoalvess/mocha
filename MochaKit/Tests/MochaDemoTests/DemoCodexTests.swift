import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoCodexTests {
    private let plan = DemoCodex.planAgentId
    private let working = DemoCodex.workingAgentId
    private let noControl: AgentID = "w4:p3"

    private func nextMeta(_ harness: DemoHarness) async throws -> ChatMeta {
        let envelope = try await harness.messages.next { if case .chatMeta = $0.message { true } else { false } }
        guard case .chatMeta(_, let meta) = envelope.message else { throw UnexpectedMessage(envelope: envelope) }
        return meta
    }

    private func nextAppend(_ harness: DemoHarness, to agentId: AgentID) async throws -> [ChatItem] {
        let envelope = try await harness.messages.next {
            if case .chatAppend(.agent(agentId), _) = $0.message { true } else { false }
        }
        guard case .chatAppend(_, let items) = envelope.message else { throw UnexpectedMessage(envelope: envelope) }
        return items
    }

    @Test func bundledCodexAgentsCoverPlanWorkingAndNoControl() throws {
        let dataset = try DemoDataset.bundled()
        let planAgent = try #require(dataset.workspaces.agent(withId: plan))
        #expect(planAgent.kind == "codex")
        #expect(planAgent.status == .idle)
        #expect(planAgent.controlAvailable == true)
        #expect(planAgent.permissionMode == "plan")
        #expect(planAgent.model == "gpt-6-luna")
        #expect(planAgent.effort == "high")
        #expect(planAgent.branch == "development")
        #expect(planAgent.sessionId == DemoCodex.planThreadId)
        let workingAgent = try #require(dataset.workspaces.agent(withId: working))
        #expect(workingAgent.status == .working)
        #expect(workingAgent.permissionMode == "default")
        #expect(workingAgent.runningSubagents == 1)
        #expect(workingAgent.activity?.status == .running)
        #expect(dataset.workspaces.agent(withId: noControl)?.controlAvailable == false)
        let archived = try #require(dataset.archived.first { $0.provider == .codex })
        #expect(archived.id == DemoCodex.archivedThreadId)
        #expect(dataset.codexUsage?.provider == .codex)
        #expect(dataset.codexSubagents.map(\.agentId) == [DemoCodex.workingChildThreadId, DemoCodex.archivedChildThreadId])
    }

    @Test func planChatEndsWithThePlanAndTheTurnFooter() throws {
        let dataset = try DemoDataset.bundled()
        let items = try #require(dataset.chats.first { $0.agentId == plan }?.items)
        #expect(items.map(\.kind.type).suffix(2) == ["assistantText", "turnFooter"])
        let last = items[items.count - 2]
        #expect(last.id == DemoCodex.planItemId)
        if case .assistantText(let markdown) = last.kind {
            #expect(markdown.hasPrefix("## Plano"))
        } else {
            Issue.record("o turno não termina num plano")
        }
    }

    @Test func emptyDemoHasNoCodexData() throws {
        let dataset = try DemoDataset.bundled(isEmpty: true)
        #expect(dataset.codexUsage == nil)
        #expect(dataset.codexSubagents.isEmpty)
        #expect(!dataset.archived.contains { $0.provider == .codex })
    }

    @Test func listModelsAnswersTheListOfTheProtocolFixture() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let reply = try await harness.request(.listModels(agentId: plan))

        let fixture = try JSONDecoder().decode(ServerEnvelope.self, from: Fixtures.data("protocol/server.models.json"))
        guard case .models(_, let expected) = fixture.message else { throw UnexpectedMessage(envelope: fixture) }
        #expect(reply.message == .models(agentId: plan, options: expected))
    }

    @Test func listModelsRejectsClaudeAndCodexWithoutControl() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let claude = try await harness.error(for: .listModels(agentId: "w1:p1"))
        #expect(claude.code == .invalidPayload)
        #expect(claude.message == "Lista de modelos só para Codex")
        #expect(try await harness.error(for: .listModels(agentId: noControl)).code == .codexUnavailable)
        #expect(try await harness.error(for: .listModels(agentId: "w99:p1")).code == .agentNotFound)
    }

    @Test func modelAndEffortFollowTheCodexList() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(plan)

        #expect(try await harness.request(.setModel(agentId: plan, model: "gpt-6.1-sol")).message == .ack())
        var meta = try await nextMeta(harness)
        #expect(meta.model == "gpt-6.1-sol")
        #expect(meta.effort == "high")

        #expect(try await harness.request(.setEffort(agentId: plan, level: "ultra")).message == .ack())
        meta = try await nextMeta(harness)
        #expect(meta.effort == "ultra")

        #expect(try await harness.request(.setModel(agentId: plan, model: "gpt-6-luna")).message == .ack())
        meta = try await nextMeta(harness)
        #expect(meta.model == "gpt-6-luna")
        #expect(meta.effort == "medium")
        let tree = try #require(try await harness.messages.next { $0.message.changedWorkspaces != nil }.message.changedWorkspaces)
        #expect(tree.agent(withId: plan)?.effort == "medium")

        #expect(try await harness.error(for: .setModel(agentId: plan, model: "gpt-oculto")).code == .invalidPayload)
        #expect(try await harness.error(for: .setEffort(agentId: plan, level: "ultra")).code == .invalidPayload)
        #expect(try await harness.error(for: .setModel(agentId: noControl, model: "gpt-6-luna")).code == .codexUnavailable)
    }

    @Test func codexModesAreOnlyDefaultAndPlan() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(working)

        #expect(try await harness.request(.setMode(agentId: working, mode: .plan)).message == .ack())
        #expect(try await nextMeta(harness).permissionMode == "plan")
        for mode in [PermissionModeTarget.acceptEdits, .auto] {
            let error = try await harness.error(for: .setMode(agentId: working, mode: mode))
            #expect(error.code == .invalidPayload)
            #expect(error.message == "Modo indisponível no Codex")
        }
    }

    @Test func implementingThePlanSwitchesToDefaultAndSendsThePrompt() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(plan)

        #expect(try await harness.request(.setMode(agentId: plan, mode: .default)).message == .ack())
        #expect(try await nextMeta(harness).permissionMode == "default")
        #expect(try await harness.request(.sendPrompt(agentId: plan, text: "Implemente o plano.")).message == .ack())

        let echoed = try await nextAppend(harness, to: plan)
        #expect(echoed.map(\.kind) == [.userPrompt(text: "Implemente o plano.", imageCount: 0)])
        let replied = try await nextAppend(harness, to: plan)
        #expect(replied.first?.kind == .assistantText(markdown: DemoServerConnection.codexReplyMarkdown))
    }

    @Test func compactAddsTheCompactedNotice() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(plan)

        #expect(try await harness.request(.slash(agentId: plan, command: "/compact")).message == .ack())

        let items = try await nextAppend(harness, to: plan)
        #expect(items.map(\.kind) == [.notice(text: "Contexto compactado")])
    }

    @Test func otherSlashCommandsAreUnavailableOnCodex() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let error = try await harness.error(for: .slash(agentId: plan, command: "/model"))

        #expect(error.code == .invalidPayload)
        #expect(error.message == "Comando indisponível no Codex")
    }

    @Test func clearOpensANewPaneAcksItAndArchivesTheThread() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let before = try await harness.page(plan)

        let ack = try await harness.request(.slash(agentId: plan, command: "/clear"))

        let newId: AgentID = "w3:p7"
        #expect(ack.message == .ack(agentId: newId))
        let tree = try #require(await harness.messages.all().compactMap(\.message.changedWorkspaces).last)
        #expect(tree.agent(withId: plan) == nil)
        let fresh = try #require(tree.agent(withId: newId))
        #expect(fresh.kind == "codex")
        #expect(fresh.sessionId != DemoCodex.planThreadId)
        #expect(fresh.permissionMode == "plan")
        #expect(fresh.model == "gpt-6-luna")
        #expect(fresh.preview == nil)
        let archived = try #require(await harness.messages.all().compactMap(\.message.archivedSessions).last)
        let session = try #require(archived.first)
        #expect(session.id == DemoCodex.planThreadId)
        #expect(session.provider == .codex)
        #expect(session.reason == .cleared)
        #expect(session.agentId == plan)

        let newPage = try await harness.page(newId)
        #expect(newPage.items.isEmpty)
        #expect(try await harness.page(plan).target == .agent(newId))
        let thread = try await harness.page(.codexThread(DemoCodex.planThreadId))
        #expect(thread.items.map(\.id) == before.items.map(\.id))
    }

    @Test func codexSubagentListOpensTheChildThread() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let list = try await harness.request(.listSubagents(agentId: working))
        guard case .subagentList(_, let items) = list.message else { throw UnexpectedMessage(envelope: list) }
        #expect(items.map(\.agentId) == [DemoCodex.workingChildThreadId])
        #expect(items.map(\.status) == [.running])

        let child = try await harness.page(.codexThread(DemoCodex.workingChildThreadId))
        #expect(child.target == .codexThread(DemoCodex.workingChildThreadId))
        let info = try #require(child.meta.subagent)
        #expect(info.parentTitle == "Migrations de índice")
        #expect(info.status == .running)
        #expect(child.meta.title == "Revisar migrations de índice")
        #expect(child.items.count == 3)
        #expect(try await harness.request(.closeChat(target: .codexThread(DemoCodex.workingChildThreadId))).message == .ack())
    }

    @Test func archivedCodexThreadOpensItsCompletedChild() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let parent = try await harness.page(.codexThread(DemoCodex.archivedThreadId))
        let card = try #require(parent.items.compactMap { item -> SubagentCall? in
            if case .subagent(let call) = item.kind { call } else { nil }
        }.first)
        #expect(card.agentId == DemoCodex.archivedChildThreadId)
        #expect(card.status == .completed)

        let child = try await harness.page(.codexThread(DemoCodex.archivedChildThreadId))
        #expect(child.meta.subagent?.parentTitle == "Contrato da API de receitas")
        #expect(child.meta.subagent?.status == .completed)
        #expect(child.meta.subagent?.durationMs == 45_000)
    }

    @Test func swipeArchivesTheCodexThread() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        #expect(try await harness.error(for: .archive(sessionId: DemoCodex.planThreadId, provider: .claude)).code == .sessionNotFound)
        #expect(try await harness.request(.archive(sessionId: DemoCodex.planThreadId, provider: .codex)).message == .ack())

        let tree = try #require(try await harness.messages.next { $0.message.changedWorkspaces != nil }.message.changedWorkspaces)
        #expect(tree.agent(withId: plan)?.archivedAt != nil)
    }

    @Test func codexWithoutControlStaysReadOnly() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        #expect(!(try await harness.page(noControl).items.isEmpty))
        for request in [
            ClientMessage.sendPrompt(agentId: noControl, text: "oi"),
            .setMode(agentId: noControl, mode: .plan),
            .slash(agentId: noControl, command: "/compact"),
            .listSubagents(agentId: noControl),
        ] {
            #expect(try await harness.error(for: request).code == .codexUnavailable, "\(request.type)")
        }
    }
}
