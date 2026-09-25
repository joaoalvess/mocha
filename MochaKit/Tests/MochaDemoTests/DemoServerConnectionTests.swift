import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

private let hello = ClientMessage.hello(HelloPayload(deviceToken: "token", deviceName: "iPhone de teste", appVersion: "0.1.0"))

private func nextEnvelope(_ iterator: inout AsyncStream<ServerEnvelope>.Iterator) async throws -> ServerEnvelope {
    try #require(await iterator.next())
}

private func openPage(
    _ connection: DemoServerConnection,
    _ iterator: inout AsyncStream<ServerEnvelope>.Iterator,
    agentId: AgentID,
    before: String? = nil,
    limit: Int? = nil
) async throws -> ChatPage {
    let id = try await connection.send(.openChat(agentId: agentId, before: before, limit: limit))
    let envelope = try await nextEnvelope(&iterator)
    #expect(envelope.id == id)
    guard case .chatPage(let page) = envelope.message else {
        throw UnexpectedMessage(envelope: envelope)
    }
    return page
}

private struct UnexpectedMessage: Error, CustomStringConvertible {
    let envelope: ServerEnvelope
    var description: String { "Mensagem inesperada: \(envelope)" }
}

private func errorCode(of envelope: ServerEnvelope) -> ProtocolErrorCode? {
    guard case .error(let code, _) = envelope.message else { return nil }
    return code
}

@Suite(.timeLimit(.minutes(1)))
struct DemoServerConnectionTests {
    let dataset: DemoDataset

    init() throws {
        dataset = try DemoDataset.bundled()
    }

    @Test func helloRepliesWithHelloOkThenTreeWithTheSameId() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        let id = try await connection.send(hello)

        let first = try await nextEnvelope(&iterator)
        #expect(first.id == id)
        guard case .helloOk(let helloOk) = first.message else {
            throw UnexpectedMessage(envelope: first)
        }
        #expect(helloOk.deviceToken == nil)
        #expect(helloOk.preferences == DevicePreferences(turnDoneAlerts: true))

