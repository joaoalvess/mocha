import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite struct SessionHubSubagentTests {
    static let agentId = "a1234567890abcdef"
    static let toolUseId = "toolu_subagent_1"

    static func card(status: SubagentStatus = .running, agentId: String? = agentId) -> ChatItem {
        ChatItem(
            id: "card-1",
            at: Sample.start,
            kind: .subagent(SubagentCall(toolUseId: toolUseId, agentId: agentId, agentType: "Explore", description: "Mapear o código", status: status))
        )
    }

    static func state(
        session: String = Sample.sessionA,
        status: SubagentStatus = .running,
        toolUses: Int = 1,
        activity: ToolActivity? = ToolActivity(toolName: "Bash", summary: "swift test", status: .running)
    ) -> SubagentState {
        SubagentState(
            agentId: agentId,
            sessionId: session,
            toolUseId: toolUseId,
            agentType: "Explore",
            description: "Mapear o código",
            status: status,
            activity: status == .running ? activity : nil,
            toolUses: toolUses,
            startedAt: Sample.start,
            durationMs: status == .running ? nil : 4200
        )
    }

    private static func subagentCall(in message: ServerMessage) -> SubagentCall? {
        guard case .chatUpdate(_, let items) = message, case .subagent(let call) = items.first?.kind else { return nil }
        return call
    }

    @Test func cardsFollowTheProviderWithOneUpdatePerSecondAndStatusAtOnce() async throws {
        let subagents = FakeSubagentProvider()
        try await withHub(subagents: subagents, configure: { transcripts in
            await transcripts.setPage(Sample.page([Self.card()]), forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            guard case .chatPage(let page) = reply, case .subagent(let call) = page.items.first?.kind else {
                Issue.record("unexpected reply \(reply)")
                return
            }
            #expect(call.status == .running)

            subagents.publish(Self.state(toolUses: 1))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            let throttled = try await socket.nextMessage { Self.subagentCall(in: $0) != nil }
            #expect(Self.subagentCall(in: throttled)?.toolUses == 1)
            #expect(Self.subagentCall(in: throttled)?.activity?.summary == "swift test")

            subagents.publish(Self.state(status: .completed, toolUses: 3))
            let finished = try await socket.nextMessage { Self.subagentCall(in: $0) != nil }
            #expect(Self.subagentCall(in: finished)?.status == .completed)
            #expect(Self.subagentCall(in: finished)?.durationMs == 4200)
            #expect(Self.subagentCall(in: finished)?.activity == nil)
        }
    }

    @Test func cardWithoutAgentIdIsMatchedByToolUseId() async throws {
        let subagents = FakeSubagentProvider()
        try await withHub(subagents: subagents, configure: { transcripts in
            await transcripts.setPage(Sample.page([Self.card(agentId: nil)]), forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            subagents.publish(Self.state(status: .failed, toolUses: 2))
            let update = try await socket.nextMessage { Self.subagentCall(in: $0) != nil }
            #expect(Self.subagentCall(in: update)?.agentId == Self.agentId)
            #expect(Self.subagentCall(in: update)?.status == .failed)
        }
    }

    @Test func runningSubagentsReachTheTreeAndKeepTheHomeLive() async throws {
        let subagents = FakeSubagentProvider()
        try await withHub(subagents: subagents) { harness in
            let (socket, _) = try await harness.pairedClient()
            await subagents.waitForObserved { $0.contains(Sample.sessionA) }
            subagents.publishRunningCount(2, session: Sample.sessionA)
            try await harness.advanceTreeDebounce()
            let changed = try await socket.nextMessage { message in
                guard case .treeChanged = message else { return false }
                return true
            }
            guard case .treeChanged(let tree) = changed else { return }
            #expect(TreeComposer.agent("w1:p1", in: tree)?.runningSubagents == 2)
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionA)
            #expect(await harness.transcripts.openRequests.contains { $0.session.sessionId == Sample.sessionA && $0.limit == SessionHub.homeLiveLimit })
        }
    }

    @Test func listSubagentsFollowsTheServerRules() async throws {
        let subagents = FakeSubagentProvider()
        let items = [SubagentSummary(agentId: Self.agentId, agentType: "Explore", description: "Mapear o código", status: .running)]
        subagents.setList(items, session: Sample.sessionA)
        try await withHub(subagents: subagents) { harness in
            let (socket, _) = try await harness.pairedClient()
            let list = try await socket.reply(to: .listSubagents(agentId: "w1:p1"))
            #expect(list == .subagentList(agentId: "w1:p1", items: items))
            let codex = try await socket.reply(to: .listSubagents(agentId: "w1:p2"), id: "c-2")
            guard case .error(let code, _) = codex else {
                Issue.record("codex agent answered \(codex)")
                return
            }
            #expect(code == .codexUnavailable)
            let unknown = try await socket.reply(to: .listSubagents(agentId: "w9:p9"), id: "c-3")
            guard case .error(let unknownCode, _) = unknown else { return }
            #expect(unknownCode == .agentNotFound)
        }
    }

    @Test func subagentChatOpensItsTranscriptAndCarriesTheSubagentMeta() async throws {
        let subagents = FakeSubagentProvider()
        let transcript = SubagentTranscript(agentId: Self.agentId, path: "/tmp/agent-\(Self.agentId).jsonl", forkToolUseId: nil)
        subagents.setTranscript(transcript, session: Sample.sessionC)
        let task = ChatItem(id: "task-1", at: Sample.start, kind: .task(text: "Mapear o código"))
        try await withHub(subagents: subagents, configure: { transcripts in
            await transcripts.setPage(Sample.page([task], meta: TranscriptMeta(model: "claude-opus-5-5")), forSession: Sample.sessionC)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let target = ChatTarget.subagent(sessionId: Sample.sessionC, agentId: Self.agentId)
            let reply = try await socket.reply(to: .openChat(target: target))
            guard case .chatPage(let page) = reply else {
                Issue.record("unexpected reply \(reply)")
                return
            }
            #expect(page.target == target)
            #expect(page.items.first?.kind == .task(text: "Mapear o código"))
            #expect(page.meta.model == "claude-opus-5-5")
            #expect(page.meta.permissionMode == nil)
            #expect(await harness.transcripts.openRequests.last?.session.subagent == transcript)

            await subagents.waitForObserved { $0.contains(Sample.sessionC) }
            subagents.publish(Self.state(session: Sample.sessionC))
            let meta = try await socket.nextMessage { message in
                guard case .chatMeta(let metaTarget, let meta) = message else { return false }
                return metaTarget == target && meta.subagent != nil
            }
            guard case .chatMeta(_, let chatMeta) = meta else { return }
            #expect(chatMeta.title == "Mapear o código")
            #expect(chatMeta.subagent?.agentType == "Explore")
            #expect(chatMeta.subagent?.status == .running)

            let closed = try await socket.reply(to: .closeChat(target: target), id: "c-2")
            #expect(closed == .ack())
        }
    }

    @Test func subagentChatRejectsBadIdsAndMissingFiles() async throws {
        let subagents = FakeSubagentProvider()
        try await withHub(subagents: subagents) { harness in
            let (socket, _) = try await harness.pairedClient()
            let badSession = try await socket.reply(to: .openChat(target: .subagent(sessionId: "nope", agentId: Self.agentId)))
            let badAgent = try await socket.reply(to: .openChat(target: .subagent(sessionId: Sample.sessionC, agentId: "../x")), id: "c-2")
            let missing = try await socket.reply(to: .openChat(target: .subagent(sessionId: Sample.sessionC, agentId: Self.agentId)), id: "c-3")
            guard case .error(let sessionCode, _) = badSession,
                  case .error(let agentCode, _) = badAgent,
                  case .error(let missingCode, let message) = missing else {
                Issue.record("expected errors")
                return
            }
            #expect(sessionCode == .invalidPayload)
            #expect(agentCode == .invalidPayload)
            #expect(missingCode == .sessionNotFound)
            #expect(message == "Subagente não encontrado")
        }
    }

    @Test func fakeProviderRecordsAndPublishes() async throws {
        let fake = FakeSubagentProvider()
        let events = fake.events()
        await fake.observe(sessions: [Sample.sessionA])
        #expect(fake.observedSessions == [[Sample.sessionA]])
        fake.publish(Self.state())
        fake.publishRunningCount(1, session: Sample.sessionA)
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .subagent(Self.state()))
        #expect(await iterator.next() == .runningCount(sessionId: Sample.sessionA, count: 1))
        #expect(await fake.state(Self.agentId) == Self.state())
        #expect(await fake.runningCount(session: Sample.sessionA) == 1)
        #expect(await fake.transcript(session: Sample.sessionA, agentId: Self.agentId) == nil)
    }
}
