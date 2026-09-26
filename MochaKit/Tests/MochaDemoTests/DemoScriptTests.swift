import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoScriptTests {
    let dataset: DemoDataset

    init() throws {
        dataset = try DemoDataset.bundled()
    }

    @Test func worktreeAppearsNestedUnderAnExistingWorkspace() async throws {
        let harness = try DemoHarness(.script)
        try await harness.connect()

        let changed = try await harness.messages.next { $0.message.changedWorkspaces != nil }

        let workspaces = try #require(changed.message.changedWorkspaces)
        #expect(workspaces.map(\.id) == dataset.workspaces.map(\.id))
        let parent = try #require(workspaces.first { $0.id == DemoScript.worktreeParentId })
        let worktree = try #require(parent.children.first)
        #expect(parent.children.count == 1)
        #expect(worktree.id == DemoScript.worktreeId)
        #expect(worktree.repoName == parent.repoName)
        #expect(worktree.branch != parent.branch)
        let agent = try #require(worktree.tabs.first?.agents.first)
        #expect(agent.id == DemoScript.worktreeAgentId)
        #expect(agent.kind == "claude")
        let page = try await harness.page(agent.id)
        #expect(page.meta.workspaceLabel == worktree.label)
        #expect(page.items.last?.at == agent.lastActivityAt)
    }

    @Test func scriptedTurnStreamsItemsUpdatesTheToolAndRenamesTheChat() async throws {
        let agentId = DemoScript.turnAgentId
        let original = try #require(dataset.chats.first { $0.agentId == agentId })
        let harness = try DemoHarness(.script)
        try await harness.connect()
        let opened = try await harness.page(agentId, limit: 200)
        #expect(opened.items == Array(original.items.suffix(200)))

        var appendEvents: [[ChatItem]] = []
        var updates: [ChatItem] = []
        var metas: [ChatMeta] = []
        var statuses: [AgentStatus] = []
        var treeStatuses: [AgentStatus] = []
        while statuses.last != .idle {
            let envelope = try await harness.messages.next()
            switch envelope.message {
            case .chatAppend(.agent(agentId), let items):
                appendEvents.append(items)
            case .chatUpdate(.agent(agentId), let items):
                updates += items
            case .chatMeta(.agent(agentId), let meta):
                metas.append(meta)
            case .agentStatus(agentId, let status, _):
                statuses.append(status)
            case .treeChanged(let workspaces):
                treeStatuses.append(try #require(workspaces.first { $0.id == "w1" }).agentStatus)
            default:
                break
            }
        }
        let finalTree = try #require(
            try await harness.messages.next { $0.message.changedWorkspaces != nil }.message.changedWorkspaces
        )

        #expect(statuses == [.working, .idle])
        #expect(appendEvents.count == 6)
        let appended = appendEvents.flatMap { $0 }
        #expect(appended.map(\.kind.type) == [
            "userPrompt", "thinking", "assistantText", "toolCall", "toolCall", "assistantText", "turnFooter",
        ])
        let running = try #require(appended[4].toolCall)
        #expect(running.status == .running)
        #expect(running.resultPreview == nil)
        #expect(updates.map(\.id) == [appended[4].id])
        let finished = try #require(updates.first?.toolCall)
        #expect(finished.toolUseId == running.toolUseId)
        #expect(finished.status == .succeeded)
        #expect(finished.resultPreview != nil)
        #expect(metas.map(\.title) == [DemoScript.renamedTitle])
        #expect(metas.first?.status == .working)
        #expect(treeStatuses.contains(.working))
        #expect(finalTree.first { $0.id == "w1" }?.agentStatus == .idle)
        #expect(finalTree.agent(withId: agentId)?.status == .idle)
        #expect(finalTree.agent(withId: agentId)?.title == DemoScript.renamedTitle)

        let reopened = try await harness.page(agentId, limit: appended.count)
        #expect(reopened.meta.title == DemoScript.renamedTitle)
        #expect(reopened.meta.status == .idle)
        #expect(reopened.items.map(\.id) == appended.map(\.id))
        #expect(reopened.items[4] == updates.first)
    }

    @Test func sessionSwitchChangesTheSessionIdAndTheChatStartsWithClear() async throws {
        let agentId = DemoScript.worktreeAgentId
        let harness = try DemoHarness(.script)
        try await harness.connect()
        let added = try await harness.messages.next { $0.message.changedWorkspaces?.agent(withId: agentId) != nil }
        let previousSession = try #require(added.message.changedWorkspaces?.agent(withId: agentId)?.sessionId)
        let before = try await harness.page(agentId)
        #expect(before.items.count > 1)

        let switched = try await harness.messages.next {
            guard let session = $0.message.changedWorkspaces?.agent(withId: agentId)?.sessionId else { return false }
            return session != previousSession
        }

        let agent = try #require(switched.message.changedWorkspaces?.agent(withId: agentId))
        #expect(agent.sessionId == DemoScript.clearedSessionId)
        let after = try await harness.page(agentId)
        #expect(after.items.map(\.kind) == [.slashCommand(name: "/clear", args: "", output: nil)])
        #expect(after.hasMore == false)
        #expect(after.items.last?.at == agent.lastActivityAt)
    }

    @Test func movedAgentKeepsItsSessionAndTheOldIdStillOpensTheChat() async throws {
        let oldId = DemoScript.movedAgentId
        let newId = DemoScript.movedAgentNewId
        let original = try #require(dataset.workspaces.agent(withId: oldId))
        let harness = try DemoHarness(.script)
        try await harness.connect()
        let before = try await harness.page(oldId)

        let moved = try await harness.messages.next { $0.message.changedWorkspaces?.agent(withId: newId) != nil }

        let workspaces = try #require(moved.message.changedWorkspaces)
        #expect(workspaces.agent(withId: oldId) == nil)
        let agent = try #require(workspaces.agent(withId: newId))
        #expect(agent.sessionId == original.sessionId)
        #expect(agent.title == original.title)
        let throughOldId = try await harness.page(oldId)
        #expect(throughOldId.target == .agent(newId))
        #expect(throughOldId.items == before.items)
        let throughNewId = try await harness.page(newId)
        #expect(throughNewId.items == before.items)
    }

    @Test func connectionDropsAndComesBackWithANewHandshake() async throws {
        let harness = try DemoHarness(.script)
        try await harness.connect()

        #expect(try await harness.states.next() == .waitingToRetry(.unreachable))
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-1")
        }
        #expect(try await harness.states.next() == .connecting)
        #expect(try await harness.states.next() == .connected)

        let helloOk = try await harness.messages.next { $0.id == "hello-2" }
        guard case .helloOk(let payload) = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        #expect(payload.deviceToken == nil)
        let tree = try await harness.messages.next()
        #expect(tree.id == "hello-2")
        guard case .tree(let workspaces) = tree.message else { throw UnexpectedMessage(envelope: tree) }
        #expect(workspaces.agent(withId: DemoScript.worktreeAgentId) != nil)
        #expect(workspaces.agent(withId: DemoScript.movedAgentNewId) != nil)
        let pong = try await harness.request(.ping)
        #expect(pong.message == .pong)
    }

    @Test func withoutTheScriptNothingHappensSpontaneously() async throws {
        var options = DemoOptions.script
        options.runsScript = false
        let harness = try DemoHarness(options)
        try await harness.connect()

        let scriptDuration = DemoScript.steps.map(\.delay).reduce(Duration.zero, +) * DemoOptions.scriptScale
        try await Task.sleep(for: scriptDuration + .milliseconds(300))

        #expect(await harness.messages.unread().isEmpty)
        #expect(await harness.states.unread().isEmpty)
    }
}
