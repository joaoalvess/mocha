import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

private func withCodexControlsHub(
    bridge: (any HerdrBridging)? = nil,
    _ body: (HubHarness, CodexServiceHarness, CodexService) async throws -> Void
) async throws {
    try await withCodexServer { codexHarness in
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-codex-controls-\(UUID().uuidString)", directoryHint: .isDirectory)
        let herdr = FakeHerdrBridge(tree: Sample.defaultTree, agents: Sample.herdrAgents(in: Sample.defaultTree))
        let transcripts = FakeTranscriptProvider()
        let clock = ManualClock(origin: Sample.start)
        let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
        let pairing = Pairing(clock: clock)
        let usage = FakeUsageProvider()
        let archive = FakeSessionArchive()
        let subagents = FakeSubagentProvider()
        let hub = SessionHub(
            herdr: bridge ?? herdr,
            transcripts: transcripts,
            devices: devices,
            pairing: pairing,
            usage: usage,
            archive: archive,
            subagents: subagents,
            clock: clock,
            configuration: SessionHubConfiguration(hostName: "Mac de Teste", daemonVersion: "9.9.9")
        )
        let codex = codexHarness.makeService()
        await hub.attachCodex(codex)
        await hub.start()
        await codex.start()
        let harness = HubHarness(
            herdr: herdr,
            transcripts: transcripts,
            usage: usage,
            archive: archive,
            subagents: subagents,
            clock: clock,
            devices: devices,
            pairing: pairing,
            hub: hub,
            directory: directory
        )
        do {
            try await body(harness, codexHarness, codex)
        } catch {
            await codex.stop()
            await hub.shutdown()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        await codex.stop()
        await hub.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum CodexControlSample {
    static func models() throws -> OrderedJSON {
        try CodexSample.result("model-list.response.json")
    }

    static func serve(_ server: FakeCodexAppServer) async throws {
        await server.reply(to: "model/list", with: .result(try models()))
        await server.reply(to: "thread/settings/update", with: .result(.object([])))
        await server.reply(to: "turn/settings/update", with: .result(.object([.init("status", .string("applied"))])))
        await server.reply(to: "thread/compact/start", with: .result(.object([])))
    }

    static func bind(
        _ harness: HubHarness,
        _ codexHarness: CodexServiceHarness,
        _ codex: CodexService,
        pane: AgentID = CodexSample.pane,
        cwd: String = CodexSample.cwd
    ) async throws {
        try await codexHarness.serveResume()
        await codexHarness.serveEmptyPages()
        try await codexHarness.bind(codex, pane: pane, cwd: cwd)
        _ = try await eventually {
            let agent = await harness.hub.agentSummary(pane)
            return agent?.controlAvailable == true && agent?.model == "gpt-6.1-sol" ? true : nil
        }
    }

    static func settingsUpdated(model: String, effort: String?, mode: String) -> OrderedJSON {
        .object([
            .init("threadId", .string(CodexSample.threadId)),
            .init("threadSettings", .object([
                .init("model", .string(model)),
                .init("effort", effort.map(OrderedJSON.string) ?? .null),
                .init("collaborationMode", .object([
                    .init("mode", .string(mode)),
                    .init("settings", .object([
                        .init("model", .string(model)),
                        .init("reasoning_effort", effort.map(OrderedJSON.string) ?? .null),
                    ])),
                ])),
            ])),
        ])
    }

    static func collaborationMode(_ mode: String, threadId: String, model: String, effort: String) -> OrderedJSON {
        .object([
            .init("threadId", .string(threadId)),
            .init("collaborationMode", .object([
                .init("mode", .string(mode)),
                .init("settings", .object([
                    .init("model", .string(model)),
                    .init("reasoning_effort", .string(effort)),
                    .init("developer_instructions", .null),
                ])),
            ])),
        ])
    }

    static func completedItem(_ id: String, threadId: String) -> OrderedJSON {
        .object([
            .init("item", .object([
                .init("type", .string("userMessage")),
                .init("id", .string(id)),
                .init("content", .array([.object([.init("type", .string("text")), .init("text", .string("oi"))])])),
            ])),
            .init("threadId", .string(threadId)),
            .init("turnId", .string("t-\(id)")),
            .init("completedAtMs", CodexSample.nowMs()),
        ])
    }

    static func appended(_ socket: TestClientSocket, id: String) -> ChatTarget? {
        socket.receivedMessages.lazy.compactMap { message -> ChatTarget? in
            guard case .chatAppend(let target, let items) = message, items.contains(where: { $0.id == id }) else { return nil }
            return target
        }.first
    }

    static func reply(_ socket: TestClientSocket, to message: ClientMessage, id: String) async throws -> ServerMessage {
        try socket.deliver(message, id: id)
        return try await envelope(withId: id, from: socket).message
    }

    static func envelope(withId id: String, from socket: TestClientSocket) async throws -> ServerEnvelope {
        while true {
            let envelope = try await socket.next()
            if envelope.id == id {
                return envelope
            }
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct CodexControlsTests {
    private let pane = CodexSample.pane

    @Test func listModelsAnswersTheVisibleModelsInTheAppServerOrder() async throws {
        try await withCodexControlsHub { harness, codexHarness, codex in
            var data = try #require(try CodexControlSample.models()["data"]?.arrayValue)
            data[2] = data[2].setting("hidden", to: .bool(true))
            let firstPage = OrderedJSON.object([.init("data", .array(Array(data[..<4]))), .init("nextCursor", .string("page-2"))])
            let secondPage = OrderedJSON.object([.init("data", .array(Array(data[4...]))), .init("nextCursor", .null)])
            await codexHarness.server.setHandler("model/list") { request in
                .result(request.string("cursor") == "page-2" ? secondPage : firstPage)
            }
            try await CodexControlSample.bind(harness, codexHarness, codex)
            let (socket, _) = try await harness.pairedClient()

            let reply = try await CodexControlSample.reply(socket, to: .listModels(agentId: pane), id: "m-1")
            guard case .models(let agentId, let options) = reply else { throw UnexpectedMessage(message: reply) }
            #expect(agentId == pane)
            #expect(options.map(\.id) == ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"])
            #expect(options.first == ModelOption(
                id: "gpt-6.1-sol",
                displayName: "GPT-6.1-Sol",
                isDefault: true,
                defaultEffort: "low",
                efforts: [
                    EffortOption(level: "low", description: "Fast responses with lighter reasoning"),
                    EffortOption(level: "medium", description: "Balances speed and reasoning depth for everyday tasks"),
                    EffortOption(level: "high", description: "Greater reasoning depth for complex problems"),
                    EffortOption(level: "xhigh", description: "Extra high reasoning depth for complex problems"),
                    EffortOption(level: "max", description: "Maximum reasoning depth for the hardest problems"),
                    EffortOption(level: "ultra", description: "Maximum reasoning with automatic task delegation"),
                ]
            ))
            #expect(options.first { $0.id == "gpt-6-luna" }?.efforts.map(\.level) == ["low", "medium", "high", "xhigh", "max"])
            #expect(await codexHarness.server.requests(method: "model/list").map { $0.string("cursor") } == [nil, "page-2"])
        }
    }

    @Test func listModelsIsOnlyForABoundCodex() async throws {
        try await withCodexControlsHub { harness, codexHarness, _ in
            try await codexHarness.connected()
            let (socket, _) = try await harness.pairedClient()

            #expect(try await CodexControlSample.reply(socket, to: .listModels(agentId: "w1:p1"), id: "m-1") == .error(code: .invalidPayload, message: "Lista de modelos só para Codex"))
            #expect(try await CodexControlSample.reply(socket, to: .listModels(agentId: "w9:p9"), id: "m-2").errorCode == .agentNotFound)
            #expect(try await CodexControlSample.reply(socket, to: .listModels(agentId: pane), id: "m-3") == .error(code: .codexUnavailable, message: "Controle indisponível nesta tab Codex."))
            #expect(await codexHarness.server.requests(method: "model/list").isEmpty)
        }
    }

    @Test func controlsOfAnUnboundCodexAnswerCodexUnavailable() async throws {
        try await withCodexControlsHub { harness, codexHarness, _ in
            try await CodexControlSample.serve(codexHarness.server)
            try await codexHarness.connected()
            let (socket, _) = try await harness.pairedClient()

            let messages: [ClientMessage] = [
                .setModel(agentId: pane, model: "gpt-6-luna"),
                .setEffort(agentId: pane, level: "high"),
                .setMode(agentId: pane, mode: .plan),
                .slash(agentId: pane, command: "/compact"),
                .slash(agentId: pane, command: "/clear"),
                .slash(agentId: pane, command: "/model"),
            ]
            for (index, message) in messages.enumerated() {
                #expect(try await CodexControlSample.reply(socket, to: message, id: "c-\(index)").errorCode == .codexUnavailable, "\(message.type)")
            }
            #expect(await codexHarness.server.requests(method: "thread/settings/update").isEmpty)
            #expect(await codexHarness.server.requests(method: "thread/compact/start").isEmpty)
            #expect(await codexHarness.server.requests(method: "turn/start").isEmpty)
        }
    }

    @Test func setModelUpdatesTheThreadAndTheTreeFollowsTheSettingsUpdated() async throws {
        try await withCodexControlsHub { harness, codexHarness, codex in
            try await CodexControlSample.serve(codexHarness.server)
            try await CodexControlSample.bind(harness, codexHarness, codex)
            let (socket, _) = try await harness.pairedClient()

            #expect(try await CodexControlSample.reply(socket, to: .setModel(agentId: pane, model: "gpt-6-luna"), id: "c-1") == .ack())
            let update = try #require(await codexHarness.server.requests(method: "thread/settings/update").first)
            #expect(update.params == .object([.init("threadId", .string(CodexSample.threadId)), .init("model", .string("gpt-6-luna"))]))
            #expect(await codexHarness.server.requests(method: "turn/settings/update").isEmpty)

            await codexHarness.server.notify("thread/settings/updated", params: CodexControlSample.settingsUpdated(model: "gpt-6-luna", effort: nil, mode: "default"))
            let tree = try await eventually { () -> AgentSummary? in
                harness.clock.advance(by: .milliseconds(150))
                return socket.receivedMessages.lazy.compactMap { message -> AgentSummary? in
                    guard case .treeChanged(let tree) = message, let agent = TreeComposer.agent(CodexSample.pane, in: tree) else { return nil }
                    return agent.model == "gpt-6-luna" ? agent : nil
                }.first
            }
            #expect(tree.permissionMode == "default")
        }
    }

    @Test func withAnActiveTurnModelAndEffortAlsoGoToTheTurn() async throws {
        try await withCodexControlsHub { harness, codexHarness, codex in
            try await CodexControlSample.serve(codexHarness.server)
            try await CodexControlSample.bind(harness, codexHarness, codex)
            await codexHarness.server.notify("turn/started", params: .object([
                .init("threadId", .string(CodexSample.threadId)),
                .init("turn", .object([.init("id", .string("turno-ativo")), .init("status", .string("inProgress"))])),
            ]))
            _ = try await eventually { await codex.activeTurnId(for: CodexSample.threadId) == "turno-ativo" ? true : nil }
            let (socket, _) = try await harness.pairedClient()

            #expect(try await CodexControlSample.reply(socket, to: .setEffort(agentId: pane, level: "high"), id: "c-1") == .ack())
            #expect(try await CodexControlSample.reply(socket, to: .setModel(agentId: pane, model: "gpt-6-astra"), id: "c-2") == .ack())

            let threadUpdates = await codexHarness.server.requests(method: "thread/settings/update").map(\.params)
            #expect(threadUpdates == [
                .object([.init("threadId", .string(CodexSample.threadId)), .init("effort", .string("high"))]),
                .object([.init("threadId", .string(CodexSample.threadId)), .init("model", .string("gpt-6-astra"))]),
            ])
            let turnUpdates = await codexHarness.server.requests(method: "turn/settings/update").map(\.params)
            #expect(turnUpdates == [
                .object([.init("threadId", .string(CodexSample.threadId)), .init("turnId", .string("turno-ativo")), .init("effort", .string("high"))]),
                .object([.init("threadId", .string(CodexSample.threadId)), .init("turnId", .string("turno-ativo")), .init("model", .string("gpt-6-astra"))]),
            ])
        }
    }

    @Test func valuesOutsideTheListAreInvalidPayload() async throws {
        try await withCodexControlsHub { harness, codexHarness, codex in
            try await CodexControlSample.serve(codexHarness.server)
            try await CodexControlSample.bind(harness, codexHarness, codex)
            await codexHarness.server.notify("thread/settings/updated", params: CodexControlSample.settingsUpdated(model: "gpt-6-luna", effort: "high", mode: "default"))
            _ = try await eventually { await harness.hub.codexPanes[CodexSample.pane]?.settings.model == "gpt-6-luna" ? true : nil }
            let (socket, _) = try await harness.pairedClient()

            #expect(try await CodexControlSample.reply(socket, to: .setModel(agentId: pane, model: "gpt-9"), id: "c-1") == .error(code: .invalidPayload, message: "Modelo indisponível no Codex"))
            #expect(try await CodexControlSample.reply(socket, to: .setModel(agentId: pane, model: "opus"), id: "c-2").errorCode == .invalidPayload)
            #expect(try await CodexControlSample.reply(socket, to: .setEffort(agentId: pane, level: "ultra"), id: "c-3") == .error(code: .invalidPayload, message: "Effort indisponível neste modelo"))
            #expect(try await CodexControlSample.reply(socket, to: .setMode(agentId: pane, mode: .acceptEdits), id: "c-4") == .error(code: .invalidPayload, message: "Modo indisponível no Codex"))
            #expect(try await CodexControlSample.reply(socket, to: .setMode(agentId: pane, mode: .auto), id: "c-5").errorCode == .invalidPayload)
            #expect(await codexHarness.server.requests(method: "thread/settings/update").isEmpty)

            #expect(try await CodexControlSample.reply(socket, to: .setEffort(agentId: pane, level: "max"), id: "c-6") == .ack())
            #expect(await codexHarness.server.requests(method: "thread/settings/update").map(\.params) == [
                .object([.init("threadId", .string(CodexSample.threadId)), .init("effort", .string("max"))]),
            ])
        }
    }

    @Test func setModeSendsTheCollaborationModeWithTheCurrentModelAndTheDefaultEffort() async throws {
        try await withCodexControlsHub { harness, codexHarness, codex in
            try await CodexControlSample.serve(codexHarness.server)
            try await CodexControlSample.bind(harness, codexHarness, codex)
            let (socket, _) = try await harness.pairedClient()

            #expect(try await CodexControlSample.reply(socket, to: .setMode(agentId: pane, mode: .plan), id: "c-1") == .ack())
            #expect(await codexHarness.server.requests(method: "thread/settings/update").map(\.params) == [
                CodexControlSample.collaborationMode("plan", threadId: CodexSample.threadId, model: "gpt-6.1-sol", effort: "low"),
            ])
            #expect(await codexHarness.server.requests(method: "turn/settings/update").isEmpty)
        }
    }

    @Test func compactStartsACompactionAndOtherCommandsAreInvalid() async throws {
        try await withCodexControlsHub { harness, codexHarness, codex in
            try await CodexControlSample.serve(codexHarness.server)
            try await CodexControlSample.bind(harness, codexHarness, codex)
            let (socket, _) = try await harness.pairedClient()

            #expect(try await CodexControlSample.reply(socket, to: .slash(agentId: pane, command: "/compact"), id: "c-1") == .ack())
            #expect(await codexHarness.server.requests(method: "thread/compact/start").map(\.params) == [
                .object([.init("threadId", .string(CodexSample.threadId))]),
            ])
            #expect(try await CodexControlSample.reply(socket, to: .slash(agentId: pane, command: "/model"), id: "c-2") == .error(code: .invalidPayload, message: "Comando indisponível no Codex"))
            #expect(try await CodexControlSample.reply(socket, to: .slash(agentId: pane, command: "/compact agora"), id: "c-3").errorCode == .invalidPayload)
            #expect(await codexHarness.server.requests(method: "turn/start").isEmpty)
            #expect(harness.herdr.promptCalls.isEmpty)
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct CodexClearTests {
    private static let pane = "w1A:p1"
    private static let cwd = "/Users/dev/projects/demo-app"
    private static let newThreadId = CodexSample.thirdThreadId

    private func withClearHub(_ body: (HubHarness, HerdrBridgeHarness, CodexServiceHarness, CodexService) async throws -> Void) async throws {
        let bridge = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .seconds(20)), start: false)
        await bridge.server.setAgent(paneId: Self.pane, agent: "codex")
        try await bridge.start()
        try await withCodexControlsHub(bridge: bridge.bridge) { harness, codexHarness, codex in
            try await CodexControlSample.serve(codexHarness.server)
            await codexHarness.server.setHandler("thread/read", CodexSample.readReply([
                CodexSample.threadId: CodexSample.thread(CodexSample.threadId, cwd: Self.cwd),
                Self.newThreadId: CodexSample.thread(Self.newThreadId, cwd: Self.cwd),
            ]))
            try await CodexControlSample.bind(harness, codexHarness, codex, pane: Self.pane, cwd: Self.cwd)
            try await body(harness, bridge, codexHarness, codex)
        }
        try await bridge.finish()
    }

    @Test func clearOpensANewPaneMovesTheChatAndClosesTheOldOne() async throws {
        try await withClearHub { harness, bridge, codexHarness, codex in
            let (socket, helloOk) = try await harness.pairedClient()
            let opened = try await CodexControlSample.reply(socket, to: .openChat(target: .agent(Self.pane)), id: "o-1")
            guard case .chatPage = opened else { throw UnexpectedMessage(message: opened) }
            #expect(try await CodexControlSample.reply(socket, to: .setForeground(agentId: Self.pane, isActive: true), id: "f-1") == .ack())

            try socket.deliver(.slash(agentId: Self.pane, command: "/clear"), id: "clear-1")
            let newPane = try await NewAgentTabSupport.startedPane(bridge.server)
            #expect(try await CodexControlSample.reply(socket, to: .slash(agentId: Self.pane, command: "/clear"), id: "clear-2") == .error(code: .internal, message: "O /clear anterior ainda está em andamento."))
            await codexHarness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(Self.newThreadId, cwd: Self.cwd)))
            await bridge.server.setAgent(paneId: newPane, agent: "codex")
            await bridge.server.setAgentStatus(paneId: newPane, status: "idle")

            let ack = try await CodexControlSample.envelope(withId: "clear-1", from: socket)
            #expect(ack.message == .ack(agentId: newPane))
            #expect(newPane != Self.pane)

            let split = try #require(await bridge.server.requests(method: "pane.split").first)
            #expect(split.paramKeys == ["target_pane_id", "direction", "cwd", "focus"])
            #expect(split.stringParam("target_pane_id") == Self.pane)
            #expect(split.stringParam("cwd") == Self.cwd)
            #expect(split.boolParam("focus") == false)
            let start = try #require(await bridge.server.requests(method: "agent.start").first)
            #expect(start.stringParam("kind") == "codex")
            #expect(start.stringParam("pane_id") == newPane)
            #expect(start.stringArrayParam("args") == [
                "--remote", "unix://\(codexHarness.server.socketPath)",
                "-c", "check_for_update_on_startup=false",
                "--cd", Self.cwd,
                "-m", "gpt-6.1-sol",
                "-c", "model_reasoning_effort=\"low\"",
            ])
            #expect(await codexHarness.server.requests(method: "thread/settings/update").map(\.params) == [
                CodexControlSample.collaborationMode("default", threadId: Self.newThreadId, model: "gpt-6.1-sol", effort: "low"),
            ])
            #expect(await bridge.server.requests(method: "pane.close").map { $0.stringParam("pane_id") } == [Self.pane])
            #expect(await codex.threadId(for: newPane) == Self.newThreadId)

            #expect(await harness.hub.foregroundDevices(for: newPane) == [helloOk.deviceId])
            #expect(await harness.hub.foregroundDevices(for: Self.pane).isEmpty)
            await codexHarness.server.notify("item/completed", params: CodexControlSample.completedItem("depois-do-clear", threadId: Self.newThreadId))
            let target = try await eventually { CodexControlSample.appended(socket, id: "depois-do-clear") }
            #expect(target == .agent(newPane))
        }
    }

    @Test func clearKeepsModelEffortAndPlanModeWhenTheThreadStartsLate() async throws {
        try await withClearHub { harness, bridge, codexHarness, _ in
            await codexHarness.server.notify("thread/settings/updated", params: CodexControlSample.settingsUpdated(model: "gpt-6-luna", effort: "high", mode: "plan"))
            _ = try await eventually { await harness.hub.codexPanes[Self.pane]?.settings.mode == "plan" ? true : nil }
            let (socket, _) = try await harness.pairedClient()

            try socket.deliver(.slash(agentId: Self.pane, command: "/clear"), id: "clear-1")
            let newPane = try await NewAgentTabSupport.startedPane(bridge.server)
            await bridge.server.setAgent(paneId: newPane, agent: "codex")
            await bridge.server.setAgentStatus(paneId: newPane, status: "idle")
            _ = try await eventually { await harness.hub.agentSummary(newPane)?.kind == "codex" ? true : nil }
            try await Task.sleep(for: .milliseconds(200))
            await codexHarness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(Self.newThreadId, cwd: Self.cwd)))

            let ack = try await CodexControlSample.envelope(withId: "clear-1", from: socket)
            #expect(ack.message == .ack(agentId: newPane))
            let start = try #require(await bridge.server.requests(method: "agent.start").first)
            #expect(start.stringArrayParam("args")?.suffix(4) == ["-m", "gpt-6-luna", "-c", "model_reasoning_effort=\"high\""])
            #expect(await codexHarness.server.requests(method: "thread/settings/update").map(\.params) == [
                CodexControlSample.collaborationMode("plan", threadId: Self.newThreadId, model: "gpt-6-luna", effort: "high"),
            ])
            #expect(await bridge.server.requests(method: "pane.close").map { $0.stringParam("pane_id") } == [Self.pane])
        }
    }

    @Test func aFailureBeforeClosingKeepsTheOldPaneAndItsChat() async throws {
        try await withClearHub { harness, bridge, codexHarness, _ in
            await bridge.server.override("agent.start", with: .error(code: "agent_not_ready", message: "pane is not at a shell prompt"))
            let (socket, _) = try await harness.pairedClient()
            let opened = try await CodexControlSample.reply(socket, to: .openChat(target: .agent(Self.pane)), id: "o-1")
            guard case .chatPage = opened else { throw UnexpectedMessage(message: opened) }

            let reply = try await CodexControlSample.reply(socket, to: .slash(agentId: Self.pane, command: "/clear"), id: "clear-1")
            #expect(reply == .error(code: .internal, message: "O agente ainda não está pronto para receber mensagens."))
            #expect(await bridge.server.requests(method: "pane.split").count == 1)
            #expect(await bridge.server.requests(method: "pane.close").isEmpty)
            #expect(await codexHarness.server.requests(method: "thread/settings/update").isEmpty)
            #expect(await bridge.bridge.agent(Self.pane)?.kind == "codex")

            await codexHarness.server.notify("item/completed", params: CodexControlSample.completedItem("ainda-no-antigo", threadId: CodexSample.threadId))
            let target = try await eventually { CodexControlSample.appended(socket, id: "ainda-no-antigo") }
            #expect(target == .agent(Self.pane))
        }
    }
}
