import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

extension ChatItem {
    var subagentCall: SubagentCall? {
        guard case .subagent(let call) = kind else { return nil }
        return call
    }

    var workflowCall: WorkflowCall? {
        guard case .workflow(let call) = kind else { return nil }
        return call
    }
}

private let receitas: AgentID = "w3:p1"
private let loadTestCardId = "card-" + DemoSubagents.loadTestAgentId
private let screen18 = [
    "Teste de carga /receitas", "Achar o script de carga", "Mapear uso de OFFSET", "Gerar fixtures de carga",
    "Revisar o índice de receitas",
]

@Suite struct DemoSubagentDataTests {
    let launch = Date(timeIntervalSince1970: 1_800_000_000)
    let dataset: DemoDataset

    init() throws {
        dataset = try DemoDataset.bundled(now: launch)
    }

    private func chat(_ agentId: AgentID) throws -> [ChatItem] {
        try #require(dataset.chats.first { $0.agentId == agentId }).items
    }

    private func turn(of items: [ChatItem]) -> ArraySlice<ChatItem> {
        let promptIndex = items.lastIndex { if case .userPrompt = $0.kind { true } else { false } } ?? items.startIndex
        return items[promptIndex...]
    }

    @Test func receitasEndsLikeScreen16WithTheOtherSubagentsOfScreen18Above() throws {
        let items = try chat(receitas)
        let cards = items.compactMap(\.subagentCall)
        #expect(cards.map(\.description) == [
            "Revisar o índice de receitas", "Gerar fixtures de carga", "Mapear uso de OFFSET", "Teste de carga /receitas",
        ])
        #expect(turn(of: items).compactMap(\.subagentCall).map(\.description) == ["Mapear uso de OFFSET", "Teste de carga /receitas"])

        let failed = cards[0]
        #expect(failed.agentType == "Plan")
        #expect(failed.status == .failed)
        #expect(failed.durationMs == 48_000)
        #expect(failed.toolUses == 3)
        #expect(failed.failureReason == "Agent terminated early due to an API error: 529 Overloaded")
        #expect(cards[1].agentType == "general-purpose")
        #expect(cards[1].status == .completed)
        #expect(cards[1].durationMs == 220_000)
        #expect(cards[1].toolUses == 22)
        #expect(cards[2].agentType == "Explore")
        #expect(cards[2].status == .completed)
        #expect(cards[2].durationMs == 134_000)
        #expect(cards[2].toolUses == 18)

        let running = cards[3]
        #expect(running.agentId == DemoSubagents.loadTestAgentId)
        #expect(running.agentType == "general-purpose")
        #expect(running.status == .running)
        #expect(running.activity == ToolActivity(toolName: "Bash", summary: "k6 run --vus 50 --duration 2m load/list-recipes.js", status: .running))
        #expect(running.toolUses == 9)
        #expect(running.durationMs == nil)
        #expect(launch.timeIntervalSince(try #require(running.startedAt)) == 231)
        #expect(cards.allSatisfy { $0.failureReason == nil || $0.status == .failed })
        #expect(dataset.workspaces.agent(withId: receitas)?.runningSubagents == 1)
    }

    @Test func demoAppEndsWithTheRunningWorkflowOfScreen19AndStaysDone() throws {
        let items = try chat(DemoSubagents.demoAppAgentId)
        let current = turn(of: items)
        #expect(current.map(\.kind.type) == [
            "userPrompt", "thinking", "toolCall", "assistantText", "workflow", "assistantText", "turnFooter",
        ])
        #expect(current.last?.kind == .turnFooter(durationMs: 18_000))
        let previous = items[items.index(before: current.startIndex)]
        #expect(previous.kind == .turnFooter(durationMs: 72_000))
        #expect(items[items.index(before: current.startIndex) - 1].kind == .assistantText(
            markdown: "Os testes da tela de ajustes passaram. Quer que eu rode a auditoria de acessibilidade também?"
        ))

        let workflow = try #require(current.compactMap(\.workflowCall).first)
        #expect(workflow.name == "auditoria-a11y")
        #expect(workflow.runId == DemoSubagents.auditRunId)
        #expect(workflow.status == .running)
        #expect(workflow.agentCount == 5)
        #expect(workflow.toolUses == 86)
        #expect(workflow.durationMs == nil)
        #expect(launch.timeIntervalSince(try #require(workflow.startedAt)) == 372)
        #expect(workflow.phases.map(\.title) == ["Mapear telas", "Corrigir por tela", "Revisar"])
        #expect(workflow.phases.map(\.status) == [.completed, .running, .pending])
        #expect(workflow.phases.map(\.detail) == [nil, "uma tela por agente, com testes de UI", nil])
        #expect(workflow.phases.map { $0.agents.map(\.label) } == [["Mapear"], ["Ajustes", "Perfil", "Login", "Home"], []])
        let fixing = workflow.phases[1].agents
        #expect(fixing.map(\.status) == [.running, .running, .completed, .completed])
        #expect(fixing.map(\.activity) == [
            ToolActivity(toolName: "Edit", summary: "SettingsView.swift", status: .running),
            ToolActivity(toolName: "Read", summary: "ProfileView.swift", status: .running),
            nil,
            nil,
        ])
        #expect(fixing.map(\.durationMs) == [nil, nil, 108_000, 125_000])
        #expect(workflow.phases[0].agents.first?.durationMs == 95_000)

        let agent = try #require(dataset.workspaces.agent(withId: DemoSubagents.demoAppAgentId))
        #expect(agent.status == .idle)
        #expect(agent.runningSubagents == 2)
        #expect(agent.lastActivityAt == items.last?.at)
    }

    @Test func loginSocialHistoryHasAStoppedSubagentAndAFinishedWorkflow() throws {
        let items = try chat(DemoSubagents.loginAgentId)
        #expect(items.map(\.at) == items.map(\.at).sorted())
        let stopped = try #require(items.compactMap(\.subagentCall).first)
        #expect(items.compactMap(\.subagentCall).count == 1)
        #expect(stopped.agentType == "Explore")
        #expect(stopped.status == .stopped)
        #expect(stopped.durationMs == 62_000)
        #expect(stopped.toolUses == 6)
        #expect(stopped.activity == nil)
        let workflow = try #require(items.compactMap(\.workflowCall).first)
        #expect(workflow.name == "auditoria-a11y")
        #expect(workflow.status == .completed)
        #expect(workflow.agentCount == 10)
        #expect(workflow.durationMs == 131_000)
        #expect(workflow.phases.allSatisfy { $0.status == .completed })
        #expect(workflow.phases.flatMap(\.agents).allSatisfy { $0.status == .completed && $0.durationMs != nil })
        #expect(dataset.workspaces.agent(withId: DemoSubagents.loginAgentId)?.runningSubagents == 0)
    }

    @Test func runningSubagentsIsSetOnlyOnSessionsWithSubagents() {
        let counts = Dictionary(uniqueKeysWithValues: dataset.workspaces.allAgents.map { ($0.id, $0.runningSubagents) })
        #expect(counts == [
            "w1:p1": 2, "w5:p1": 0, "w2:p1": nil, "w3:p1": 1, "w3:p2": nil, "w4:p2": nil, "w4:p3": nil,
        ])
    }

    @Test func everySubagentHasATranscriptWithTheTaskOnTopThatMatchesItsCard() throws {
        let cards = (dataset.chats.flatMap(\.items) + dataset.subagents.flatMap(\.items)).compactMap(\.subagentCall)
        let workflowAgents = dataset.chats.flatMap(\.items).compactMap(\.workflowCall).flatMap { $0.phases.flatMap(\.agents) }
        #expect(dataset.subagents.count == 21)
        #expect(Set(dataset.subagents.map { "\($0.sessionId)/\($0.agentId)" }).count == dataset.subagents.count)
        for subagent in dataset.subagents {
            let items = subagent.items
            guard case .task = items.first?.kind else {
                Issue.record("\(subagent.description) não começa com a tarefa")
                continue
            }
            #expect(items.first?.at == subagent.startedAt, "\(subagent.description)")
            #expect(Set(items.map(\.id)).count == items.count, "\(subagent.description)")
            #expect(items.map(\.at) == items.map(\.at).sorted(), "\(subagent.description)")
            let toolUses = items.count { $0.toolCall != nil || $0.subagentCall != nil }
            #expect(toolUses == subagent.toolUses, "\(subagent.description)")
            #expect((subagent.status == .running) == items.contains { $0.toolCall?.status == .running }, "\(subagent.description)")
            #expect(DemoServerConnection.isValidSubagentId(subagent.agentId))
            if subagent.isWorkflowAgent {
                #expect(subagent.agentType == DemoSubagents.workflowAgentType)
                #expect(workflowAgents.filter { $0.agentId == subagent.agentId } == [subagent.workflowAgent])
            } else {
                #expect(cards.filter { $0.agentId == subagent.agentId } == [subagent.call], "\(subagent.description)")
            }
        }
    }

    @Test func subagentTimesAreRelativeToTheLaunch() throws {
        let later = try DemoDataset.bundled(now: launch.addingTimeInterval(3_600))
        for (now, then) in zip(dataset.subagents, later.subagents) {
            #expect(then.startedAt.timeIntervalSince(now.startedAt) == 3_600)
        }
        let card = { (dataset: DemoDataset) in
            dataset.chats.flatMap(\.items).first { $0.id == loadTestCardId }?.subagentCall?.startedAt
        }
        #expect(try #require(card(later)).timeIntervalSince(try #require(card(dataset))) == 3_600)
    }

    @Test func listOrderPutsRunningFirstThenTheLatestEndAndNestsUnderTheParent() {
        let base = Date(timeIntervalSince1970: 1_000)
        func subagent(_ id: String, parent: String? = nil, _ status: SubagentStatus, started: TimeInterval, duration: Int? = nil, workflow: Bool = false) -> DemoSubagent {
            DemoSubagent(
                sessionId: "s",
                agentId: id,
                parentAgentId: parent,
                toolUseId: workflow ? nil : "toolu_" + id,
                agentType: "Explore",
                description: id,
                status: status,
                toolUses: 1,
                startedAt: base.addingTimeInterval(started),
                durationMs: duration,
                items: []
            )
        }
        let subagents = [
            subagent("oldRunning", .running, started: 10),
            subagent("newRunning", .running, started: 50),
            subagent("longDone", .completed, started: 0, duration: 90_000),
            subagent("shortDone", .failed, started: 60, duration: 5_000),
            subagent("childOfOld", parent: "oldRunning", .stopped, started: 20, duration: 1_000),
            subagent("grandchild", parent: "childOfOld", .completed, started: 21, duration: 500),
            subagent("orphan", parent: "gone", .completed, started: 70, duration: 1_000),
            subagent("workflowAgent", .running, started: 80, workflow: true),
            DemoSubagent(
                sessionId: "other",
                agentId: "otherSession",
                toolUseId: "toolu",
                agentType: "Plan",
                description: "otherSession",
                status: .running,
                toolUses: 0,
                startedAt: base,
                items: []
            ),
        ]

        let list = subagents.summaries(inSession: "s")

        #expect(list.map(\.agentId) == ["newRunning", "oldRunning", "childOfOld", "grandchild", "longDone", "orphan", "shortDone"])
        #expect(list.map(\.parentAgentId) == [nil, nil, "oldRunning", "childOfOld", nil, "gone", nil])
        #expect(subagents.runningSubagents(inSession: "s") == 3)
        #expect(subagents.runningSubagents(inSession: "nenhuma") == nil)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct DemoSubagentConnectionTests {
    @Test func openChatWithSubagentIdReturnsEachTranscriptWithTheSubagentMeta() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        for subagent in harness.dataset.subagents {
            let target = ChatTarget.subagent(sessionId: subagent.sessionId, agentId: subagent.agentId)
            let page = try await harness.page(target, limit: 200)
            #expect(page.target == target)
            #expect(page.items == subagent.items)
            #expect(page.hasMore == false)
            #expect(page.before == nil)
            #expect(page.meta.title == subagent.description)
            #expect(page.meta.status == .unknown)
            #expect(page.meta.permissionMode == nil)
            #expect(page.meta.model == "claude-opus-5-5")
            let info = try #require(page.meta.subagent)
            #expect(info.agentType == subagent.agentType)
            #expect(info.status == subagent.status)
            #expect(info.startedAt == subagent.startedAt)
            #expect(info.durationMs == subagent.durationMs)
            #expect(info.toolUses == subagent.toolUses)
            #expect(info.failureReason == subagent.failureReason)
        }

        let running = try await harness.page(.subagent(sessionId: DemoSubagents.receitasSessionId, agentId: DemoSubagents.loadTestAgentId))
        #expect(running.meta == ChatMeta(
            title: "Teste de carga /receitas",
            workspaceLabel: "receitas-api",
            model: "claude-opus-5-5",
            branch: "development",
            status: .unknown,
            subagent: SubagentChatInfo(
                parentTitle: "Paginação com cursor em /receitas",
                agentType: "general-purpose",
                status: .running,
                startedAt: harness.launch.addingTimeInterval(-231),
                toolUses: 9
            )
        ))
        #expect(running.items.map(\.kind.type).prefix(3) == ["task", "thinking", "subagent"])
        #expect(running.items[2].subagentCall?.description == "Achar o script de carga")
        #expect(running.items.last?.toolCall?.status == .running)

        let nested = try await harness.page(.subagent(sessionId: DemoSubagents.receitasSessionId, agentId: "a76543210fedcba98"))
        #expect(nested.meta.subagent?.parentTitle == "Teste de carga /receitas")
        let failed = try await harness.page(.subagent(sessionId: DemoSubagents.receitasSessionId, agentId: "a89abcdef01234567"))
        #expect(failed.meta.subagent?.failureReason == "Agent terminated early due to an API error: 529 Overloaded")
        let workflowAgent = try await harness.page(.subagent(sessionId: DemoSubagents.demoAppSessionId, agentId: "a2222222222222222"))
        #expect(workflowAgent.meta.title == "Ajustes")
        #expect(workflowAgent.meta.workspaceLabel == "demo-app")
        #expect(workflowAgent.meta.branch == "main")
        #expect(workflowAgent.meta.subagent?.parentTitle == "Testes e tela de ajustes")
        #expect(workflowAgent.meta.subagent?.agentType == "workflow-subagent")
    }

    @Test func subagentTranscriptPaginatesBackwards() async throws {
        let harness = try DemoHarness()
        let fixtures = try #require(harness.dataset.subagents.first { $0.description == "Gerar fixtures de carga" })
        #expect(fixtures.items.count > 10)
        try await harness.connect()
        let target = ChatTarget.subagent(sessionId: fixtures.sessionId, agentId: fixtures.agentId)

        var page = try await harness.page(target, limit: 10)
        var collected = page.items
        while page.hasMore {
            page = try await harness.page(target, before: try #require(page.before), limit: 10)
            collected = page.items + collected
        }

        #expect(collected == fixtures.items)
        #expect(page.items.first?.kind.type == "task")
    }

    @Test func openAndCloseChatWithSubagentIdFollowTheServerRules() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let session = DemoSubagents.receitasSessionId
        let known = DemoSubagents.loadTestAgentId
        let invalidIds = ["", "a b", "../agent-a0123456789abcdef", "a0123456789abcdef.jsonl", String(repeating: "a", count: 65)]
        var cases: [(ClientMessage, ProtocolErrorCode, String)] = [
            (.openChat(target: .subagent(sessionId: "nao-e-uuid", agentId: known)), .invalidPayload, "Id de sessão inválido."),
            (.closeChat(target: .subagent(sessionId: "nao-e-uuid", agentId: known)), .invalidPayload, "Id de sessão inválido."),
            (.openChat(target: .subagent(sessionId: session, agentId: String(repeating: "a", count: 64))), .sessionNotFound, "Subagente não encontrado"),
            (.openChat(target: .subagent(sessionId: session, agentId: "a0000000000000000")), .sessionNotFound, "Subagente não encontrado"),
            (.openChat(target: .subagent(sessionId: DemoSubagents.demoAppSessionId, agentId: known)), .sessionNotFound, "Subagente não encontrado"),
            (.openChat(target: .subagent(sessionId: UUID().uuidString.lowercased(), agentId: known)), .sessionNotFound, "Subagente não encontrado"),
            (.closeChat(target: .subagent(sessionId: session, agentId: "a0000000000000000")), .sessionNotFound, "Subagente não encontrado"),
            (.openChat(target: .subagent(sessionId: session, agentId: known), before: "demo:99"), .invalidPayload, "Cursor de paginação inválido."),
        ]
        for invalid in invalidIds {
            cases.append((.openChat(target: .subagent(sessionId: session, agentId: invalid)), .invalidPayload, "Id de subagente inválido."))
            cases.append((.closeChat(target: .subagent(sessionId: session, agentId: invalid)), .invalidPayload, "Id de subagente inválido."))
        }
        for (request, code, message) in cases {
            let error = try await harness.error(for: request)
            #expect(error.code == code, "\(request)")
            #expect(error.message == message, "\(request)")
        }

        let closed = try await harness.request(.closeChat(target: .subagent(sessionId: session, agentId: known)))
        #expect(closed.message == .ack())
    }

    @Test func subagentOfAnArchivedSessionStillOpens() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.request(.slash(agentId: receitas, command: "/clear"))
        let cleared = try await harness.messages.next { $0.message.changedWorkspaces?.agent(withId: receitas)?.sessionId != DemoSubagents.receitasSessionId }
        #expect(cleared.message.changedWorkspaces?.agent(withId: receitas)?.runningSubagents == nil)

        let page = try await harness.page(.subagent(sessionId: DemoSubagents.receitasSessionId, agentId: DemoSubagents.loadTestAgentId))
        #expect(page.meta.subagent?.parentTitle == "Paginação com cursor em /receitas")
        #expect(page.meta.workspaceLabel == "receitas-api")
        let list = try await harness.request(.listSubagents(agentId: receitas))
        #expect(list.message == .subagentList(agentId: receitas, items: []))
    }

    @Test func listSubagentsReturnsTheListOfScreen18() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let envelope = try await harness.request(.listSubagents(agentId: receitas))

        guard case .subagentList(let agentId, let items) = envelope.message else { throw UnexpectedMessage(envelope: envelope) }
        #expect(agentId == receitas)
        #expect(items.map(\.description) == screen18)
        #expect(items.map(\.agentType) == ["general-purpose", "Explore", "Explore", "general-purpose", "Plan"])
        #expect(items.map(\.status) == [.running, .completed, .completed, .completed, .failed])
        #expect(items.map(\.toolUses) == [9, 5, 18, 22, 3])
        #expect(items.map(\.durationMs) == [nil, 41_000, 134_000, 220_000, 48_000])
        #expect(items.map(\.parentAgentId) == [nil, DemoSubagents.loadTestAgentId, nil, nil, nil])
        #expect(items.allSatisfy { $0.startedAt != nil })
    }

    @Test func listSubagentsFollowsTheServerRules() async throws {
        let harness = try DemoHarness(adjusting: { dataset in
            dataset.workspaces.updateAgent(withId: "w3:p2") { $0.sessionId = nil }
        })
        try await harness.connect()

        let demoApp = try await harness.request(.listSubagents(agentId: DemoSubagents.demoAppAgentId))
        #expect(demoApp.message == .subagentList(agentId: DemoSubagents.demoAppAgentId, items: []))
        let login = try await harness.request(.listSubagents(agentId: DemoSubagents.loginAgentId))
        guard case .subagentList(_, let loginItems) = login.message else { throw UnexpectedMessage(envelope: login) }
        #expect(loginItems.map(\.status) == [.stopped])
        for agentId in ["w2:p1", "w3:p2"] {
            let empty = try await harness.request(.listSubagents(agentId: agentId))
            #expect(empty.message == .subagentList(agentId: agentId, items: []), "\(agentId)")
        }
        let unknown = try await harness.error(for: .listSubagents(agentId: "w99:p1"))
        #expect(unknown.code == .agentNotFound)
        let codex = try await harness.error(for: .listSubagents(agentId: "w4:p3"))
        #expect(codex.code == .invalidPayload)
        #expect(codex.message == DemoServerConnection.claudeOnlyMessage)
    }

    @Test func scriptFinishesTheRunningSubagentEverywhereItIsShown() async throws {
        let harness = try DemoHarness(.script)
        let transcript = ChatTarget.subagent(sessionId: DemoSubagents.receitasSessionId, agentId: DemoSubagents.loadTestAgentId)
        try await harness.connect()
        _ = try await harness.page(receitas)
        _ = try await harness.page(.session(DemoSubagents.receitasSessionId))
        let opened = try await harness.page(transcript)
        let runningTool = try #require(opened.items.last)

        let card = try await harness.messages.next { $0.message.type == "chatUpdate" }
        guard case .chatUpdate(.agent(receitas), let cardItems) = card.message else { throw UnexpectedMessage(envelope: card) }
        let finished = try #require(cardItems.first?.subagentCall)
        #expect(cardItems.map(\.id) == [loadTestCardId])
        #expect(finished.status == .completed)
        #expect(finished.activity == nil)
        #expect(finished.toolUses == 9)
        let durationMs = try #require(finished.durationMs)
        #expect(durationMs > 231_000)
        let sessionCard = try await harness.messages.next()
        #expect(sessionCard.message == .chatUpdate(target: .session(DemoSubagents.receitasSessionId), items: cardItems))

        let toolUpdate = try await harness.messages.next()
        guard case .chatUpdate(transcript, let tools) = toolUpdate.message else { throw UnexpectedMessage(envelope: toolUpdate) }
        #expect(tools.map(\.id) == [runningTool.id])
        #expect(tools.first?.toolCall?.status == .succeeded)
        #expect(tools.first?.toolCall?.resultPreview == DemoSubagents.loadTestResult)
        let answer = try await harness.messages.next()
        #expect(answer.message.type == "chatAppend")
        guard case .chatAppend(transcript, let appended) = answer.message else { throw UnexpectedMessage(envelope: answer) }
        #expect(appended.map(\.kind) == [.assistantText(markdown: DemoSubagents.loadTestAnswer)])
        let meta = try await harness.messages.next()
        guard case .chatMeta(transcript, let chatMeta) = meta.message else { throw UnexpectedMessage(envelope: meta) }
        #expect(chatMeta.subagent?.status == .completed)
        #expect(chatMeta.subagent?.durationMs == durationMs)
        let tree = try await harness.messages.next()
        #expect(tree.message.changedWorkspaces?.agent(withId: receitas)?.runningSubagents == 0)

        let list = try await harness.request(.listSubagents(agentId: receitas))
        guard case .subagentList(_, let items) = list.message else { throw UnexpectedMessage(envelope: list) }
        #expect(items.map(\.description) == screen18)
        #expect(items.first?.status == .completed)
        #expect(items.first?.durationMs == durationMs)
        let reopened = try await harness.page(transcript)
        #expect(reopened.items.last?.kind == .assistantText(markdown: DemoSubagents.loadTestAnswer))
        #expect(reopened.meta == chatMeta)
    }

    @Test func closedSubagentTranscriptReceivesNoEvents() async throws {
        let harness = try DemoHarness(.script)
        let transcript = ChatTarget.subagent(sessionId: DemoSubagents.receitasSessionId, agentId: DemoSubagents.loadTestAgentId)
        try await harness.connect()
        _ = try await harness.page(transcript)
        _ = try await harness.request(.closeChat(target: transcript))

        _ = try await harness.messages.next { $0.message.changedWorkspaces?.agent(withId: receitas)?.runningSubagents == 0 }

        let targets = await harness.messages.all().compactMap { envelope -> ChatTarget? in
            switch envelope.message {
            case .chatAppend(let target, _), .chatUpdate(let target, _), .chatMeta(let target, _): target
            default: nil
            }
        }
        #expect(!targets.contains(transcript))
    }
}
