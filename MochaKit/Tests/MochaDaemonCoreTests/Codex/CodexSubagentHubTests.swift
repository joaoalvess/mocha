import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

private func withCodexSubagentHub(_ body: (HubHarness, CodexServiceHarness, CodexService) async throws -> Void) async throws {
    try await withCodexServer { codexHarness in
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-codex-subagents-\(UUID().uuidString)", directoryHint: .isDirectory)
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
struct CodexSubagentHubTests {
    private static let child = CodexSample.otherThreadId
    private static let rootTitle = "Responder OK1"
    private static let cardId = "call_7EWkRgqP8fNGsoIyGhbvxr8U"
    private static let spawnedAt = Date(timeIntervalSinceReferenceDate: 812_520_266.034)

    private static func childThread() throws -> OrderedJSON {
        try #require(try CodexSample.result("thread-read.subagent.response.json")["thread"])
    }

    private static func listing(_ threads: [OrderedJSON]) -> FakeCodexReply {
        .result(.object([.init("data", .array(threads)), .init("nextCursor", .null)]))
    }

    private static func prepare(_ harness: HubHarness, _ codexHarness: CodexServiceHarness, _ codex: CodexService) async throws {
        try await codexHarness.serveResume()
        await codexHarness.serveEmptyPages()
        await codexHarness.server.setHandler("thread/read", CodexSample.readReply([
            CodexSample.threadId: try #require(try CodexSample.result("thread-read.response.json")["thread"]),
            child: try childThread(),
        ]))
        try await codexHarness.bind(codex)
        _ = try await eventually { await harness.hub.codexPanes[CodexSample.pane]?.title == rootTitle ? true : nil }
        _ = try await eventually { await codexHarness.server.requests(method: "thread/list").isEmpty ? nil : true }
    }

    private static func tracked(_ harness: HubHarness, _ threadId: String) async throws {
        _ = try await eventually {
            harness.clock.advance(by: .milliseconds(150))
            return await harness.hub.trackedSessions[threadId] != nil ? true : nil
        }
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

    private static func page(_ socket: TestClientSocket, _ target: ChatTarget, id: String) async throws -> ChatPage {
        let reply = try await Self.reply(socket, to: .openChat(target: target), id: id)
        guard case .chatPage(let page) = reply else { throw UnexpectedMessage(message: reply) }
        return page
    }

    private static func cards(_ socket: TestClientSocket, child: String) -> [SubagentCall] {
        socket.receivedMessages.flatMap { message -> [ChatItem] in
            switch message {
            case .chatAppend(.agent, let items), .chatUpdate(.agent, let items): items
            default: []
            }
        }.compactMap { item in
            guard case .subagent(let call) = item.kind, call.agentId == child else { return nil }
            return call
        }
    }

    private static func runningBadges(_ socket: TestClientSocket) -> [Int?] {
        socket.receivedMessages.compactMap { message in
            guard case .treeChanged(let workspaces) = message else { return nil }
            return TreeComposer.agent(CodexSample.pane, in: workspaces).map(\.runningSubagents)
        }
    }

    private static func lastTreeAgent(_ socket: TestClientSocket) -> AgentSummary? {
        socket.receivedMessages.last { if case .treeChanged = $0 { true } else { false } }.flatMap { message in
            guard case .treeChanged(let workspaces) = message else { return nil }
            return TreeComposer.agent(CodexSample.pane, in: workspaces)
        }
    }

    private static func activity(_ kind: String, child: String, path: String, on threadId: String, at seconds: TimeInterval) -> OrderedJSON {
        .object([
            .init("item", .object([
                .init("type", .string("subAgentActivity")),
                .init("id", .string("\(kind)-\(child)")),
                .init("kind", .string(kind)),
                .init("agentThreadId", .string(child)),
                .init("agentPath", .string(path)),
            ])),
            .init("threadId", .string(threadId)),
            .init("turnId", .string("turn-\(threadId)")),
            .init("startedAtMs", .number(String(Int(seconds * 1000)))),
        ])
    }

    private static func turnStarted(_ threadId: String, at date: Date) -> OrderedJSON {
        .object([
            .init("threadId", .string(threadId)),
            .init("turn", .object([
                .init("id", .string("turn-novo")),
                .init("items", .array([])),
                .init("status", .string("inProgress")),
                .init("error", .null),
                .init("startedAt", .number(String(Int(date.timeIntervalSince1970)))),
                .init("completedAt", .null),
                .init("durationMs", .null),
            ])),
        ])
    }

    @Test func aChildRunsAndFinishesOnTheCardTheBadgeAndItsChat() async throws {
        try await withCodexSubagentHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.prepare(harness, codexHarness, codex)
            _ = try await Self.page(socket, .agent(CodexSample.pane), id: "o-1")
            let listed = try Self.childThread().setting("turns", to: nil)
            await codexHarness.server.setHandler("thread/list") { request in
                Self.listing(request.string("parentThreadId") == CodexSample.threadId ? [listed] : [])
            }

            let messages = try CodexLiveReplay.messages("subagent-turn")
            for message in messages.prefix(11) {
                await codexHarness.server.notify(try #require(message["method"]?.stringValue), params: try #require(message["params"]))
            }
            _ = try await eventually {
                harness.clock.advance(by: .milliseconds(150))
                return Self.runningBadges(socket).contains(1) ? true : nil
            }
            let running = try await eventually { Self.cards(socket, child: Self.child).last { $0.agentType == "Pascal" } }
            #expect(running.status == .running)
            #expect(running.description == "list_directory")
            #expect(running.startedAt == Self.spawnedAt)

            for message in messages.dropFirst(11) {
                await codexHarness.server.notify(try #require(message["method"]?.stringValue), params: try #require(message["params"]))
            }
            let finished = try await eventually { () -> SubagentCall? in
                harness.clock.advance(by: .milliseconds(150))
                return Self.cards(socket, child: Self.child).last { $0.status == .completed && $0.toolUses == 1 }
            }
            #expect(finished.agentType == "Pascal")
            #expect(finished.durationMs == 5638)
            #expect(finished.activity == nil)
            _ = try await eventually {
                harness.clock.advance(by: .milliseconds(150))
                return Self.runningBadges(socket).last == .some(nil) ? true : nil
            }
            #expect(await harness.hub.agentSummary(CodexSample.pane)?.runningSubagents == nil)

            let page = try await Self.page(socket, .codexThread(Self.child), id: "o-2")
            #expect(page.meta.title == "list_directory")
            #expect(page.meta.subagent == SubagentChatInfo(
                parentTitle: Self.rootTitle,
                agentType: "Pascal",
                status: .completed,
                startedAt: Self.spawnedAt,
                durationMs: 5638,
                toolUses: 1
            ))

            await codexHarness.server.notify("item/completed", params: .object([
                .init("item", .object([.init("type", .string("agentMessage")), .init("id", .string("msg-filha")), .init("text", .string("mais"))])),
                .init("threadId", .string(Self.child)),
                .init("turnId", .string("turn-filha")),
                .init("completedAtMs", CodexSample.nowMs()),
            ]))
            _ = try await eventually {
                socket.receivedMessages.contains { message in
                    guard case .chatAppend(.codexThread(Self.child), let items) = message else { return false }
                    return items.contains { $0.id == "msg-filha" }
                } ? true : nil
            }
        }
    }

    @Test func theCodexListFollowsTheSubagentOrder() async throws {
        try await withCodexSubagentHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.prepare(harness, codexHarness, codex)
            let start: TimeInterval = 1_790_827_000
            let root = CodexSample.threadId
            let events = [
                Self.activity("started", child: "filha-a", path: "/root/scout", on: root, at: start),
                Self.activity("started", child: "filha-b", path: "/root/writer", on: root, at: start + 1),
                Self.activity("started", child: "neta-c", path: "/root/scout/helper", on: "filha-a", at: start + 2),
                Self.activity("completed", child: "filha-b", path: "/root/writer", on: root, at: start + 3),
                Self.activity("started", child: "filha-d", path: "/root/reviewer", on: root, at: start + 4),
            ]
            for event in events {
                await codexHarness.server.notify("item/started", params: event)
            }
            _ = try await eventually {
                let subagents = await harness.hub.codexSubagents
                return subagents.count == 4 && subagents["filha-b"]?.status == .completed ? true : nil
            }

            let reply = try await Self.reply(socket, to: .listSubagents(agentId: CodexSample.pane), id: "l-1")
            guard case .subagentList(let agentId, let items) = reply else { throw UnexpectedMessage(message: reply) }
            #expect(agentId == CodexSample.pane)
            #expect(items.map(\.agentId) == ["filha-d", "filha-a", "neta-c", "filha-b"])
            #expect(items.map(\.agentType) == ["reviewer", "scout", "helper", "writer"])
            #expect(items.map(\.parentAgentId) == [nil, nil, "filha-a", nil])
            #expect(items.map(\.status) == [.running, .running, .running, .completed])
            #expect(items[3].durationMs == 2000)
            #expect(items[2].startedAt == Date(timeIntervalSince1970: start + 2))
            _ = try await eventually {
                harness.clock.advance(by: .milliseconds(150))
                return Self.runningBadges(socket).last == 3 ? true : nil
            }
        }
    }

    @Test func anUnboundCodexTabAnswersCodexUnavailableToTheList() async throws {
        try await withCodexSubagentHub { harness, codexHarness, _ in
            try await codexHarness.connected()
            let (socket, _) = try await harness.pairedClient()
            let reply = try await Self.reply(socket, to: .listSubagents(agentId: CodexSample.pane), id: "l-1")
            guard case .error(let code, _) = reply else { throw UnexpectedMessage(message: reply) }
            #expect(code == .codexUnavailable)
        }
    }

    @Test func aFinishedChildOpensFromThreadReadWithItsSubagentMeta() async throws {
        try await withCodexSubagentHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.prepare(harness, codexHarness, codex)

            let page = try await Self.page(socket, .codexThread(Self.child), id: "o-1")
            #expect(page.meta.title == "list_directory")
            #expect(page.meta.subagent == SubagentChatInfo(
                parentTitle: Self.rootTitle,
                agentType: "Pascal",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: 1_790_827_466),
                durationMs: 5634,
                toolUses: 1
            ))
            let reads = await codexHarness.server.requests(method: "thread/read").filter { $0.string("threadId") == Self.child }
            #expect(reads.contains { $0.params["includeTurns"]?.boolValue == true })
        }
    }

    @Test func closingTheCodexPaneArchivesItsThreadAsEnded() async throws {
        try await withCodexSubagentHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.prepare(harness, codexHarness, codex)
            try await Self.tracked(harness, CodexSample.threadId)
            let summary = try #require(await harness.hub.agentSummary(CodexSample.pane))

            harness.herdr.setTree(SessionHubArchiveTests.treeWithout(CodexSample.pane))
            let record = try await eventually { harness.archive.endedCalls.first { $0.id == CodexSample.threadId } }
            #expect(record.provider == .codex)
            #expect(record.reason == .ended)
            #expect(record.agentId == CodexSample.pane)
            #expect(record.title == Self.rootTitle)
            #expect(record.workspaceLabel == summary.workspaceLabel)
            #expect(record.model == "gpt-6.1-sol")

            _ = try await eventually { await harness.hub.archivedSessions.contains { $0.id == CodexSample.threadId } ? true : nil }
            let page = try await Self.page(socket, .codexThread(CodexSample.threadId), id: "o-1")
            #expect(page.meta.title == Self.rootTitle)
            #expect(page.meta.workspaceLabel == summary.workspaceLabel)
            #expect(page.meta.subagent == nil)
        }
    }

    @Test func aNewThreadInThePaneArchivesTheOldOneAsCleared() async throws {
        try await withCodexSubagentHub { harness, codexHarness, codex in
            try await Self.prepare(harness, codexHarness, codex)
            try await Self.tracked(harness, CodexSample.threadId)

            await codexHarness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(CodexSample.thirdThreadId)))
            let record = try await eventually { () -> ArchivedSession? in
                harness.clock.advance(by: .milliseconds(150))
                return harness.archive.endedCalls.first { $0.id == CodexSample.threadId }
            }
            #expect(record.provider == .codex)
            #expect(record.reason == .cleared)
            #expect(record.title == Self.rootTitle)
            #expect(record.agentId == CodexSample.pane)
            try await Self.tracked(harness, CodexSample.thirdThreadId)
            #expect(!harness.archive.endedCalls.contains { $0.id == CodexSample.thirdThreadId })
        }
    }

    @Test func archiveHidesTheCurrentCodexThreadUntilItsNextTurn() async throws {
        try await withCodexSubagentHub { harness, codexHarness, codex in
            let (socket, _) = try await harness.pairedClient()
            try await Self.prepare(harness, codexHarness, codex)
            try await Self.tracked(harness, CodexSample.threadId)

            let other = try await Self.reply(socket, to: .archive(sessionId: CodexSample.otherThreadId, provider: .codex), id: "a-1")
            #expect(other == .error(code: .sessionNotFound, message: "A sessão não é a atual de nenhum agente."))
            #expect(try await Self.reply(socket, to: .archive(sessionId: CodexSample.threadId, provider: .codex), id: "a-2") == .ack())
            #expect(harness.archive.archiveCalls == [FakeArchiveCall(sessionId: CodexSample.threadId, date: harness.clock.now())])
            let archivedAt = try await eventually { () -> Date? in
                harness.clock.advance(by: .milliseconds(150))
                return Self.lastTreeAgent(socket)?.archivedAt
            }
            #expect(archivedAt == harness.archive.userArchived[CodexSample.threadId])

            await codexHarness.server.notify("turn/started", params: Self.turnStarted(CodexSample.threadId, at: Date()))
            _ = try await eventually {
                harness.clock.advance(by: .milliseconds(150))
                return Self.lastTreeAgent(socket).map { $0.archivedAt == nil } == true ? true : nil
            }
            #expect(harness.archive.userArchived[CodexSample.threadId] == nil)
            #expect(harness.archive.turnStartedCalls.contains { $0.sessionId == CodexSample.threadId })
        }
    }
}

