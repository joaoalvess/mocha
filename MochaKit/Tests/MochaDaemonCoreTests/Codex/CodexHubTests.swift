import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

private final class LiveActivityInputs: Sendable {
    private let inputs = Mutex<[LiveActivityInput]>([])

    var all: [LiveActivityInput] {
        inputs.withLock { $0 }
    }

    func record(_ input: LiveActivityInput) {
        inputs.withLock { $0.append(input) }
    }
}

private func withCodexHub(_ body: (HubHarness, CodexServiceHarness, CodexService) async throws -> Void) async throws {
    try await withCodexServer { codexHarness in
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-codex-hub-\(UUID().uuidString)", directoryHint: .isDirectory)
        let herdr = FakeHerdrBridge(tree: Sample.defaultTree, agents: Sample.herdrAgents(in: Sample.defaultTree))
        let transcripts = FakeTranscriptProvider()
        let clock = ManualClock(origin: Sample.start)
        let store = PendingStore(herdr: herdr, transcripts: transcripts, clock: ManualClock(origin: Sample.start))
        await store.start()
        let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
        let pairing = Pairing(clock: clock)
        let usage = FakeUsageProvider()
        let archive = FakeSessionArchive()
        let subagents = FakeSubagentProvider()
        let hub = SessionHub(
            herdr: herdr,
            transcripts: transcripts,
            devices: devices,
            pairing: pairing,
            usage: usage,
            archive: archive,
            subagents: subagents,
            pending: store,
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
            await store.shutdown()
            await hub.shutdown()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        await codex.stop()
        await store.shutdown()
        await hub.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct CodexHubTests {
    private static let deviceToken = "token-do-iphone"

    private static func post(_ requestId: RequestID, _ response: PendingResponse, port: UInt16) async throws -> TestHttpResponse {
        try await sendRequest(
            "POST",
            port: port,
            target: Gateway.respondPath,
            headers: ["Content-Type": "application/json", "Authorization": "Bearer \(deviceToken)"],
            body: PendingHttpTests.respondBody(requestId, response)
        )
    }

    private static func fresh(_ name: String) throws -> OrderedJSON {
        CodexSample.setting(try CodexSample.params(name), ["startedAtMs": CodexSample.nowMs()])
    }

    private static func reply(_ socket: TestClientSocket, to message: ClientMessage, id: String) async throws -> ServerMessage {
        try socket.deliver(message, id: id)
        while true {
            let envelope = try await socket.next()
            if envelope.id == id {
                return envelope.message
            }
        }
    }

    private static func pending(in hub: SessionHub, count: Int = 1) async throws -> PendingRequest {
        try await eventually {
            let requests = await hub.pendingRequests
            return requests.count == count ? requests.first : nil
        }
    }

    @Test func postRespondAnswersACodexRequestOnTheAppServerSocket() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            _ = try await harness.devices.register(name: "iPhone", token: Self.deviceToken, at: Sample.start)
            try await codexHarness.bind(codex)
            await codexHarness.server.serverRequest("item/commandExecution/requestApproval", id: 2, params: try Self.fresh("command-execution-request-approval.json"))
            let request = try await Self.pending(in: harness.hub)
            #expect(request.agentId == CodexSample.pane)

            try await withRunningServer(Gateway(herdr: harness.herdr, hub: harness.hub).makeRouter()) { port in
                #expect(try await Self.post(request.id, .answers(["x": ["y"]]), port: port).status == 400)
                let accepted = try await Self.post(request.id, .allow, port: port)
                #expect(accepted.status == 200)
                #expect(String(decoding: accepted.body, as: UTF8.self) == "{}")
                #expect(try await Self.post(request.id, .allow, port: port).status == 404)
            }
            let answer = try await eventually { await codexHarness.server.clientResponses.first }
            #expect(answer.id == .number("2"))
            #expect(answer.result == .object([.init("decision", .string("accept"))]))
            _ = try await eventually { await harness.hub.pendingRequests.isEmpty ? true : nil }
        }
    }

    @Test func postRespondAnswersACodexQuestionByItsText() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            _ = try await harness.devices.register(name: "iPhone", token: Self.deviceToken, at: Sample.start)
            try await codexHarness.bind(codex)
            await codexHarness.server.serverRequest("item/tool/requestUserInput", id: 4, params: try CodexSample.params("tool-request-user-input.json"))
            let request = try await Self.pending(in: harness.hub)

            try await withRunningServer(Gateway(herdr: harness.herdr, hub: harness.hub).makeRouter()) { port in
                let accepted = try await Self.post(request.id, .answers(["Qual banco de dados usar?": ["Postgres"]]), port: port)
                #expect(accepted.status == 200)
            }
            let answer = try await eventually { await codexHarness.server.clientResponses.first }
            #expect(answer.result == .object([
                .init("answers", .object([.init("banco", .object([.init("answers", .array([.string("Postgres")]))]))])),
            ]))
        }
    }

    @Test func theCodexOutcomeReachesTheLiveActivitySnapshot() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            let inputs = LiveActivityInputs()
            let updates = harness.hub.liveActivityUpdates
            Task {
                for await input in updates {
                    inputs.record(input)
                }
            }
            let (socket, _) = try await harness.pairedClient()
            try await codexHarness.bind(codex)
            await codexHarness.server.serverRequest("item/commandExecution/requestApproval", id: 2, params: try Self.fresh("command-execution-request-approval.json"))
            let request = try await Self.pending(in: harness.hub)

            #expect(try await Self.reply(socket, to: .respond(requestId: request.id, response: .allow), id: "r-1") == .ack())
            let final = try await eventually {
                harness.clock.advance(by: .milliseconds(150))
                return inputs.all.last { $0.pending.isEmpty && $0.decisions[CodexSample.pane] != nil }
            }
            #expect(final.decisions[CodexSample.pane] == PendingDecision(requestId: request.id, outcome: .allowed))
            var tracker = AgentActivityTracker()
            let snapshot = tracker.snapshots(of: final, at: Sample.start, titleLimit: LiveActivityConfiguration().titleLimit)[CodexSample.pane]
            #expect(snapshot?.agent.outcome == "allowed")
        }
    }

    @Test func paneMovedMovesTheCodexBinding() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            try await codexHarness.bind(codex)
            _ = try await eventually { await harness.hub.codexPanes[CodexSample.pane] != nil ? true : nil }

            harness.herdr.movePane(from: CodexSample.pane, to: "w2:p9")
            _ = try await eventually { await codex.threadId(for: "w2:p9") == CodexSample.threadId ? true : nil }
            #expect(await harness.hub.codexPanes["w2:p9"]?.threadId == CodexSample.threadId)
            #expect(await harness.hub.codexPanes[CodexSample.pane] == nil)
            #expect(CodexSample.savedBindings(in: codexHarness.directory)["w2:p9"]?.threadId == CodexSample.threadId)
        }
    }

    @Test func anUnverifiedCodexTabAnswersCodexUnavailable() async throws {
        try await withCodexHub { harness, codexHarness, _ in
            try await codexHarness.connected()
            let (socket, _) = try await harness.pairedClient()
            let reply = try await Self.reply(socket, to: .sendPrompt(agentId: CodexSample.pane, text: "oi"), id: "c-1")
            #expect(reply == .error(code: .codexUnavailable, message: "Controle indisponível nesta tab Codex."))
        }
    }

    private static func appendedIds(_ socket: TestClientSocket) -> [String] {
        socket.receivedMessages.flatMap { message -> [String] in
            if case .chatAppend(_, let items) = message { items.map(\.id) } else { [] }
        }
    }

    private static func updatedIds(_ socket: TestClientSocket) -> [String] {
        socket.receivedMessages.flatMap { message -> [String] in
            if case .chatUpdate(_, let items) = message { items.map(\.id) } else { [] }
        }
    }

    private static func openCodexChat(_ socket: TestClientSocket, id: String = "o-1") async throws -> ChatPage {
        let opened = try await reply(socket, to: .openChat(target: .agent(CodexSample.pane)), id: id)
        guard case .chatPage(let page) = opened else { throw UnexpectedMessage(message: opened) }
        return page
    }

    private static func readsOfTheThread(_ server: FakeCodexAppServer) async -> Int {
        await server.requests(method: "thread/items/list").count + server.requests(method: "thread/read").count + server.requests(method: "thread/turns/list").count
    }

    private static func bindAndHydrate(_ harness: HubHarness, _ codexHarness: CodexServiceHarness, _ codex: CodexService) async throws {
        await codexHarness.serveEmptyPages()
        await codexHarness.server.setHandler("thread/read", CodexSample.readReply([CodexSample.threadId: try #require(try CodexSample.result("thread-read.response.json")["thread"])]))
        try await codexHarness.bind(codex)
        _ = try await eventually { await harness.hub.codexPanes[CodexSample.pane] != nil ? true : nil }
        _ = try await eventually { await codexHarness.server.requests(method: "thread/items/list").isEmpty ? nil : true }
    }

    @Test func liveItemsReachTheOpenChatWithoutReadingTheThreadAgain() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.bindAndHydrate(harness, codexHarness, codex)
            let page = try await Self.openCodexChat(socket)
            #expect(page.items.isEmpty)
            let reads = await Self.readsOfTheThread(codexHarness.server)

            try await codexHarness.replay("command-turn")
            let footer = "01a0f5a1-4002-74e3-99de-cad3477bac9a#end"
            _ = try await eventually { Self.appendedIds(socket).contains(footer) ? true : nil }

            #expect(Self.appendedIds(socket) == [
                "01a0f5a1-4077-79f3-83b3-8058426ded7f",
                "rs_0f438d23f1f4b339016abddb75eb2487d29ca69942affaba80",
                "msg_0f438d23f1f4b339016abddb779e6487d28b8a66d5f40d48fd",
                "exec-8362d0c8-096b-40aa-9497-1aad0fde3c89",
                "exec-b8a03a30-4caf-4f78-bbe6-d1e1a006e14e",
                "msg_0f438d23f1f4b339016abddb7bab3487d2b8a36300fc2b573e",
                footer,
            ])
            #expect(Self.updatedIds(socket) == ["exec-8362d0c8-096b-40aa-9497-1aad0fde3c89", "exec-b8a03a30-4caf-4f78-bbe6-d1e1a006e14e"])
            #expect(await Self.readsOfTheThread(codexHarness.server) == reads)
            _ = try await eventually { harness.herdr.dirtyRefreshCalls.contains(CodexSample.pane) ? true : nil }
        }
    }

    @Test func aLateItemOfAnInterruptedTurnUpdatesItsCardAndDoesNotAlert() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.bindAndHydrate(harness, codexHarness, codex)
            _ = try await Self.openCodexChat(socket)

            try await codexHarness.replay("interrupted-turn")
            let command = "exec-f8463abb-8d46-412a-b723-6e3e75d4a917"
            _ = try await eventually { Self.updatedIds(socket).contains(command) ? true : nil }
            let notice = socket.receivedMessages.lazy.compactMap { message -> ChatItem? in
                guard case .chatAppend(_, let items) = message else { return nil }
                return items.first { $0.id == "01a0f5a4-e9c9-7db2-9616-66d30583af2d#end" }
            }.first
            #expect(notice?.kind == .notice(text: "Interrompido"))
        }
    }

    @Test func theChatMetaCarriesTheThreadSettings() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            try await codexHarness.serveResume()
            let (socket, _) = try await harness.pairedClient()
            try await Self.bindAndHydrate(harness, codexHarness, codex)
            _ = try await eventually { await harness.hub.codexPanes[CodexSample.pane]?.title == "Responder OK1" ? true : nil }
            let page = try await Self.openCodexChat(socket)
            #expect(page.meta.title == "Responder OK1")
            #expect(page.meta.model == "gpt-6.1-sol")
            #expect(page.meta.branch == "s9-branch")
            #expect(page.meta.permissionMode == "default")

            let settings = try #require(try CodexLiveReplay.messages("plan-turn").first?["params"])
            await codexHarness.server.notify("thread/settings/updated", params: settings)
            let meta = try await eventually { () -> ChatMeta? in
                harness.clock.advance(by: .milliseconds(150))
                return socket.receivedMessages.lazy.compactMap { message -> ChatMeta? in
                    if case .chatMeta(_, let meta) = message, meta.permissionMode == "plan" { meta } else { nil }
                }.first
            }
            #expect(meta == ChatMeta(
                title: "Responder OK1",
                workspaceLabel: meta.workspaceLabel,
                model: "gpt-6-luna",
                branch: "s9-branch",
                status: meta.status,
                permissionMode: "plan",
                effort: "high"
            ))
            let summary = try #require(await harness.hub.agentSummary(CodexSample.pane))
            #expect(summary.model == "gpt-6-luna")
            #expect(summary.effort == "high")
            #expect(summary.permissionMode == "plan")
        }
    }

    @Test func aThreadSwitchInThePaneMovesTheChatToTheNewThread() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.bindAndHydrate(harness, codexHarness, codex)
            _ = try await Self.openCodexChat(socket)

            await codexHarness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(CodexSample.thirdThreadId)))
            _ = try await eventually { await harness.hub.codexPanes[CodexSample.pane]?.threadId == CodexSample.thirdThreadId ? true : nil }
            _ = try await eventually { await harness.hub.agentSummary(CodexSample.pane)?.sessionId == CodexSample.thirdThreadId ? true : nil }

            let item = { (threadId: String, id: String) in
                OrderedJSON.object([
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
            await codexHarness.server.notify("item/completed", params: item(CodexSample.threadId, "da-antiga"))
            await codexHarness.server.notify("item/completed", params: item(CodexSample.thirdThreadId, "da-nova"))
            _ = try await eventually { Self.appendedIds(socket).contains("da-nova") ? true : nil }
            #expect(!Self.appendedIds(socket).contains("da-antiga"))
        }
    }

    @Test func theSummaryCarriesTheThreadAsItsSession() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            try await codexHarness.bind(codex)
            _ = try await eventually { await harness.hub.agentSummary(CodexSample.pane)?.sessionId == CodexSample.threadId ? true : nil }
        }
    }
}
