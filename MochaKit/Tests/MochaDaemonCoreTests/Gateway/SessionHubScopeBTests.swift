import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubScopeBTests {
    private static let archivedMeta = TranscriptMeta(
        title: "sessao-arquivada",
        model: "claude-haiku-4-5-20251001",
        branch: "main",
        permissionMode: "default",
        contextTokens: 50_000
    )

    @Test func openChatBySessionIdPagesAndFollowsWithTheSameSessionId() async throws {
        let items = [Sample.item("s1", text: "arquivo antigo")]
        let older = [Sample.item("s0", text: "mais antigo")]
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.archivedMeta, forSession: Sample.sessionC)
            await transcripts.setPage(Sample.page(items, meta: Self.archivedMeta, before: "\(Sample.sessionC):5"), forSession: Sample.sessionC)
            await transcripts.setPage(Sample.page(older, meta: Self.archivedMeta), forSession: Sample.sessionC, before: "\(Sample.sessionC):5")
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let target = ChatTarget.session(Sample.sessionC)
            let meta = ChatMeta(title: "sessao-arquivada", workspaceLabel: "", model: "claude-haiku-4-5-20251001", branch: "main", status: .unknown, permissionMode: "default")
            let reply = try await socket.reply(to: .openChat(target: target), id: "c-11")
            #expect(reply == .chatPage(ChatPage(target: target, meta: meta, items: items, before: "\(Sample.sessionC):5", hasMore: true)))

            let olderReply = try await socket.reply(to: .openChat(target: target, before: "\(Sample.sessionC):5"), id: "c-12")
            #expect(olderReply == .chatPage(ChatPage(target: target, meta: meta, items: older, before: nil, hasMore: false)))

            let appended = Sample.item("s2", text: "linha nova")
            await harness.transcripts.emit(.append([appended]), toSession: Sample.sessionC)
            #expect(try await socket.nextMessage() == .chatAppend(target: target, items: [appended]))
            var renamed = Self.archivedMeta
            renamed.title = "sessao-renomeada"
            await harness.transcripts.publishMeta(renamed, toSession: Sample.sessionC)
            var renamedMeta = meta
            renamedMeta.title = "sessao-renomeada"
            #expect(try await socket.nextMessage() == .chatMeta(target: target, meta: renamedMeta))

            #expect(await harness.hub.followedSessions() == [FollowedSession(sessionId: Sample.sessionC, agentId: nil)])
            #expect(try await socket.reply(to: .closeChat(target: target), id: "c-13") == .ack())
            await harness.transcripts.waitForSubscribers(0, forSession: Sample.sessionC)
            #expect(harness.herdr.openChatsCalls.filter { !$0.isEmpty }.isEmpty)
        }
    }

    @Test func sessionIdOutsideTheUUIDFormatIsInvalidPayload() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .openChat(target: .session("../../etc/passwd"))).errorCode == .invalidPayload)
            #expect(try await socket.reply(to: .closeChat(target: .session("abc"))).errorCode == .invalidPayload)
            #expect(await harness.transcripts.metaRequests.allSatisfy { $0.sessionId != "../../etc/passwd" })
        }
    }

    @Test func sessionWithoutFileIsSessionNotFound() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .openChat(target: .session(Sample.sessionB))).errorCode == .sessionNotFound)
            #expect(try await socket.reply(to: .closeChat(target: .session(Sample.sessionB))).errorCode == .sessionNotFound)
            #expect(await harness.transcripts.openRequests.isEmpty)
        }
    }

    @Test func herdrStatusFollowsEveryAvailabilityChange() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.emit(.availability(false))
            #expect(try await socket.nextMessage() == .herdrStatus(connected: false))
            harness.herdr.emit(.availability(false))
            harness.herdr.emit(.availability(true))
            #expect(try await socket.nextMessage() == .herdrStatus(connected: true))
            harness.herdr.emit(.availability(true))
            harness.herdr.emit(.availability(false))
            #expect(try await socket.nextMessage() == .herdrStatus(connected: false))
        }
    }

    @Test func previewAndActivityOfAnAgentWithoutChatReachTheTree() async throws {
        let tree = [Sample.workspace("w1", tabs: [TabNode(id: "w1:t1", title: "Claude", agents: [Sample.agent("w1:p1", status: .working, sessionId: Sample.sessionA)])])]
        let initial = TranscriptMeta(model: "claude-opus-5-5", preview: MessagePreview(author: .user, text: "roda os testes"))
        try await withHub(tree: tree, configure: { transcripts in
            await transcripts.setMeta(initial, forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionA)

            var withPreview = initial
            withPreview.preview = MessagePreview(author: .assistant, text: "Rodando scripts/test.sh")
            await harness.transcripts.publishMeta(withPreview, toSession: Sample.sessionA)
            let first = try await Self.nextTree(socket, harness: harness) {
                TreeComposer.agent("w1:p1", in: $0)?.preview == withPreview.preview
            }
            #expect(TreeComposer.agent("w1:p1", in: first)?.activity == nil)

            var withActivity = withPreview
            withActivity.activity = ToolActivity(toolName: "Bash", summary: "scripts/test.sh", status: .running)
            await harness.transcripts.publishMeta(withActivity, toSession: Sample.sessionA)
            let second = try await Self.nextTree(socket, harness: harness) {
                TreeComposer.agent("w1:p1", in: $0)?.activity == withActivity.activity
            }
            #expect(TreeComposer.agent("w1:p1", in: second)?.preview == withPreview.preview)
            #expect(await harness.transcripts.openRequests.map(\.limit) == [SessionHub.homeLiveLimit])
            #expect(await harness.hub.followedSessions() == [FollowedSession(sessionId: Sample.sessionA, agentId: "w1:p1")])
        }
    }

    @Test func homeLiveFollowOpensOnWorkingAndReleasesThirtySecondsAfterIdle() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(await harness.transcripts.subscriberCount(forSession: Sample.sessionA) == 0)

            harness.herdr.emit(.agentStatus("w1:p1", .working, title: nil))
            #expect(try await socket.nextMessage() == .agentStatus(agentId: "w1:p1", status: .working, title: "terminal-title"))
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionA)
            #expect(await harness.hub.followedSessions() == [FollowedSession(sessionId: Sample.sessionA, agentId: "w1:p1")])

            harness.herdr.emit(.agentStatus("w1:p1", .idle, title: nil))
            #expect(try await socket.nextMessage() == .agentStatus(agentId: "w1:p1", status: .idle, title: "terminal-title"))
            try await harness.clock.waitForSleepers(2)
            harness.clock.advance(by: .milliseconds(150))
            harness.clock.advance(by: .milliseconds(29_849))
            #expect(await harness.transcripts.subscriberCount(forSession: Sample.sessionA) == 1)
            harness.clock.advance(by: .milliseconds(1))
            await harness.transcripts.waitForSubscribers(0, forSession: Sample.sessionA)
            #expect(await harness.hub.followedSessions().isEmpty)
            #expect(await harness.transcripts.openRequests.map(\.limit) == [SessionHub.homeLiveLimit])
        }
    }

    @Test func workingAgainBeforeThirtySecondsKeepsTheFollow() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.emit(.agentStatus("w1:p1", .working, title: nil))
            _ = try await socket.nextMessage()
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionA)
            harness.herdr.emit(.agentStatus("w1:p1", .done, title: nil))
            _ = try await socket.nextMessage()
            try await harness.clock.waitForSleepers(2)
            harness.clock.advance(by: .seconds(10))
            harness.herdr.emit(.agentStatus("w1:p1", .blocked, title: nil))
            _ = try await socket.nextMessage(matching: { $0 == .agentStatus(agentId: "w1:p1", status: .blocked, title: "terminal-title") })
            _ = try await eventually { harness.clock.pendingDelays.allSatisfy { $0 < .seconds(1) } ? true : nil }
            harness.clock.advance(by: .seconds(60))
            #expect(await harness.transcripts.subscriberCount(forSession: Sample.sessionA) == 1)
            #expect(await harness.transcripts.openCount(forSession: Sample.sessionA) == 1)
            #expect(await harness.hub.followedSessions() == [FollowedSession(sessionId: Sample.sessionA, agentId: "w1:p1")])
        }
    }

    @Test func liveFollowIsOnlyForClaudeAgents() async throws {
        let tree = [Sample.workspace("w1", tabs: [
            TabNode(id: "w1:t1", title: "Codex", agents: [Sample.agent("w1:p1", status: .working, sessionId: Sample.sessionB, kind: "codex", title: "codex")]),
        ])]
        try await withHub(tree: tree) { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.emit(.agentStatus("w1:p1", .blocked, title: nil))
            _ = try await socket.nextMessage()
            #expect(try await socket.reply(to: .ping, id: "c-2") == .pong)
            #expect(await harness.hub.followedSessions().isEmpty)
            #expect(await harness.transcripts.openRequests.isEmpty)
        }
    }

    @Test func permissionModeComesFromTheTranscript() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(TranscriptMeta(permissionMode: "plan"), forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.permissionMode == "plan")
        }
    }

    @Test func contextLeftComesFromContextTokensAndTheModelWindow() async throws {
        let meta = TranscriptMeta(model: "claude-opus-5-5", contextTokens: 250_000)
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(meta, forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.contextLeftPercent == 75)
        }
    }

    @Test(arguments: [
        (TranscriptMeta(model: "claude-opus-5-5", contextTokens: 250_000), 75),
        (TranscriptMeta(model: "claude-opus-4-7", contextTokens: 123_456), 88),
        (TranscriptMeta(model: "claude-sonnet-4-5-20250929", contextTokens: 50_000), 75),
        (TranscriptMeta(model: "claude-haiku-4-5-20251001", contextTokens: 300_000), 0),
        (TranscriptMeta(contextTokens: 20_000), 90),
        (TranscriptMeta(model: "claude-opus-5-5", contextTokens: 0), 100),
    ])
    func contextLeftPercentRules(meta: TranscriptMeta, expected: Int) {
        #expect(TreeComposer.contextLeftPercent(meta) == expected)
    }

    @Test func contextLeftIsNilWithoutContextTokens() {
        #expect(TreeComposer.contextLeftPercent(TranscriptMeta(model: "claude-opus-5-5")) == nil)
    }

    private static func nextTree(
        _ socket: TestClientSocket,
        harness: HubHarness,
        where predicate: @escaping ([WorkspaceNode]) -> Bool
    ) async throws -> [WorkspaceNode] {
        try await eventually {
            harness.clock.advance(by: .milliseconds(150))
            while socket.pendingCount > 0 {
                if case .treeChanged(let tree) = try? await socket.nextMessage(), predicate(tree) {
                    return tree
                }
            }
            return nil
        }
    }
}
