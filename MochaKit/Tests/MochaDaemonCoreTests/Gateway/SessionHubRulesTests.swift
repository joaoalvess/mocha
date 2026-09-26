import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubRulesTests {
    @Test func openChatDefaultsTheLimitAndClampsIt() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-1")
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1"), limit: 500), id: "c-2")
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1"), limit: 0), id: "c-3")
            let limits = await harness.transcripts.openRequests.map(\.limit)
            #expect(limits == [60, 200, 1])
        }
    }

    @Test func openChatAnswersTheLastPageAndFollowsTheSession() async throws {
        let items = [Sample.item("i1", text: "um"), Sample.item("i2", text: "dois")]
        let meta = TranscriptMeta(title: "Título da sessão", model: "claude-opus-5-5", branch: "main", permissionMode: "auto")
        try await withHub(configure: { transcripts in
            await transcripts.setPage(Sample.page(items, meta: meta, before: "\(Sample.sessionA):10"), forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-7")
            let expectedMeta = ChatMeta(title: "Título da sessão", workspaceLabel: "Core", model: "claude-opus-5-5", branch: "main", status: .idle, permissionMode: "auto")
            #expect(reply == .chatPage(ChatPage(target: .agent("w1:p1"), meta: expectedMeta, items: items, before: "\(Sample.sessionA):10", hasMore: true)))
            let appended = Sample.item("i3", text: "três")
            await harness.transcripts.emit(.append([appended]), toSession: Sample.sessionA)
            #expect(try await socket.nextMessage() == .chatAppend(target: .agent("w1:p1"), items: [appended]))
            let updated = Sample.item("i2", text: "dois, editado")
            await harness.transcripts.emit(.update([updated]), toSession: Sample.sessionA)
            #expect(try await socket.nextMessage() == .chatUpdate(target: .agent("w1:p1"), items: [updated]))
            #expect(try await eventually { harness.herdr.openChatsCalls.last == ["w1:p1"] ? true : nil })
        }
    }

    @Test func openChatWithACursorAnswersTheOlderPage() async throws {
        let older = [Sample.item("i0", text: "zero")]
        try await withHub(configure: { transcripts in
            await transcripts.setPage(Sample.page(older), forSession: Sample.sessionA, before: "\(Sample.sessionA):10")
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1"), before: "\(Sample.sessionA):10"))
            guard case .chatPage(let page) = reply else { throw UnexpectedMessage(message: reply) }
            #expect(page.items == older)
            #expect(page.hasMore == false)
            #expect(await harness.transcripts.pageRequests == [
                FakeTranscriptProvider.PageRequest(session: TranscriptSession(sessionId: Sample.sessionA), before: "\(Sample.sessionA):10", limit: 60),
            ])
        }
    }

    @Test func invalidCursorIsInvalidPayload() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .openChat(target: .agent("w1:p1"), before: "\(Sample.sessionB):0")).errorCode == .invalidPayload)
        }
    }

    @Test func agentsThatAreNotClaudeHaveNoChat() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p2")))
            #expect(reply == .error(code: .invalidPayload, message: "Chat disponível só para Claude Code"))
        }
    }

    @Test func agentWithoutSessionAnswersAnEmptyPageAndFollowsTheFileLater() async throws {
        let tree = [Sample.workspace("w1", tabs: [TabNode(id: "w1:t1", title: "Claude", agents: [Sample.agent("w1:p1")])])]
        let first = Sample.item("i1", text: "primeira")
        try await withHub(tree: tree, configure: { transcripts in
            await transcripts.setPage(Sample.page([first]), forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            let meta = ChatMeta(title: "Claude Code", workspaceLabel: "Core", status: .idle)
            #expect(reply == .chatPage(ChatPage(target: .agent("w1:p1"), meta: meta, items: [], before: nil, hasMore: false)))
            #expect(await harness.transcripts.openRequests.isEmpty)

            harness.herdr.setAgent(HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: Sample.sessionA))
            harness.herdr.emit(.sessionChanged("w1:p1", sessionId: Sample.sessionA))
            #expect(try await socket.nextMessage() == .chatAppend(target: .agent("w1:p1"), items: [first]))
            let second = Sample.item("i2", text: "segunda")
            await harness.transcripts.emit(.append([second]), toSession: Sample.sessionA)
            #expect(try await socket.nextMessage() == .chatAppend(target: .agent("w1:p1"), items: [second]))
        }
    }

    @Test func unknownAgentIsAgentNotFound() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .openChat(target: .agent("w9:p9"))).errorCode == .agentNotFound)
            #expect(try await socket.reply(to: .sendPrompt(agentId: "w9:p9", text: "oi")).errorCode == .agentNotFound)
        }
    }

    @Test func oldIdIsResolvedAndTheChatAnswersWithTheCurrentId() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.movePane(from: "w1:p1", to: "w3:p1")
            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            guard case .chatPage(let page) = reply else { throw UnexpectedMessage(message: reply) }
            #expect(page.target == .agent("w3:p1"))
            #expect(harness.herdr.resolveCalls.contains("w1:p1"))
        }
    }

    @Test func promptAndInterruptReachTheHerdr() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .sendPrompt(agentId: "w1:p1", text: "roda os testes")) == .ack())
            #expect(try await socket.reply(to: .interrupt(agentId: "w1:p1")) == .ack())
            #expect(harness.herdr.promptCalls == [FakeHerdrPromptCall(agentId: "w1:p1", text: "roda os testes")])
            #expect(harness.herdr.interruptCalls == ["w1:p1"])
        }
    }

    @Test func commandsRejectAgentsThatAreNotClaude() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            let prompt = try await socket.reply(to: .sendPrompt(agentId: "w1:p2", text: "oi"))
            #expect(prompt == .error(code: .invalidPayload, message: "Chat disponível só para Claude Code"))
            #expect(try await socket.reply(to: .interrupt(agentId: "w1:p2")).errorCode == .invalidPayload)
            #expect(harness.herdr.promptCalls.isEmpty)
        }
    }

    @Test(arguments: [
        (HerdrBridgeError.agentBlocked, ProtocolErrorCode.agentBlocked),
        (.herdr(code: "agent_blocked", message: "blocked"), .agentBlocked),
        (.agentNotFound, .agentNotFound),
        (.herdr(code: "agent_not_found", message: "no agent"), .agentNotFound),
        (.herdr(code: "pane_not_found", message: "no pane"), .agentNotFound),
        (.unavailable, .herdrUnavailable),
        (.herdr(code: "agent_not_ready", message: "not ready"), .internal),
        (.herdr(code: "agent_prompt_stalled", message: "stalled"), .internal),
        (.herdr(code: "timeout", message: "timeout"), .internal),
        (.herdr(code: "invalid_key", message: "bad key"), .internal),
    ])
    func herdrErrorsMapToProtocolErrors(error: HerdrBridgeError, expected: ProtocolErrorCode) async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setPromptError(error)
            harness.herdr.setInterruptError(error)
            let prompt = try await socket.reply(to: .sendPrompt(agentId: "w1:p1", text: "oi"))
            let interrupt = try await socket.reply(to: .interrupt(agentId: "w1:p1"))
            #expect(prompt.errorCode == expected)
            #expect(interrupt.errorCode == expected)
            if expected == .internal {
                let message = try #require(prompt.errorMessage)
                #expect(!message.isEmpty)
                #expect(message.contains("Herdr") || message.contains("agente"))
            }
        }
    }

    @Test func unknownAndLaterPhaseTypesAnswerUnknownType() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            socket.deliverRaw(#"{"v":1,"id":"c-1","type":"teleport","payload":{}}"#)
            let unknown = try await socket.next()
            #expect(unknown.id == "c-1")
            #expect(unknown.message.errorCode == .unknownType)
            #expect(try await socket.reply(to: .respond(requestId: "r-1", response: .allow), id: "c-3").errorCode == .unknownType)
            #expect(try await socket.reply(to: .ping, id: "c-4") == .pong)
        }
    }

    @Test func malformedPayloadIsInvalidPayloadWithTheRequestId() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            socket.deliverRaw(#"{"v":1,"id":"c-5","type":"openChat","payload":{"agentId":"w1:p1","sessionId":"\#(Sample.sessionA)"}}"#)
            let reply = try await socket.next()
            #expect(reply.id == "c-5")
            #expect(reply.message.errorCode == .invalidPayload)
        }
    }

    @Test func setForegroundIsAcknowledged() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .setForeground(agentId: "w1:p1", isActive: true)) == .ack())
            #expect(try await socket.reply(to: .setForeground(agentId: nil, isActive: false)) == .ack())
        }
    }

    @Test func protocolMismatchAfterHelloCloses1002() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            socket.deliverRaw(#"{"v":7,"id":"c-9","type":"ping","payload":{}}"#)
            let reply = try await socket.next()
            #expect(reply.id == "c-9")
            #expect(reply.message.errorCode == .protocolMismatch)
            #expect(try await socket.waitForClose() == .protocolError)
        }
    }

    @Test func unpairAcknowledgesClosesWith1000AndForgetsTheDevice() async throws {
        try await withHub { harness in
            let (socket, helloOk) = try await harness.pairedClient()
            let token = try #require(helloOk.deviceToken)
            let other = try await harness.client(token: token)
            #expect(try await socket.reply(to: .unpair, id: "c-3") == .ack())
            #expect(try await socket.waitForClose() == .normalClosure)
            #expect(try await harness.devices.devices().isEmpty)
            #expect(try await other.nextMessage().errorCode == .unauthorized)
            #expect(try await other.waitForClose() == .policyViolation)
            let again = harness.connect()
            #expect(try await again.reply(to: .hello(HelloPayload(deviceToken: token, deviceName: "iPhone", appVersion: "1.0"))).errorCode == .unauthorized)
        }
    }
}
