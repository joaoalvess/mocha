import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoSlashTests {
    private let clearChip = ChatItemKind.slashCommand(name: "/clear", args: "", output: nil)

    @Test func clearStartsANewEmptySessionAndArchivesTheOldOne() async throws {
        let agentId: AgentID = "w1:p1"
        let harness = try DemoHarness()
        let original = try #require(harness.dataset.workspaces.agent(withId: agentId))
        let previousSessionId = try #require(original.sessionId)
        try await harness.connect()
        let before = try await harness.page(agentId, limit: 200)

        let ack = try await harness.request(.slash(agentId: agentId, command: "/clear"))

        #expect(ack.message == .ack())
        let tree = try #require(try await harness.messages.next().message.changedWorkspaces)
        let agent = try #require(tree.agent(withId: agentId))
        let newSessionId = try #require(agent.sessionId)
        #expect(newSessionId != previousSessionId)
        #expect(UUID(uuidString: newSessionId) != nil)
        #expect(agent.preview == nil)
        #expect(agent.activity == nil)
        #expect(agent.archivedAt == nil)
        #expect(agent.turnStartedAt == nil)
        #expect(agent.contextLeftPercent == DemoServerConnection.freshContextLeftPercent)

        let archived = try #require(try await harness.messages.next().message.archivedSessions)
        let session = try #require(archived.first)
        #expect(session.id == previousSessionId)
        #expect(session.agentId == agentId)
        #expect(session.reason == .cleared)
        #expect(session.title == original.title)
        #expect(session.preview == original.preview)
        #expect(session.workspaceLabel == original.workspaceLabel)
        #expect(archived.count == harness.dataset.archived.count + 1)
        #expect(await harness.messages.unread().isEmpty)

        let after = try await harness.page(agentId)
        #expect(after.target == .agent(agentId))
        #expect(after.items.map(\.kind) == [clearChip])
        #expect(after.hasMore == false)
        #expect(after.items.last?.at == agent.lastActivityAt)

        let old = try await harness.page(.session(previousSessionId), limit: 200)
        #expect(old.target == .session(previousSessionId))
        #expect(old.items == before.items)
    }

    @Test func clearOfAWorkingAgentStopsTheTurnFirst() async throws {
        let agentId: AgentID = "w5:p1"
        let harness = try DemoHarness()
        let previousSessionId = try #require(harness.dataset.workspaces.agent(withId: agentId)?.sessionId)
        try await harness.connect()
        _ = try await harness.page(agentId)

        let ack = try await harness.request(.slash(agentId: agentId, command: "/clear"))

        #expect(ack.message == .ack())
        #expect(try await harness.messages.next().message == .agentStatus(agentId: agentId, status: .idle))
        let switched = try await harness.messages.next {
            guard let sessionId = $0.message.changedWorkspaces?.agent(withId: agentId)?.sessionId else { return false }
            return sessionId != previousSessionId
        }
        #expect(switched.message.changedWorkspaces?.agent(withId: agentId)?.status == .idle)
        let archived = try #require(try await harness.messages.next().message.archivedSessions)
        #expect(archived.first?.id == previousSessionId)

        let after = try await harness.page(agentId)
        #expect(after.meta.status == .idle)
        #expect(after.items.map(\.kind) == [clearChip])
    }

    @Test func clearAfterAPromptDiscardsThePendingReply() async throws {
        let agentId: AgentID = "w1:p1"
        let harness = try DemoHarness(
            DemoOptions(connectDelay: .milliseconds(5), echoDelay: .milliseconds(5), replyDelay: .milliseconds(200))
        )
        try await harness.connect()
        _ = try await harness.page(agentId)
        _ = try await harness.request(.sendPrompt(agentId: agentId, text: "faz algo demorado"))
        _ = try await harness.messages.next { $0.message == .agentStatus(agentId: agentId, status: .working) }

        _ = try await harness.request(.slash(agentId: agentId, command: "/clear"))
        _ = try await harness.messages.next { $0.message.archivedSessions != nil }
        try await Task.sleep(for: .milliseconds(400))

        #expect(await harness.messages.unread().allSatisfy { $0.message.type != "chatAppend" })
        let after = try await harness.page(agentId)
        #expect(after.items.map(\.kind) == [clearChip])
    }

    @Test func clearIsRefusedWhileTheAgentIsBlocked() async throws {
        let agentId: AgentID = "w2:p1"
        let harness = try DemoHarness()
        try await harness.connect()
        let before = try await harness.page(agentId)

        let error = try await harness.error(for: .slash(agentId: agentId, command: "/clear"))

        #expect(error.code == .agentBlocked)
        #expect(await harness.messages.unread().isEmpty)
        let after = try await harness.page(agentId)
        #expect(after.items == before.items)
    }

    @Test func otherCommandsOnlyAcknowledge() async throws {
        let agentId: AgentID = "w1:p1"
        let harness = try DemoHarness()
        try await harness.connect()
        let before = try await harness.page(agentId)

        for command in ["/compact", "/context", "/cost", "/clearance"] {
            let ack = try await harness.request(.slash(agentId: agentId, command: command))
            #expect(ack.message == .ack(), "Resposta a \(command)")
        }

        #expect(await harness.messages.unread().isEmpty)
        let after = try await harness.page(agentId)
        #expect(after.items == before.items)
    }

    @Test func clearCommandMatchesOnlyTheFirstWord() {
        #expect(DemoServerConnection.isClear("/clear"))
        #expect(DemoServerConnection.isClear("  /clear  "))
        #expect(!DemoServerConnection.isClear("/clearance"))
        #expect(!DemoServerConnection.isClear("/compact"))
        #expect(!DemoServerConnection.isClear(""))
    }
}