        let second = try await nextEnvelope(&iterator)
        #expect(second.id == id)
        guard case .tree(let workspaces) = second.message else {
            throw UnexpectedMessage(envelope: second)
        }
        #expect(workspaces == dataset.workspaces)
        #expect(workspaces.count == 4)
        #expect(workspaces.filter { !$0.children.isEmpty }.count == 1)
    }

    @Test func helloWithPairingCodeReturnsADeviceToken() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        _ = try await connection.send(.hello(HelloPayload(pairingCode: "codigo", deviceName: "iPhone", appVersion: "0.1.0")))

        let envelope = try await nextEnvelope(&iterator)
        guard case .helloOk(let helloOk) = envelope.message else {
            throw UnexpectedMessage(envelope: envelope)
        }
        #expect(helloOk.deviceToken != nil)
    }

    @Test func requestIdsAreUniquePerConnection() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var ids: Set<String> = []
        for _ in 0..<5 {
            ids.insert(try await connection.send(.ping))
        }
        #expect(ids.count == 5)
    }

    @Test func openChatReturnsTheLastPageAndPaginatesBackwardsWithBefore() async throws {
        let chat = try #require(dataset.chats.first { $0.agentId == "w1:p1" })
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        let first = try await openPage(connection, &iterator, agentId: chat.agentId, limit: 60)
        #expect(first.agentId == chat.agentId)
        #expect(first.meta == chat.meta)
        #expect(first.items == Array(chat.items.suffix(60)))
        #expect(first.hasMore)
        let cursor = try #require(first.before)

        let second = try await openPage(connection, &iterator, agentId: chat.agentId, before: cursor, limit: 60)
        let expectedSecond = Array(chat.items.dropLast(60).suffix(60))
        #expect(second.items == expectedSecond)
        #expect(second.hasMore == (chat.items.count > 120))

        var collected = second.items + first.items
        var page = second
        while page.hasMore {
            let previousCursor: String = try #require(page.before)
            page = try await openPage(connection, &iterator, agentId: chat.agentId, before: previousCursor, limit: 60)
            collected = page.items + collected
        }
        #expect(page.before == nil)
        #expect(collected == chat.items)
    }

    @Test func openChatUsesTheDefaultLimitAndCapsLargeLimits() async throws {
        let chat = try #require(dataset.chats.first)
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        let defaultPage = try await openPage(connection, &iterator, agentId: chat.agentId)
        #expect(defaultPage.items.count == DemoServerConnection.defaultPageSize)

        let everything = try await openPage(connection, &iterator, agentId: chat.agentId, limit: 1_000)
        #expect(everything.items.count == min(chat.items.count, DemoServerConnection.maximumPageSize))
    }

    @Test func openChatRejectsUnknownAgentsAndInvalidCursors() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        let unknownId = try await connection.send(.openChat(agentId: "w99:p1"))
        let unknown = try await nextEnvelope(&iterator)
        #expect(unknown.id == unknownId)
        #expect(errorCode(of: unknown) == .agentNotFound)

        let cursorId = try await connection.send(.openChat(agentId: "w1:p1", before: "b:120394"))
        let invalidCursor = try await nextEnvelope(&iterator)
        #expect(invalidCursor.id == cursorId)
        #expect(errorCode(of: invalidCursor) == .invalidPayload)
    }

    @Test func sendPromptAcksEchoesThePromptAndRepliesAfterTheDelay() async throws {
        let connection = try DemoServerConnection(replyDelay: .milliseconds(20))
        var iterator = connection.messages.makeAsyncIterator()
        _ = try await openPage(connection, &iterator, agentId: "w1:p1")

        let id = try await connection.send(.sendPrompt(agentId: "w1:p1", text: "oi, modo demo"))

        let ack = try await nextEnvelope(&iterator)
        #expect(ack.id == id)
        #expect(ack.message == .ack())

        let echo = try await nextEnvelope(&iterator)
        #expect(echo.id == nil)
        guard case .chatAppend("w1:p1", let echoed) = echo.message else {
            throw UnexpectedMessage(envelope: echo)
        }
        #expect(echoed.map(\.kind) == [.userPrompt(text: "oi, modo demo", imageCount: 0)])

        let working = try await nextEnvelope(&iterator)
        #expect(working.message == .agentStatus(agentId: "w1:p1", status: .working))

        let reply = try await nextEnvelope(&iterator)
        guard case .chatAppend("w1:p1", let replied) = reply.message else {
            throw UnexpectedMessage(envelope: reply)
        }
        #expect(replied.first?.kind == .assistantText(markdown: DemoServerConnection.replyMarkdown))
        guard case .turnFooter = replied.last?.kind else {
            throw UnexpectedMessage(envelope: reply)
        }

        let idle = try await nextEnvelope(&iterator)
        #expect(idle.message == .agentStatus(agentId: "w1:p1", status: .idle))

        let reopened = try await openPage(connection, &iterator, agentId: "w1:p1", limit: 3)
        #expect(reopened.items.map(\.id) == (echoed + replied).map(\.id))
        #expect(reopened.meta.status == .idle)
    }

    @Test func sendPromptToABlockedAgentFails() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        let id = try await connection.send(.sendPrompt(agentId: "w2:p1", text: "continua"))

        let envelope = try await nextEnvelope(&iterator)
        #expect(envelope.id == id)
        #expect(errorCode(of: envelope) == .agentBlocked)
    }

    @Test func interruptAcksAndCancelsThePendingReply() async throws {
        let connection = try DemoServerConnection(replyDelay: .seconds(30))
        var iterator = connection.messages.makeAsyncIterator()
        _ = try await openPage(connection, &iterator, agentId: "w1:p1")
        _ = try await connection.send(.sendPrompt(agentId: "w1:p1", text: "faz algo demorado"))
        for _ in 0..<3 {
            _ = try await nextEnvelope(&iterator)
        }

        let id = try await connection.send(.interrupt(agentId: "w1:p1"))

        let ack = try await nextEnvelope(&iterator)
        #expect(ack.id == id)
        #expect(ack.message == .ack())
        let idle = try await nextEnvelope(&iterator)
        #expect(idle.message == .agentStatus(agentId: "w1:p1", status: .idle))

        let pingId = try await connection.send(.ping)
        let pong = try await nextEnvelope(&iterator)
        #expect(pong.id == pingId)
        #expect(pong.message == .pong)
    }

    @Test func remainingMessagesGetTheirDirectResponse() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()
        let cases: [(ClientMessage, ServerMessage)] = [
            (.closeChat(agentId: "w1:p1"), .ack()),
            (.setForeground(agentId: "w1:p1", isActive: true), .ack()),
            (.setForeground(agentId: nil, isActive: false), .ack()),
            (.ping, .pong),
            (.slash(agentId: "w1:p1", command: "/compact"), .ack()),
            (.setPreferences(DevicePreferences(turnDoneAlerts: false)), .ack()),
            (.registerLiveActivity(LiveActivityRegistration(pushToStartToken: "abc", env: .sandbox)), .ack()),
        ]
        for (request, expected) in cases {
            let id = try await connection.send(request)
            let envelope = try await nextEnvelope(&iterator)
            #expect(envelope.id == id)
            #expect(envelope.message == expected, "Resposta a \(request.type)")
        }

        let errors: [(ClientMessage, ProtocolErrorCode)] = [
            (.respond(requestId: "r1", response: .allow), .requestNotFound),
            (.newAgentTab(workspaceId: "w1"), .internal),
            (.unknown(type: "teleport"), .unknownType),
            (.slash(agentId: "w99:p1", command: "/clear"), .agentNotFound),
        ]
        for (request, code) in errors {
            let id = try await connection.send(request)
            let envelope = try await nextEnvelope(&iterator)
            #expect(envelope.id == id)
            #expect(errorCode(of: envelope) == code, "Erro para \(request.type)")
        }

        _ = try await connection.send(hello)
        let helloOk = try await nextEnvelope(&iterator)
        guard case .helloOk(let payload) = helloOk.message else {
            throw UnexpectedMessage(envelope: helloOk)
        }
        #expect(payload.preferences == DevicePreferences(turnDoneAlerts: false))
    }

    @Test func unpairAcksAndClosesTheConnection() async throws {
        let connection = try DemoServerConnection(replyDelay: .zero)
        var iterator = connection.messages.makeAsyncIterator()

        let id = try await connection.send(.unpair)

        let ack = try await nextEnvelope(&iterator)
        #expect(ack.id == id)
        #expect(ack.message == .ack())
        #expect(await iterator.next() == nil)
        await #expect(throws: DemoError.connectionClosed) {
            try await connection.send(.ping)
        }
    }
}