@Suite
struct CodexSubagentsTests {
    @Test func aChildReadFromItsThreadCarriesTheTurnTotals() throws {
        let thread = try #require(try CodexSample.result("thread-read.subagent.response.json")["thread"])
        let subagent = try #require(CodexSubagents.read(thread))
        #expect(subagent.threadId == CodexSample.otherThreadId)
        #expect(subagent.parentThreadId == CodexSample.threadId)
        #expect(subagent.rootThreadId == CodexSample.threadId)
        #expect(subagent.agentType == "Pascal")
        #expect(subagent.description == "list_directory")
        #expect(subagent.status == .completed)
        #expect(subagent.durationMs == 5634)
        #expect(subagent.toolUses == 1)
        #expect(subagent.failureReason == nil)
    }

    @Test func aFailedLastTurnMarksTheChildFailedWithItsMessage() throws {
        let thread = try #require(try CodexSample.result("thread-read.subagent.response.json")["thread"])
        let turn = try #require(thread["turns"]?.arrayValue?.first)
            .setting("status", to: .string("failed"))
            .setting("error", to: .object([.init("message", .string("Sem acesso ao diretório."))]))
        let subagent = try #require(CodexSubagents.read(thread.setting("turns", to: .array([turn]))))
        #expect(subagent.status == .failed)
        #expect(subagent.failureReason == "Sem acesso ao diretório.")
        #expect(subagent.state.summary.status == .failed)
    }

    @Test func aListedChildWithoutNicknameUsesTheLastSegmentOfItsPath() throws {
        let thread = try #require(try CodexSample.result("thread-read.subagent.response.json")["thread"])
        let listed = try #require(CodexListedThread(thread.setting("agentNickname", to: .null).setting("status", to: .object([.init("type", .string("active"))]))))
        #expect(listed.nickname == nil)
        #expect(listed.name == "list_directory")
        #expect(listed.status == .running)
    }
}
