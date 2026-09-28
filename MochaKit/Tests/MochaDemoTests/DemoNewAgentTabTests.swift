import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoNewAgentTabTests {
    @Test func codexTabCanChatWhenControlIsAvailable() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let ack = try await harness.request(.newAgentTab(workspaceId: "w1", kind: .codex))
        guard case .ack(let agentId?) = ack.message else { throw UnexpectedMessage(envelope: ack) }
        let tree = try #require(await harness.messages.all().last { $0.message.changedWorkspaces != nil }?.message.changedWorkspaces)
        let agent = try #require(tree.agent(withId: agentId))
        #expect(agent.kind == "codex")
        #expect(agent.controlAvailable == true)
        #expect(try await harness.page(agentId).target == .agent(agentId))
        #expect(try await harness.request(.sendPrompt(agentId: agentId, text: "oi")).message == .ack())
    }

    @Test func acksWithTheNewAgentAfterSendingTheTreeThatHasIt() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let originalTabs = try #require(harness.dataset.workspaces.first { $0.id == "w1" }?.tabs)

        let ack = try await harness.request(.newAgentTab(workspaceId: "w1"))

        guard case .ack(let agentId?) = ack.message else { throw UnexpectedMessage(envelope: ack) }
        let all = await harness.messages.all()
        let ackIndex = try #require(all.firstIndex { $0.id == ack.id })
        let treeIndex = try #require(all.firstIndex { $0.message.changedWorkspaces?.agent(withId: agentId) != nil })
        #expect(treeIndex < ackIndex)
        let tree = try #require(all[treeIndex].message.changedWorkspaces)
        let workspace = try #require(tree.first { $0.id == "w1" })
        #expect(workspace.tabs.dropLast() == originalTabs[...])
        let tab = try #require(workspace.tabs.last)
        #expect(tab.id == "w1:t3")
        #expect(tab.title == DemoNewAgentTab.tabTitle)
        let agent = try #require(tab.agents.first)
        #expect(tab.agents.count == 1)
        #expect(agent.id == "w1:p3")
        #expect(agent.kind == "claude")
        #expect(agent.status == .idle)
        #expect(agent.title == DemoNewAgentTab.agentTitle)
        #expect(agent.workspaceLabel == workspace.label)
        #expect(agent.branch == workspace.branch)
        #expect(agent.preview == nil)
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func newAgentOpensAnEmptyChatAndAnswersTheFirstPrompt() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let ack = try await harness.request(.newAgentTab(workspaceId: "w3"))
        guard case .ack(let agentId?) = ack.message else { throw UnexpectedMessage(envelope: ack) }

        let page = try await harness.page(agentId)

        #expect(page.target == .agent(agentId))
        #expect(page.items.isEmpty)
        #expect(page.before == nil)
        #expect(!page.hasMore)
        #expect(page.meta.title == DemoNewAgentTab.agentTitle)
        #expect(page.meta.workspaceLabel == "receitas-api")
        #expect(page.meta.status == .idle)

        let sent = try await harness.request(.sendPrompt(agentId: agentId, text: "oi"))
        #expect(sent.message == .ack())
        _ = try await harness.messages.next { $0.message == .agentStatus(agentId: agentId, status: .idle) }
        let tree = try #require(try await harness.messages.next { $0.message.changedWorkspaces != nil }.message.changedWorkspaces)
        #expect(tree.agent(withId: agentId)?.preview?.author == .assistant)
    }

    @Test func nestedWorktreesAndRepeatedTabsGetUniqueIds() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        var created: [AgentID] = []

        for workspaceId in ["w5", "w5", "w4"] {
            let ack = try await harness.request(.newAgentTab(workspaceId: workspaceId))
            guard case .ack(let agentId?) = ack.message else { throw UnexpectedMessage(envelope: ack) }
            created.append(agentId)
        }

        #expect(created == ["w5:p3", "w5:p4", "w4:p4"])
        #expect(!created.contains(DemoScript.movedAgentNewId))
        let tree = try #require(await harness.messages.all().last { $0.message.changedWorkspaces != nil }?.message.changedWorkspaces)
        let parent = try #require(tree.first { $0.id == "w1" })
        let worktree = try #require(parent.children.first { $0.id == "w5" })
        #expect(worktree.tabs.map(\.id) == ["w5:t1", "w5:t3", "w5:t4"])
        #expect(tree.allAgents.count == Set(tree.allAgents.map(\.id)).count)
    }

    @Test func unknownWorkspaceAnswersInvalidPayloadWithoutTouchingTheTree() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let error = try await harness.error(for: .newAgentTab(workspaceId: "w99"))

        #expect(error.code == .invalidPayload)
        #expect(error.message == "Workspace não encontrado")
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func waitingForTheNewAgentDoesNotHoldOtherMessages() async throws {
        let harness = try DemoHarness(DemoOptions(connectDelay: .milliseconds(5), newAgentTabDelay: .seconds(30)))
        try await harness.connect()
        let tabId = "c-new-tab"
        try await harness.connection.send(.newAgentTab(workspaceId: "w1"), id: tabId)

        let pong = try await harness.request(.ping)

        #expect(pong.message == .pong)
        #expect(await harness.messages.all().allSatisfy { $0.id != tabId && $0.message.changedWorkspaces == nil })
    }

    @Test func aReplyFromAClosedConnectionIsDroppedButTheTabStays() async throws {
        let harness = try DemoHarness(DemoOptions(connectDelay: .milliseconds(5), newAgentTabDelay: .milliseconds(200)))
        try await harness.connect()
        let tabId = "c-new-tab"
        try await harness.connection.send(.newAgentTab(workspaceId: "w2"), id: tabId)
        await harness.connection.stop()
        await harness.connection.start()
        let hasNewTab: @Sendable (ServerEnvelope) -> Bool = { envelope in
            envelope.message.workspaces?.first { $0.id == "w2" }?.tabs.last?.id == "w2:t3"
        }

        let reconnected = try await harness.messages.next { $0.message.workspaces != nil }
        if !hasNewTab(reconnected) {
            _ = try await harness.messages.next(where: hasNewTab)
        }
        let pong = try await harness.request(.ping)

        #expect(pong.message == .pong)
        #expect(await harness.messages.all().allSatisfy { $0.id != tabId })
    }
}
