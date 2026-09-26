import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubCompositionTests {
    private static let fullMeta = TranscriptMeta(
        title: "herdr-sidebar abre arquivos",
        model: "claude-opus-5-5",
        branch: "development",
        permissionMode: "auto",
        claudeVersion: "2.1.283",
        lastModified: Sample.start.addingTimeInterval(-60),
        preview: MessagePreview(author: .assistant, text: "Pronto, os testes passaram."),
        activity: ToolActivity(toolName: "Bash", summary: "scripts/test.sh", status: .succeeded),
        contextTokens: 100_000,
        sessionStartedAt: Sample.start.addingTimeInterval(-3600),
        turnStartedAt: Sample.start.addingTimeInterval(-300),
        turnEndedAt: Sample.start.addingTimeInterval(-60)
    )

    @Test func titleModelAndBranchComeFromTheRightSources() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.fullMeta, forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            let tree = try #require(socket.initialTree)
            let agent = try #require(TreeComposer.agent("w1:p1", in: tree))
            #expect(agent == AgentSummary(
                id: "w1:p1",
                kind: "claude",
                status: .idle,
                title: "herdr-sidebar abre arquivos",
                workspaceLabel: "Core",
                model: "claude-opus-5-5",
                branch: "feature/foreground",
                sessionId: Sample.sessionA,
                lastActivityAt: Self.fullMeta.lastModified,
                preview: Self.fullMeta.preview,
                activity: Self.fullMeta.activity,
                contextLeftPercent: 90,
                sessionStartedAt: Self.fullMeta.sessionStartedAt,
                turnStartedAt: Self.fullMeta.turnStartedAt,
                turnEndedAt: Self.fullMeta.turnEndedAt
            ))
            #expect(TreeComposer.agent("w1:p2", in: tree) == Sample.agent("w1:p2", kind: "codex", title: "codex"))

            let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            guard case .chatPage(let page) = reply else { throw UnexpectedMessage(message: reply) }
            #expect(page.meta == ChatMeta(
                title: "herdr-sidebar abre arquivos",
                workspaceLabel: "Core",
                model: "claude-opus-5-5",
                branch: "development",
                status: .idle,
                permissionMode: "auto"
            ))
        }
    }

    @Test func titleFallsBackToTheHerdrTitleWithoutAiTitle() async throws {
        var meta = Self.fullMeta
        meta.title = nil
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(meta, forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.title == "terminal-title")
            guard case .chatPage(let page) = try await socket.reply(to: .openChat(target: .agent("w1:p1"))) else {
                Issue.record("expected a chat page")
                return
            }
            #expect(page.meta.title == "terminal-title")
        }
    }

    @Test func workspaceStatusAggregatesItsOwnAgents() {
        let child = Sample.workspace("w2", tabs: [TabNode(id: "w2:t1", title: "c", agents: [Sample.agent("w2:p1", status: .done)])])
        let tree = [
            Sample.workspace("w1", tabs: [
                TabNode(id: "w1:t1", title: "a", agents: [Sample.agent("w1:p1", status: .idle), Sample.agent("w1:p2", status: .done)]),
                TabNode(id: "w1:t2", title: "b", agents: [Sample.agent("w1:p3", status: .idle)]),
            ], children: [child]),
            Sample.workspace("w3", tabs: [TabNode(id: "w3:t1", title: "shell")]),
        ]
        #expect(tree.map(\.agentStatus) == [.done, .unknown])
        let working = TreeComposer.updatingAgent("w1:p3", in: tree) { $0.status = .working }
        #expect(working[0].agentStatus == .working)
        #expect(working[0].children[0].agentStatus == .done)
        let blocked = TreeComposer.updatingAgent("w1:p1", in: working) { $0.status = .blocked }
        #expect(blocked[0].agentStatus == .blocked)
        let childWorking = TreeComposer.updatingAgent("w2:p1", in: blocked) { $0.status = .working }
        #expect(childWorking[0].agentStatus == .blocked)
        #expect(childWorking[0].children[0].agentStatus == .working)
    }

    @Test func statusGoesOutAtOnceAndTheTreeAfterTheDebounce() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.emit(.agentStatus("w1:p1", .working, title: "rodando testes"))
            #expect(try await socket.nextMessage() == .agentStatus(agentId: "w1:p1", status: .working, title: "rodando testes"))
            harness.herdr.emit(.agentStatus("w1:p1", .blocked, title: nil))
            #expect(try await socket.nextMessage() == .agentStatus(agentId: "w1:p1", status: .blocked, title: "terminal-title"))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .milliseconds(149))
            #expect(socket.pendingCount == 0)
            harness.clock.advance(by: .milliseconds(1))
            let expected = TreeComposer.updatingAgent("w1:p1", in: Sample.defaultTree) { $0.status = .blocked }
            #expect(try await socket.nextMessage() == .treeChanged(workspaces: expected))
            #expect(expected[0].agentStatus == .blocked)
        }
    }

    @Test func agentStatusCarriesTheAiTitle() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.fullMeta, forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.emit(.agentStatus("w1:p1", .working, title: "✳ terminal"))
            #expect(try await socket.nextMessage() == .agentStatus(agentId: "w1:p1", status: .working, title: "herdr-sidebar abre arquivos"))
        }
    }

    @Test func chatMetaGoesOutOnlyWhenTheChatMetaChanges() async throws {
        let tree = [Sample.workspace("w1", tabs: [TabNode(id: "w1:t1", title: "Claude", agents: [Sample.agent("w1:p1", status: .working, sessionId: Sample.sessionA)])])]
        try await withHub(tree: tree, configure: { transcripts in
            await transcripts.setMeta(Self.fullMeta, forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            guard case .chatPage(let page) = try await socket.reply(to: .openChat(target: .agent("w1:p1"))) else {
                Issue.record("expected a chat page")
                return
            }
            #expect(page.meta.status == .working)
            await harness.transcripts.waitForSubscribers(2, forSession: Sample.sessionA)

            var previewOnly = Self.fullMeta
            previewOnly.preview = MessagePreview(author: .user, text: "e agora?")
            previewOnly.contextTokens = 120_000
            await harness.transcripts.publishMeta(previewOnly, toSession: Sample.sessionA)
            var renamed = previewOnly
            renamed.title = "novo-titulo"
            await harness.transcripts.publishMeta(renamed, toSession: Sample.sessionA)
            let expected = ChatMeta(title: "novo-titulo", workspaceLabel: "Core", model: "claude-opus-5-5", branch: "development", status: .working, permissionMode: "auto")
            #expect(try await socket.nextMessage() == .chatMeta(target: .agent("w1:p1"), meta: expected))

            harness.herdr.emit(.agentStatus("w1:p1", .idle, title: nil))
            #expect(try await socket.nextMessage() == .agentStatus(agentId: "w1:p1", status: .idle, title: "novo-titulo"))
            var idle = expected
            idle.status = .idle
            #expect(try await socket.nextMessage() == .chatMeta(target: .agent("w1:p1"), meta: idle))
            #expect(socket.pendingCount == 0)
        }
    }

    @Test func severalSubscriptionsToOneSessionNeverRewindTheMeta() async throws {
        let tree = [Sample.workspace("w1", tabs: [TabNode(id: "w1:t1", title: "Claude", agents: [Sample.agent("w1:p1", status: .working, sessionId: Sample.sessionA)])])]
        try await withHub(tree: tree, configure: { transcripts in
            await transcripts.setMeta(Self.fullMeta, forSession: Sample.sessionA)
        }) { harness in
            let (first, _) = try await harness.pairedClient(name: "iPhone")
            let (second, _) = try await harness.pairedClient(name: "iPad")
            _ = try await first.reply(to: .openChat(target: .agent("w1:p1")))
            _ = try await second.reply(to: .openChat(target: .agent("w1:p1")))
            _ = try await second.reply(to: .openChat(target: .session(Sample.sessionA)), id: "c-2")
            await harness.transcripts.waitForSubscribers(4, forSession: Sample.sessionA)

            let titles = (1...12).map { "titulo-\($0)" }
            for title in titles {
                var meta = Self.fullMeta
                meta.title = title
                await harness.transcripts.publishMeta(meta, toSession: Sample.sessionA)
            }
            for title in titles {
                guard case .chatMeta(let target, let meta) = try await first.nextMessage() else {
                    Issue.record("expected chatMeta \(title)")
                    return
                }
                #expect(target == .agent("w1:p1"))
                #expect(meta.title == title)
            }
            var secondTitles: [String: [String]] = [:]
            for _ in 0..<(titles.count * 2) {
                guard case .chatMeta(let target, let meta) = try await second.nextMessage() else {
                    Issue.record("expected chatMeta")
                    return
                }
                secondTitles[target == .agent("w1:p1") ? "agent" : "session", default: []].append(meta.title)
            }
            #expect(secondTitles == ["agent": titles, "session": titles])
            #expect(try await first.reply(to: .ping, id: "c-9") == .pong)
            #expect(try await second.reply(to: .ping, id: "c-9") == .pong)
        }
    }

    @Test func sessionChangeUpdatesTheTreeAndMovesTheOpenChat() async throws {
        var newMeta = Self.fullMeta
        newMeta.title = "sessao-nova"
        newMeta.preview = nil
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.fullMeta, forSession: Sample.sessionA)
            await transcripts.setMeta(newMeta, forSession: Sample.sessionB)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionA)

            harness.herdr.setAgent(HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: Sample.sessionB))
            harness.herdr.emit(.sessionChanged("w1:p1", sessionId: Sample.sessionB))
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionB)
            await harness.transcripts.waitForSubscribers(0, forSession: Sample.sessionA)
            guard case .chatMeta(let target, let meta) = try await socket.nextMessageSkippingArchived() else {
                Issue.record("expected chatMeta")
                return
            }
            #expect(target == .agent("w1:p1"))
            #expect(meta.title == "sessao-nova")

            try await harness.advanceTreeDebounce()
            guard case .treeChanged(let tree) = try await socket.nextMessageSkippingArchived() else {
                Issue.record("expected treeChanged")
                return
            }
            let agent = try #require(TreeComposer.agent("w1:p1", in: tree))
            #expect(agent.sessionId == Sample.sessionB)
            #expect(agent.title == "sessao-nova")
            #expect(agent.preview == nil)

            let item = Sample.item("n1", text: "depois do /clear")
            await harness.transcripts.emit(.append([item]), toSession: Sample.sessionB)
            #expect(try await socket.nextMessageSkippingArchived() == .chatAppend(target: .agent("w1:p1"), items: [item]))
        }
    }

    @Test func movedPaneKeepsTheChatAndTranslatesOldIds() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            harness.herdr.movePane(from: "w1:p1", to: "w3:p1")
            try await harness.advanceTreeDebounce()
            guard case .treeChanged(let tree) = try await socket.nextMessage() else {
                Issue.record("expected treeChanged")
                return
            }
            #expect(TreeComposer.agent("w3:p1", in: tree)?.sessionId == Sample.sessionA)
            #expect(TreeComposer.agent("w1:p1", in: tree) == nil)
            #expect(try await eventually { harness.herdr.openChatsCalls.last == ["w3:p1"] ? true : nil })

            #expect(try await socket.reply(to: .sendPrompt(agentId: "w1:p1", text: "continua"), id: "c-2") == .ack())
            #expect(harness.herdr.promptCalls == [FakeHerdrPromptCall(agentId: "w3:p1", text: "continua")])
            let item = Sample.item("m1", text: "movido")
            await harness.transcripts.emit(.append([item]), toSession: Sample.sessionA)
            #expect(try await socket.nextMessage() == .chatAppend(target: .agent("w3:p1"), items: [item]))
            #expect(try await socket.reply(to: .closeChat(target: .agent("w1:p1")), id: "c-3") == .ack())
            await harness.transcripts.waitForSubscribers(0, forSession: Sample.sessionA)
        }
    }

    @Test func unavailableHerdrKeepsTheLastTreeAndRejectsCommands() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setAvailable(false)
            #expect(try await socket.nextMessage() == .herdrStatus(connected: false))
            #expect(try await socket.reply(to: .sendPrompt(agentId: "w1:p1", text: "oi")).errorCode == .herdrUnavailable)
            #expect(try await socket.reply(to: .interrupt(agentId: "w1:p1")).errorCode == .herdrUnavailable)
            #expect(harness.herdr.promptCalls.isEmpty)

            let (late, helloOk) = try await harness.pairedClient()
            #expect(helloOk.host.herdrConnected == false)
            #expect(late.initialTree == Sample.defaultTree)
            guard case .chatPage = try await late.reply(to: .openChat(target: .agent("w1:p1"))) else {
                Issue.record("expected a chat page from the last known tree")
                return
            }

            harness.herdr.setAvailable(true)
            #expect(try await socket.nextMessage() == .herdrStatus(connected: true))
            #expect(try await late.nextMessage() == .herdrStatus(connected: true))
        }
    }
}
