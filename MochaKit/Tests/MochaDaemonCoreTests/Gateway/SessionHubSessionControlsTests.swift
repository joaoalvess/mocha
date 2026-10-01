import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubSessionControlsTests {
    static let sonnet = TranscriptMeta(title: "sessão", model: "claude-sonnet-5-5", permissionMode: "default")
    static let haiku = TranscriptMeta(title: "sessão", model: "claude-haiku-4-5-20251001", permissionMode: "default")

    static func agent(in message: ServerMessage) -> AgentSummary? {
        guard case .treeChanged(let tree) = message else { return nil }
        return TreeComposer.agent("w1:p1", in: tree)
    }

    static func withControlsHub(meta: TranscriptMeta = sonnet, modelSwitches: ModelSwitchGate? = nil, _ body: (HubHarness) async throws -> Void) async throws {
        try await withHub(modelSwitches: modelSwitches, configure: { transcripts in
            await transcripts.setMeta(meta, forSession: Sample.sessionA)
        }, body)
    }

    static func hook(_ file: String, as name: HookEventName, agentId: AgentID = "w1:p1") throws -> ReceivedHook {
        var body = try #require(try JSONSerialization.jsonObject(with: Fixtures.data("hooks/\(file)")) as? [String: Any])
        body["session_id"] = Sample.sessionA
        let event = try HookEvent.decode(name, from: JSONSerialization.data(withJSONObject: body))
        return ReceivedHook(agentId: agentId, receivedAt: Sample.start, event: event)
    }

    @Test func setModeAcksAfterTheSwitchAndSendsTheTreeAndChatMetaWithTheReadMode() async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()
            guard case .chatPage(let page) = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-0") else {
                Issue.record("expected chatPage")
                return
            }
            #expect(page.meta.permissionMode == "default")
            harness.herdr.setModeResult("acceptEdits")

            let envelope = try await socket.request(.setMode(agentId: "w1:p1", mode: .plan), id: "c-1")
            #expect(envelope.id == "c-1")
            #expect(envelope.message == .ack())
            #expect(Self.agent(in: try await socket.nextMessage())?.permissionMode == "acceptEdits")
            guard case .chatMeta(.agent("w1:p1"), let updated) = try await socket.nextMessage() else {
                Issue.record("expected chatMeta")
                return
            }
            #expect(updated.permissionMode == "acceptEdits")
            #expect(harness.herdr.controlCalls == [.mode("w1:p1", .plan)])
        }
    }

    @Test func setEffortShowsTheEffortInTheTreeAndChatMeta() async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-0")

            #expect(try await socket.reply(to: .setEffort(agentId: "w1:p1", level: "xhigh")) == .ack())
            #expect(Self.agent(in: try await socket.nextMessage())?.effort == "xhigh")
            guard case .chatMeta(_, let meta) = try await socket.nextMessage() else {
                Issue.record("expected chatMeta")
                return
            }
            #expect(meta.effort == "xhigh")
            #expect(meta.model == "claude-sonnet-5-5")
        }
    }

    @Test func setEffortOnHaikuIsInvalidPayloadWithoutTouchingTheTerminal() async throws {
        try await Self.withControlsHub(meta: Self.haiku) { harness in
            let (socket, _) = try await harness.pairedClient()

            #expect(try await socket.reply(to: .setEffort(agentId: "w1:p1", level: "low")).errorCode == .invalidPayload)
            #expect(harness.herdr.controlCalls.isEmpty)
        }
    }

    @Test func setModelOpensTheGateOnlyWhileSwitchingAndRereadsTheMode() async throws {
        let gate = ModelSwitchGate()
        try await Self.withControlsHub(modelSwitches: gate) { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setCurrentMode("plan", of: "w1:p1")

            #expect(try await socket.reply(to: .setModel(agentId: "w1:p1", model: "haiku")) == .ack())
            #expect(Self.agent(in: try await socket.nextMessage())?.permissionMode == "plan")
            #expect(harness.herdr.controlCalls == [.model("w1:p1", .haiku)])
            #expect(await gate.approves("w1:p1", at: Date()) == false)

            harness.herdr.setControlError(.screenBusy)
            #expect(try await socket.reply(to: .setModel(agentId: "w1:p1", model: "opus"), id: "c-2").errorCode == .screenBusy)
            #expect(await gate.approves("w1:p1", at: Date()) == false)
        }
    }

    @Test(arguments: [
        (HerdrBridgeError.modeUnavailable, ProtocolErrorCode.modeUnavailable, "Modo indisponível neste modelo"),
        (.screenBusy, .screenBusy, "Feche o seletor aberto no terminal"),
        (.agentBlocked, .agentBlocked, "O agente está esperando uma resposta no terminal."),
        (.herdr(code: "selector", message: "O seletor de modelo não abriu no terminal."), .internal, "O seletor de modelo não abriu no terminal."),
    ])
    func bridgeErrorsMapToTheProtocol(error: HerdrBridgeError, code: ProtocolErrorCode, message: String) async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setControlError(error)

            let reply = try await socket.reply(to: .setMode(agentId: "w1:p1", mode: .auto))
            #expect(reply == .error(code: code, message: message))
        }
    }

    @Test func controlsFollowTheSendPromptTargetRules() async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()

            #expect(try await socket.reply(to: .setMode(agentId: "w1:p2", mode: .plan), id: "c-1").errorCode == .invalidPayload)
            #expect(try await socket.reply(to: .setModel(agentId: "w9:p9", model: "opus"), id: "c-2").errorCode == .agentNotFound)
            harness.herdr.setAvailable(false)
            _ = try await socket.nextMessage { $0 == .herdrStatus(connected: false) }
            #expect(try await socket.reply(to: .setEffort(agentId: "w1:p1", level: "low"), id: "c-3").errorCode == .herdrUnavailable)
            #expect(harness.herdr.controlCalls.isEmpty)
        }
    }

    @Test func invalidValuesAreInvalidPayload() async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()

            socket.deliverRaw(#"{"v":2,"id":"c-1","type":"setMode","payload":{"agentId":"w1:p1","mode":"bypassPermissions"}}"#)
            #expect(try await socket.nextMessage().errorCode == .invalidPayload)
            socket.deliverRaw(#"{"v":2,"id":"c-2","type":"setModel","payload":{"agentId":"w1:p1","model":"gpt"}}"#)
            #expect(try await socket.nextMessage().errorCode == .invalidPayload)
            #expect(harness.herdr.controlCalls.isEmpty)
        }
    }

    @Test func stopAndPromptHooksSetEffortAndPermissionModeUntilTheTranscriptMoves() async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()

            await harness.hub.hookReceived(try Self.hook("Stop.effort.json", as: .stop))
            var prompt = try Self.hook("UserPromptSubmit.json", as: .userPromptSubmit)
            if case .userPromptSubmit(var submit) = prompt.event {
                submit.context.permissionMode = "plan"
                prompt.event = .userPromptSubmit(submit)
            }
            await harness.hub.hookReceived(prompt)
            try await harness.advanceTreeDebounce()
            let agent = try #require(Self.agent(in: try await socket.nextMessage { Self.agent(in: $0) != nil }))
            #expect(agent.effort == "medium")
            #expect(agent.permissionMode == "plan")

            var moved = Self.sonnet
            moved.permissionMode = "auto"
            await harness.transcripts.setMeta(moved, forSession: Sample.sessionA)
            await harness.hub.hookReceived(try Self.hook("PostModelSwitch.auto.json", as: .postModelSwitch))
            harness.herdr.emit(.treeChanged(Sample.defaultTree))
            try await harness.advanceTreeDebounce()
            let later = try #require(Self.agent(in: try await socket.nextMessage { Self.agent(in: $0) != nil }))
            #expect(later.permissionMode == "auto")
            #expect(later.effort == "medium")
            #expect(later.model == "claude-sonnet-5-5")
        }
    }

    @Test func postModelSwitchUpdatesTheModelAndIgnoresAutomaticSwitches() async throws {
        try await Self.withControlsHub(meta: Self.haiku) { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-0")

            await harness.hub.hookReceived(try Self.hook("PostModelSwitch.auto.json", as: .postModelSwitch))
            #expect(socket.pendingCount == 0)

            await harness.hub.hookReceived(try Self.hook("PostModelSwitch.picker.json", as: .postModelSwitch))
            guard case .chatMeta(_, let meta) = try await socket.nextMessage() else {
                Issue.record("expected chatMeta")
                return
            }
            #expect(meta.model == "claude-sonnet-5-5")
            try await harness.advanceTreeDebounce()
            #expect(Self.agent(in: try await socket.nextMessage { Self.agent(in: $0) != nil })?.model == "claude-sonnet-5-5")
        }
    }

    @Test func hooksOfAnotherSessionDoNotLeakIntoTheAgent() async throws {
        try await Self.withControlsHub { harness in
            let (socket, _) = try await harness.pairedClient()
            let hook = try HookEvent.decode(.stop, from: Fixtures.data("hooks/Stop.effort.json"))
            await harness.hub.hookReceived(ReceivedHook(agentId: "w1:p1", receivedAt: Sample.start, event: hook))
            try await harness.advanceTreeDebounce()
            _ = try await eventually { await harness.hub.agentControls.isEmpty ? true : nil }
            let agent = try #require(await harness.hub.agentSummary("w1:p1"))
            #expect(agent.effort == nil)
            #expect(agent.permissionMode == "default")
            #expect(socket.pendingCount == 0)
        }
    }
}
