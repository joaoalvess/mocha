import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubNewAgentTabTests {
    private func envelope(withId id: String, from socket: TestClientSocket) async throws -> ServerEnvelope {
        while true {
            let envelope = try await socket.next()
            if envelope.id == id {
                return envelope
            }
        }
    }

    @Test func newAgentTabOverTheBridgeAnswersTheNewPaneAndKeepsServingTheConnection() async throws {
        let bridge = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .seconds(20)))
        await bridge.server.override("agent.wait", with: .noReply)
        try await withHub(bridge: bridge.bridge) { harness in
            let (socket, _) = try await harness.pairedClient()
            try socket.deliver(.newAgentTab(workspaceId: "w1A"), id: "tab-1")
            let paneId = try await NewAgentTabSupport.startedPane(bridge.server)

            try socket.deliver(.ping, id: "ping-1")
            let pong = try await envelope(withId: "ping-1", from: socket)
            #expect(pong.message == .pong)
            #expect(!socket.receivedMessages.contains { if case .ack = $0 { true } else { false } })

            await NewAgentTabSupport.agentIsDetected(bridge.server, paneId: paneId, status: "idle")
            await bridge.server.emit(try NewAgentTabSupport.statusLine(paneId: paneId, status: "idle"))
            let ack = try await envelope(withId: "tab-1", from: socket)
            #expect(ack.message == .ack(agentId: paneId))

            let chat = try await socket.reply(to: .openChat(target: .agent(paneId)), id: "chat-1")
            guard case .chatPage(let page) = chat else { throw UnexpectedMessage(message: chat) }
            #expect(page.target == .agent(paneId))
            #expect(page.items.isEmpty)
        }
        try await bridge.finish()
    }

    @Test func trustDialogOverTheBridgeStillAnswersAck() async throws {
        let bridge = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .seconds(20)))
        await bridge.server.override("agent.wait", with: .noReply)
        try await withHub(bridge: bridge.bridge) { harness in
            let (socket, _) = try await harness.pairedClient()
            try socket.deliver(.newAgentTab(workspaceId: "w1A"), id: "tab-1")
            let paneId = try await NewAgentTabSupport.startedPane(bridge.server)
            await NewAgentTabSupport.agentIsDetected(bridge.server, paneId: paneId, status: "blocked")
            await bridge.server.emit(try NewAgentTabSupport.trustDialogBlockedLine(paneId: paneId))
            let ack = try await envelope(withId: "tab-1", from: socket)
            #expect(ack.message == .ack(agentId: paneId))
            #expect(await bridge.requestCount("agent.send_keys") == 0)
        }
        try await bridge.finish()
    }

    @Test func startFailureOverTheBridgeFollowsTheErrorTable() async throws {
        let bridge = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(50)))
        await bridge.server.override("agent.start", with: .error(code: "agent_not_ready", message: "pane is not at a shell prompt"))
        try await withHub(bridge: bridge.bridge) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .newAgentTab(workspaceId: "w1A"), id: "tab-1")
            #expect(reply.errorCode == .internal)
            #expect(reply.errorMessage?.contains("agente") == true)
            #expect(try await socket.reply(to: .newAgentTab(workspaceId: "w99"), id: "tab-2") == .error(code: .invalidPayload, message: "Workspace não encontrado"))
        }
        try await bridge.finish()
    }
}
