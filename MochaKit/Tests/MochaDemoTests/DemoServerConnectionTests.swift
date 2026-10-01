import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoServerConnectionTests {
    @Test func openChatReturnsTheLastPageAndPaginatesBackwardsWithBefore() async throws {
        let harness = try DemoHarness()
        let chat = try #require(harness.dataset.chats.first { $0.agentId == "w1:p1" })
        try await harness.connect()

        let first = try await harness.page(chat.agentId, limit: 60)
        #expect(first.target == .agent(chat.agentId))
        #expect(first.meta == chat.meta)
        #expect(first.items == Array(chat.items.suffix(60)))
        #expect(first.hasMore)

        var collected = first.items
        var page = first
        while page.hasMore {
            let cursor: String = try #require(page.before)
            page = try await harness.page(chat.agentId, before: cursor, limit: 60)
            collected = page.items + collected
        }
        #expect(page.before == nil)
        #expect(collected == chat.items)
    }

    @Test(arguments: [
        (nil, 60),
        (0, 1),
        (-5, 1),
        (1, 1),
        (200, 200),
        (500, 200),
    ] as [(Int?, Int)])
    func openChatClampsTheLimit(limit: Int?, expectedCount: Int) async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let page = try await harness.page(DemoLongChat.agentId, limit: limit)

        #expect(page.items.count == expectedCount)
        #expect(page.hasMore)
    }

    @Test(arguments: ["b:120394", "demo:", "demo:abc", "demo:-1", "demo:5000"])
    func openChatRejectsInvalidCursors(_ cursor: String) async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let error = try await harness.error(for: .openChat(target: .agent("w1:p1"), before: cursor))

        #expect(error.code == .invalidPayload)
    }

    @Test func codexWithoutControlOpensForReadingButRejectsPrompt() async throws {
        let harness = try DemoHarness()
        let codex = try #require(harness.dataset.workspaces.agent(withId: "w4:p3"))
        #expect(codex.kind != "claude")
        try await harness.connect()

        let page = try await harness.page(codex.id)
        #expect(page.items.last?.kind == .assistantText(markdown: "O build foi concluído."))
        let error = try await harness.error(for: .sendPrompt(agentId: codex.id, text: "oi"))
        #expect(error.code == .codexUnavailable)
    }

    @Test func openChatRejectsUnknownAgents() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let error = try await harness.error(for: .openChat(target: .agent("w99:p1")))

        #expect(error.code == .agentNotFound)
    }

    @Test func longChatPaginatesToTheBeginningWithoutRepeatingOrSkippingItems() async throws {
        let harness = try DemoHarness()
        let chat = try #require(harness.dataset.chats.first { $0.agentId == DemoLongChat.agentId })
        #expect(chat.items.count == 2_000)
        try await harness.connect()

        var page = try await harness.page(chat.agentId)
        var collected = page.items
        var pageCount = 1
        while page.hasMore {
            let cursor: String = try #require(page.before)
            page = try await harness.page(chat.agentId, before: cursor)
            collected = page.items + collected
            pageCount += 1
        }

        #expect(pageCount == 34)
        #expect(page.before == nil)
        #expect(collected.count == 2_000)
        #expect(Set(collected.map(\.id)).count == 2_000)
        #expect(collected == chat.items)
    }

    @Test func promptEchoArrivesAfterTheDelayAndTheTreeFollowsTheStatus() async throws {
        let harness = try DemoHarness(
            DemoOptions(connectDelay: .milliseconds(5), echoDelay: .milliseconds(400), replyDelay: .milliseconds(50))
        )
        try await harness.connect()
        _ = try await harness.page("w1:p1")

        let ack = try await harness.request(.sendPrompt(agentId: "w1:p1", text: "oi, modo demo"))

        #expect(ack.message == .ack())
        try await Task.sleep(for: .milliseconds(150))
        #expect(await harness.messages.unread().isEmpty)

        let echo = try await harness.messages.next()
        #expect(echo.id == nil)
        guard case .chatAppend(.agent("w1:p1"), let echoed) = echo.message else { throw UnexpectedMessage(envelope: echo) }
        #expect(echoed.map(\.kind) == [.userPrompt(text: "oi, modo demo", imageCount: 0)])
        #expect(try await harness.messages.next().message == .agentStatus(agentId: "w1:p1", status: .working))
        let working = try #require(try await harness.messages.next().message.changedWorkspaces)
        #expect(working.agent(withId: "w1:p1")?.status == .working)
        #expect(working.agent(withId: "w1:p1")?.lastActivityAt == echoed.last?.at)
        #expect(working.first { $0.id == "w1" }?.agentStatus == .working)
        #expect(working.first { $0.id == "w1" }?.children.first?.agentStatus == .working)
        #expect(working.first { $0.id == "w2" }?.agentStatus == .blocked)

        let reply = try await harness.messages.next()
        guard case .chatAppend(.agent("w1:p1"), let replied) = reply.message else { throw UnexpectedMessage(envelope: reply) }
        #expect(replied.first?.kind == .assistantText(markdown: DemoServerConnection.replyMarkdown))
        guard case .turnFooter = replied.last?.kind else { throw UnexpectedMessage(envelope: reply) }
        #expect(try await harness.messages.next().message == .agentStatus(agentId: "w1:p1", status: .idle))
        let idle = try #require(try await harness.messages.next().message.changedWorkspaces)
        #expect(idle.agent(withId: "w1:p1")?.status == .idle)
        #expect(idle.first { $0.id == "w1" }?.agentStatus == .idle)

        let reopened = try await harness.page("w1:p1", limit: 3)
        #expect(reopened.items.map(\.id) == (echoed + replied).map(\.id))
        #expect(reopened.meta.status == .idle)
    }

    @Test func sendPromptToABlockedAgentFails() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let error = try await harness.error(for: .sendPrompt(agentId: "w2:p1", text: "continua"))

        #expect(error.code == .agentBlocked)
    }

    @Test func interruptAcksCancelsThePendingReplyAndUpdatesTheTree() async throws {
        let harness = try DemoHarness(
            DemoOptions(connectDelay: .milliseconds(5), echoDelay: .milliseconds(5), replyDelay: .seconds(30))
        )
        try await harness.connect()
        _ = try await harness.page("w1:p1")
        _ = try await harness.request(.sendPrompt(agentId: "w1:p1", text: "faz algo demorado"))
        _ = try await harness.messages.next { $0.message == .agentStatus(agentId: "w1:p1", status: .working) }
        _ = try await harness.messages.next { $0.message.changedWorkspaces != nil }

        let ack = try await harness.request(.interrupt(agentId: "w1:p1"))

        #expect(ack.message == .ack())
        #expect(try await harness.messages.next().message == .agentStatus(agentId: "w1:p1", status: .idle))
        let tree = try #require(try await harness.messages.next().message.changedWorkspaces)
        #expect(tree.agent(withId: "w1:p1")?.status == .idle)
        #expect(tree.first { $0.id == "w1" }?.agentStatus == .idle)
        let pong = try await harness.request(.ping)
        #expect(pong.message == .pong)
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func remainingMessagesGetTheirDirectResponse() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let cases: [(ClientMessage, ServerMessage)] = [
            (.closeChat(target: .agent("w1:p1")), .ack()),
            (.setForeground(agentId: "w1:p1", isActive: true), .ack()),
            (.setForeground(agentId: nil, isActive: false), .ack()),
            (.ping, .pong),
            (.slash(agentId: "w1:p1", command: "/compact"), .ack()),
            (.setPreferences(DevicePreferences(turnDoneAlerts: false)), .ack()),
            (.registerLiveActivity(LiveActivityRegistration(pushToStartToken: "abc", env: .sandbox)), .ack()),
        ]
        for (request, expected) in cases {
            let envelope = try await harness.request(request)
            #expect(envelope.message == expected, "Resposta a \(request.type)")
        }

        let errors: [(ClientMessage, ProtocolErrorCode)] = [
            (.respond(requestId: "r1", response: .allow), .requestNotFound),
            (.newAgentTab(workspaceId: "w99"), .invalidPayload),
            (.unknown(type: "teleport"), .unknownType),
            (.slash(agentId: "w99:p1", command: "/clear"), .agentNotFound),
            (.slash(agentId: "w4:p3", command: "/clear"), .codexUnavailable),
            (.sendPrompt(agentId: "w99:p1", text: "oi"), .agentNotFound),
            (.interrupt(agentId: "w99:p1"), .agentNotFound),
        ]
        for (request, code) in errors {
            let error = try await harness.error(for: request)
            #expect(error.code == code, "Erro para \(request.type)")
        }
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func preferencesAreReturnedInTheNextHelloOk() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.request(.setPreferences(DevicePreferences(turnDoneAlerts: false)))

        await harness.connection.stop()
        await harness.connection.start()

        let helloOk = try await harness.messages.next()
        guard case .helloOk(let payload) = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        #expect(payload.preferences == DevicePreferences(turnDoneAlerts: false))
    }

    @Test func chatEventsStopAfterAReconnectionUntilTheChatIsOpenedAgain() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page("w1:p1")
        await harness.connection.stop()
        await harness.connection.start()
        _ = try await harness.messages.next { $0.message.workspaces != nil }

        _ = try await harness.request(.sendPrompt(agentId: "w1:p1", text: "oi"))
        _ = try await harness.messages.next { $0.message == .agentStatus(agentId: "w1:p1", status: .idle) }
        _ = try await harness.messages.next { $0.message.changedWorkspaces != nil }

        #expect(await harness.messages.all().allSatisfy { $0.message.type != "chatAppend" })
    }
}
