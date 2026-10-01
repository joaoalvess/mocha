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

    @Test func theSummaryCarriesTheThreadAsItsSession() async throws {
        try await withCodexHub { harness, codexHarness, codex in
            try await codexHarness.bind(codex)
            _ = try await eventually { await harness.hub.agentSummary(CodexSample.pane)?.sessionId == CodexSample.threadId ? true : nil }
        }
    }
}
