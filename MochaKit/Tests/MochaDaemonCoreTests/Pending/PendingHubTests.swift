import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

func withPendingHub(_ body: (HubHarness, PendingHarness) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-pending-\(UUID().uuidString)", directoryHint: .isDirectory)
    let herdr = FakeHerdrBridge(tree: Sample.defaultTree, agents: Sample.herdrAgents(in: Sample.defaultTree))
    let transcripts = FakeTranscriptProvider()
    let hubClock = ManualClock(origin: Sample.start)
    let storeClock = ManualClock(origin: Sample.start)
    let store = PendingStore(herdr: herdr, transcripts: transcripts, clock: storeClock)
    await store.start()
    let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
    let pairing = Pairing(clock: hubClock)
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
        clock: hubClock,
        configuration: SessionHubConfiguration(hostName: "Mac de Teste", daemonVersion: "9.9.9")
    )
    await hub.start()
    let hooks = HookEventHub()
    let server = HookServer(
        secrets: HookSecretVerifier(secret: PendingSample.secret),
        events: hooks,
        permissions: store,
        resolveAgent: { await herdr.resolve($0) },
        now: { storeClock.now() }
    )
    let hubHarness = HubHarness(
        herdr: herdr,
        transcripts: transcripts,
        usage: usage,
        archive: archive,
        subagents: subagents,
        clock: hubClock,
        devices: devices,
        pairing: pairing,
        hub: hub,
        directory: directory
    )
    let pendingHarness = PendingHarness(herdr: herdr, transcripts: transcripts, clock: storeClock, store: store, hooks: hooks, server: server)
    _ = try await eventually { await store.observedEvents > 0 ? true : nil }
    do {
        try await body(hubHarness, pendingHarness)
    } catch {
        await store.shutdown()
        await hub.shutdown()
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    await store.shutdown()
    await hub.shutdown()
    try? FileManager.default.removeItem(at: directory)
}

extension TestClientSocket {
    func collect(until done: ([ServerEnvelope]) -> Bool) async throws -> [ServerEnvelope] {
        var envelopes: [ServerEnvelope] = []
        while !done(envelopes) {
            envelopes.append(try await next())
        }
        return envelopes
    }
}

@Suite(.timeLimit(.minutes(1)))
struct PendingHubTests {
    static func pendingClient(_ harness: HubHarness) async throws -> TestClientSocket {
        let (socket, _) = try await harness.pairedClient()
        let initial = try await socket.next()
        #expect(initial.id == nil)
        #expect(initial.message == .pending(requests: []))
        return socket
    }

    static func agent(_ id: AgentID, in tree: [WorkspaceNode]) -> AgentSummary? {
        TreeComposer.agent(id, in: tree)
    }

    @Test func helloEndsWithTheCurrentPendingList() async throws {
        try await withPendingHub { hub, pending in
            let held = try await pending.hold("PermissionRequest.bash.json")
            let request = try #require(await pending.store.requests.first)
            _ = try await eventually { await hub.hub.pendingRequests == [request] ? true : nil }

            let (socket, _) = try await hub.pairedClient()

            let message = try await socket.next()
            #expect(message.id == nil)
            #expect(message.message == .pending(requests: [request]))
            #expect(socket.initialTree.flatMap { Self.agent(PendingSample.agent, in: $0) }?.pendingCount == 1)
            try await pending.closeAndWait(held)
        }
    }

    @Test func creationAndEndAreBroadcastAndCountedInTheTree() async throws {
        try await withPendingHub { hub, pending in
            let socket = try await Self.pendingClient(hub)

            let held = try await pending.hold("PermissionRequest.bash.json")

            let request = try #require(await pending.store.requests.first)
            #expect(try await socket.nextMessage() == .pending(requests: [request]))
            try await hub.advanceTreeDebounce()
            guard case .treeChanged(let tree) = try await socket.nextMessage() else { throw TestTimeoutError() }
            #expect(Self.agent(PendingSample.agent, in: tree)?.pendingCount == 1)
            #expect(Self.agent("w1:p2", in: tree)?.pendingCount == 0)
            #expect(await hub.hub.agentSummary(PendingSample.agent)?.pendingCount == 1)

            try socket.deliver(.respond(requestId: held.requestId, response: .allow), id: "c-9")
            let envelopes = try await socket.collect { envelopes in
                envelopes.contains { $0.id == "c-9" } && envelopes.contains { $0.message == .pending(requests: []) }
            }
            #expect(envelopes.first { $0.id == "c-9" }?.message == .ack())
            #expect(try OrderedJSON.parse(await held.response().body) == PendingHookReply.allow())
            try await hub.advanceTreeDebounce()
            guard case .treeChanged(let after) = try await socket.nextMessage() else { throw TestTimeoutError() }
            #expect(Self.agent(PendingSample.agent, in: after)?.pendingCount == 0)
        }
    }

    static let notFound = ServerMessage.error(code: .requestNotFound, message: "Este pedido já foi respondido ou expirou.")

    static func respond(_ socket: TestClientSocket, _ response: PendingResponse, to requestId: RequestID, id: String) async throws -> ServerMessage? {
        try socket.deliver(.respond(requestId: requestId, response: response), id: id)
        return try await socket.collect { $0.contains { $0.id == id } }.first { $0.id == id }?.message
    }

    @Test func respondErrorsFollowTheSpec() async throws {
        try await withPendingHub { hub, pending in
            let socket = try await Self.pendingClient(hub)
            let question = try await pending.hold("PermissionRequest.AskUserQuestion.multi.json")
            let permission = try await pending.hold("PermissionRequest.bash.json")
            _ = try await socket.nextMessage { message in
                guard case .pending(let requests) = message else { return false }
                return requests.count == 2
            }

            #expect(try await Self.respond(socket, .allow, to: question.requestId, id: "c-1") == .error(code: .invalidPayload, message: PendingHookReply.allowOnQuestion))
            #expect(
                try await Self.respond(socket, .answers(["Qual editor?": ["Vim"]]), to: question.requestId, id: "c-2")
                    == .error(code: .invalidPayload, message: PendingHookReply.missingAnswer("Quais testes?"))
            )
            #expect(
                try await Self.respond(socket, .answers(["Qual banco?": ["SQLite"]]), to: permission.requestId, id: "c-3")
                    == .error(code: .invalidPayload, message: PendingHookReply.answersOnPermission)
            )
            #expect(try await Self.respond(socket, .deny(reason: nil), to: "nao-existe", id: "c-4") == Self.notFound)
            #expect(await pending.store.requests.count == 2)

            #expect(try await Self.respond(socket, .deny(reason: nil), to: question.requestId, id: "c-5") == .ack())
            #expect(try OrderedJSON.parse(await question.response().body) == PendingHookReply.deny(nil))
            #expect(try await Self.respond(socket, .deny(reason: nil), to: question.requestId, id: "c-6") == Self.notFound)
            try await pending.closeAndWait(permission)
        }
    }
}
