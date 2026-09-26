import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

private let unknownSessionId = "0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64"

@Suite(.timeLimit(.minutes(1)))
struct DemoScopeBTests {
    @Test func handshakeSendsHelloOkTreeArchivedAndUsageInThisOrder() async throws {
        let harness = try DemoHarness()
        await harness.connection.start()

        var envelopes: [ServerEnvelope] = []
        for _ in 0..<4 {
            envelopes.append(try await harness.messages.next())
        }

        #expect(envelopes.map(\.message.type) == ["helloOk", "tree", "archived", "usage"])
        #expect(envelopes.map(\.id) == ["hello-1", "hello-1", nil, nil])
        guard case .helloOk(let helloOk) = envelopes[0].message else { throw UnexpectedMessage(envelope: envelopes[0]) }
        #expect(helloOk.host.hostName == "MacBook")
        #expect(helloOk.host.herdrConnected)
        #expect(envelopes[2].message == .archived(sessions: harness.dataset.archived))
        #expect(harness.dataset.archived.count == 2)
        #expect(envelopes[3].message == .usage(harness.dataset.usage))
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func archiveMarksTheCurrentSessionUntilTheNextTurn() async throws {
        let harness = try DemoHarness()
        let sessionId = try #require(harness.dataset.workspaces.agent(withId: "w1:p1")?.sessionId)
        try await harness.connect()
        let before = Date()

        let ack = try await harness.request(.archive(sessionId: sessionId))

        #expect(ack.message == .ack())
        let archived = try #require(try await harness.messages.next().message.changedWorkspaces)
        let archivedAt = try #require(archived.agent(withId: "w1:p1")?.archivedAt)
        #expect(archivedAt >= before)
        #expect(archived.allAgents.filter { $0.archivedAt != nil }.map(\.id) == ["w1:p1"])

        _ = try await harness.request(.sendPrompt(agentId: "w1:p1", text: "mais uma coisa"))
        let working = try #require(
            try await harness.messages.next { $0.message.changedWorkspaces?.agent(withId: "w1:p1")?.status == .working }
                .message.changedWorkspaces?.agent(withId: "w1:p1")
        )
        #expect(working.archivedAt == nil)
        #expect(working.preview == MessagePreview(author: .user, text: "mais uma coisa"))
        #expect(try #require(working.turnStartedAt) > archivedAt)
    }

    @Test func archiveOfASessionThatIsNotCurrentFails() async throws {
        let harness = try DemoHarness()
        let archivedId = try #require(harness.dataset.archived.first?.id)
        try await harness.connect()

        for sessionId in [archivedId, unknownSessionId] {
            let error = try await harness.error(for: .archive(sessionId: sessionId))
            #expect(error.code == .sessionNotFound)
        }
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func archivedSessionOpensAsAFixedPagedChat() async throws {
        let harness = try DemoHarness()
        let chat = try #require(harness.dataset.sessionChats.first { $0.session.reason == .cleared })
        let sessionId = chat.session.id
        try await harness.connect()

        let whole = try await harness.page(.session(sessionId))
        #expect(whole.target == .session(sessionId))
        #expect(whole.items == chat.items)
        #expect(whole.meta.title == chat.session.title)
        #expect(whole.meta.workspaceLabel == chat.session.workspaceLabel)
        #expect(whole.meta.branch == chat.session.branch)
        #expect(!whole.hasMore)
        #expect(whole.before == nil)

        let last = try await harness.page(.session(sessionId), limit: chat.items.count - 1)
        #expect(last.items == Array(chat.items.dropFirst()))
        #expect(last.hasMore)
        let cursor: String = try #require(last.before)
        let first = try await harness.page(.session(sessionId), before: cursor)
        #expect(first.items == Array(chat.items.prefix(1)))
        #expect(!first.hasMore)

        let ack = try await harness.request(.closeChat(target: .session(sessionId)))
        #expect(ack.message == .ack())
    }

    @Test func sessionChatsFollowTheServerRules() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let cases: [(ClientMessage, ProtocolErrorCode)] = [
            (.openChat(target: .session("sessao-1")), .invalidPayload),
            (.closeChat(target: .session("sessao-1")), .invalidPayload),
            (.openChat(target: .session(unknownSessionId)), .sessionNotFound),
            (.closeChat(target: .session(unknownSessionId)), .sessionNotFound),
            (.openChat(target: .session(harness.dataset.archived[0].id), before: "demo:99"), .invalidPayload),
        ]
        for (request, code) in cases {
            let error = try await harness.error(for: request)
            #expect(error.code == code, "\(request)")
        }
    }

    @Test func currentSessionOfALiveAgentOpensByIdAndFollowsTheAppends() async throws {
        let harness = try DemoHarness()
        let chat = try #require(harness.dataset.chats.first { $0.agentId == "w1:p1" })
        let sessionId = try #require(harness.dataset.workspaces.agent(withId: "w1:p1")?.sessionId)
        try await harness.connect()

        let page = try await harness.page(.session(sessionId))
        #expect(page.target == .session(sessionId))
        #expect(page.items == Array(chat.items.suffix(60)))
        #expect(page.meta == chat.meta)

        _ = try await harness.request(.sendPrompt(agentId: "w1:p1", text: "oi pela sessão"))
        let echo = try await harness.messages.next { $0.message.type == "chatAppend" }
        guard case .chatAppend(let target, let items) = echo.message else { throw UnexpectedMessage(envelope: echo) }
        #expect(target == .session(sessionId))
        #expect(items.map(\.kind) == [.userPrompt(text: "oi pela sessão", imageCount: 0)])
    }

    @Test func emptyDemoHasWorkspacesWithoutClaude() async throws {
        let harness = try DemoHarness(DemoOptions(isEmpty: true, connectDelay: .milliseconds(5)))
        await harness.connection.start()

        let tree = try await harness.messages.next { $0.message.type == "tree" }
        guard case .tree(let workspaces) = tree.message else { throw UnexpectedMessage(envelope: tree) }
        #expect(workspaces.count == 4)
        #expect(!workspaces.allAgents.contains { $0.kind == "claude" })
        #expect(try await harness.messages.next().message == .archived(sessions: []))
        let usage = try await harness.messages.next()
        guard case .usage(let snapshot) = usage.message else { throw UnexpectedMessage(envelope: usage) }
        #expect(snapshot.windows.map(\.usedPercent) == [3, 64])
        let error = try await harness.error(for: .openChat(target: .agent("w1:p1")))
        #expect(error.code == .agentNotFound)
    }

    @Test func scriptFinishesAWorkingAgentWithTurnEndedAt() async throws {
        let agentId = DemoScript.movedAgentNewId
        let harness = try DemoHarness(.script)
        let original = try #require(harness.dataset.workspaces.agent(withId: DemoScript.finishingAgentId))
        #expect(original.status == .working)
        try await harness.connect()

        _ = try await harness.messages.next { $0.message == .agentStatus(agentId: agentId, status: .idle) }
        let tree = try #require(try await harness.messages.next { $0.message.changedWorkspaces != nil }.message.changedWorkspaces)

        let agent = try #require(tree.agent(withId: agentId))
        #expect(agent.status == .idle)
        let turnEndedAt = try #require(agent.turnEndedAt)
        #expect(turnEndedAt > Date().addingTimeInterval(-60))
        #expect(turnEndedAt > (try #require(agent.turnStartedAt)))
        #expect(agent.lastActivityAt == turnEndedAt)
        #expect(Date().timeIntervalSince(try #require(agent.sessionStartedAt)) < 6 * 3_600)
        #expect(agent.preview?.author == .assistant)
    }

    @Test func scriptSessionSwitchArchivesThePreviousSessionAsCleared() async throws {
        let harness = try DemoHarness(.script)
        try await harness.connect()

        let event = try await harness.messages.next { $0.message.archivedSessions != nil }

        #expect(event.id == nil)
        let sessions = try #require(event.message.archivedSessions)
        #expect(sessions.count == 3)
        let session = try #require(sessions.first)
        #expect(session.id == DemoScript.worktreeSessionId)
        #expect(session.reason == .cleared)
        #expect(session.agentId == DemoScript.worktreeAgentId)
        #expect(session.preview == MessagePreview(
            author: .assistant,
            text: "Worktree feat/feed-rss limpo. Vou começar por src/feed/rss.ts."
        ))
        #expect(Array(sessions.dropFirst()) == harness.dataset.archived)
        let page = try await harness.page(.session(DemoScript.worktreeSessionId))
        #expect(page.items.first?.id == "script-worktree-prompt")
        #expect(page.items.count == 4)
    }

    @Test func scriptTakesTheHerdrDownAndBringsItBack() async throws {
        let harness = try DemoHarness(.script)
        try await harness.connect()

        let down = try await harness.messages.next { $0.message.herdrConnected != nil }
        let up = try await harness.messages.next { $0.message.herdrConnected != nil }

        #expect(down.id == nil)
        #expect(down.message == .herdrStatus(connected: false))
        #expect(up.message == .herdrStatus(connected: true))
        let helloOk = try await harness.messages.next { $0.id == "hello-2" }
        guard case .helloOk(let payload) = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        #expect(payload.host.herdrConnected)
    }
}
