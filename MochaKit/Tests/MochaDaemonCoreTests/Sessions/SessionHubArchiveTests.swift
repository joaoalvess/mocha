import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubArchiveTests {
    static let meta = TranscriptMeta(
        title: "Paginação do chat",
        model: "claude-opus-5-5",
        lastModified: Sample.start.addingTimeInterval(-60),
        preview: MessagePreview(author: .assistant, text: "Pronto, os testes passaram."),
        contextTokens: 100_000,
        sessionStartedAt: Sample.start.addingTimeInterval(-3600),
        turnStartedAt: Sample.start.addingTimeInterval(-300),
        turnEndedAt: Sample.start.addingTimeInterval(-60)
    )

    static let expectedRecord = ArchivedSession(
        id: Sample.sessionA,
        agentId: "w1:p1",
        title: "Paginação do chat",
        workspaceLabel: "Core",
        model: "claude-opus-5-5",
        branch: "feature/foreground",
        preview: MessagePreview(author: .assistant, text: "Pronto, os testes passaram."),
        contextLeftPercent: 90,
        reason: .cleared,
        endedAt: Sample.start,
        sessionStartedAt: Sample.start.addingTimeInterval(-3600),
        lastActivityAt: Sample.start.addingTimeInterval(-60)
    )

    static func archivedRecord(_ id: String, workspaceLabel: String = "anotacoes") -> ArchivedSession {
        ArchivedSession(id: id, title: "Rascunho", workspaceLabel: workspaceLabel, reason: .ended, endedAt: Sample.start.addingTimeInterval(-600))
    }

    static func treeWithout(_ agentId: AgentID) -> [WorkspaceNode] {
        Sample.defaultTree.map { workspace in
            var workspace = workspace
            workspace.tabs = workspace.tabs.map { tab in
                var tab = tab
                tab.agents.removeAll { $0.id == agentId }
                return tab
            }
            return workspace
        }
    }

    static func nextArchived(_ socket: TestClientSocket) async throws -> [ArchivedSession] {
        let message = try await socket.nextMessage { message in
            if case .archived = message {
                return true
            }
            return false
        }
        guard case .archived(let sessions) = message else { throw UnexpectedMessage(message: message) }
        return sessions
    }

    @Test func helloSendsTheArchivedListRightAfterTheTree() async throws {
        let archive = FakeSessionArchive(sessions: [Self.archivedRecord(Sample.sessionC)])
        try await withHub(archive: archive) { harness async throws in
            let code = await harness.pairing.issueCode(url: Sample.pairingURL)
            let socket = harness.connect()
            try socket.deliver(.hello(HelloPayload(pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0")), id: "hello-1")
            let helloOk = try await socket.next()
            let tree = try await socket.next()
            let archived = try await socket.next()
            guard case .helloOk = helloOk.message, case .tree = tree.message else { throw UnexpectedMessage(message: tree.message) }
            #expect(archived.id == nil)
            #expect(archived.message == .archived(sessions: [Self.archivedRecord(Sample.sessionC)]))
            #expect(try await socket.reply(to: .ping, id: "c-1") == .pong)
        }
    }

    @Test func clearArchivesTheOldSessionAsClearedWithTheLastSummary() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.meta, forSession: Sample.sessionA)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setAgent(HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: Sample.sessionB))
            harness.herdr.emit(.sessionChanged("w1:p1", sessionId: Sample.sessionB))

            #expect(try await Self.nextArchived(socket) == [Self.expectedRecord])
            #expect(harness.archive.endedCalls == [Self.expectedRecord])
        }
    }

    @Test func closedPaneArchivesItsSessionAsEnded() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.meta, forSession: Sample.sessionA)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setTree(Self.treeWithout("w1:p1"))

            var expected = Self.expectedRecord
            expected.reason = .ended
            #expect(try await Self.nextArchived(socket) == [expected])
        }
    }

    @Test func claudeLeavingThePaneArchivesTheSessionAsEnded() async throws {
        try await withHub { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setTree(TreeComposer.updatingAgent("w1:p1", in: Sample.defaultTree) { $0.sessionId = nil })

            let sessions = try await Self.nextArchived(socket)
            #expect(sessions.map(\.id) == [Sample.sessionA])
            #expect(sessions.first?.reason == .ended)
            #expect(sessions.first?.title == "terminal-title")
        }
    }

    @Test func unavailableHerdrDoesNotArchive() async throws {
        try await withHub { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.setAvailable(false)
            #expect(try await socket.nextMessage() == .herdrStatus(connected: false))
            harness.herdr.setTree(Self.treeWithout("w1:p1"))
            try await harness.advanceTreeDebounce()
            guard case .treeChanged = try await socket.nextMessage() else {
                Issue.record("expected treeChanged")
                return
            }
            #expect(try await socket.reply(to: .ping, id: "c-2") == .pong)
            #expect(harness.archive.endedCalls.isEmpty)

            harness.herdr.setAvailable(true)
            #expect(try await socket.nextMessage() == .herdrStatus(connected: true))
            let sessions = try await Self.nextArchived(socket)
            #expect(sessions.map(\.id) == [Sample.sessionA])
            #expect(sessions.first?.reason == .ended)
        }
    }

    @Test func movedPaneKeepsItsSessionOutOfTheArchive() async throws {
        try await withHub { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.movePane(from: "w1:p1", to: "w3:p1")
            try await harness.advanceTreeDebounce()
            guard case .treeChanged = try await socket.nextMessage() else {
                Issue.record("expected treeChanged")
                return
            }
            #expect(try await socket.reply(to: .ping, id: "c-2") == .pong)
            #expect(harness.archive.endedCalls.isEmpty)
        }
    }

    @Test func archivingTheCurrentSessionAcksAndSendsTheTreeWithArchivedAt() async throws {
        try await withHub { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.archivedAt == nil)
            harness.clock.advance(by: .seconds(5))

            #expect(try await socket.reply(to: .archive(sessionId: Sample.sessionA), id: "c-2") == .ack())
            let archivedAt = Sample.start.addingTimeInterval(5)
            #expect(harness.archive.archiveCalls == [FakeArchiveCall(sessionId: Sample.sessionA, date: archivedAt)])
            try await harness.advanceTreeDebounce()
            guard case .treeChanged(let tree) = try await socket.nextMessage() else {
                Issue.record("expected treeChanged")
                return
            }
            #expect(TreeComposer.agent("w1:p1", in: tree)?.archivedAt == archivedAt)

            let (late, _) = try await harness.pairedClient(name: "iPad")
            #expect(TreeComposer.agent("w1:p1", in: try #require(late.initialTree))?.archivedAt == archivedAt)
        }
    }

    @Test func archivingASessionThatIsNotCurrentIsSessionNotFound() async throws {
        try await withHub { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .archive(sessionId: Sample.sessionC)).errorCode == .sessionNotFound)
            #expect(try await socket.reply(to: .archive(sessionId: "nao-e-uuid"), id: "c-2").errorCode == .sessionNotFound)
            #expect(harness.archive.archiveCalls.isEmpty)
        }
    }

    @Test func aNewTurnClearsTheUserArchive() async throws {
        let tree = [Sample.workspace("w1", tabs: [TabNode(id: "w1:t1", title: "Claude", agents: [Sample.agent("w1:p1", status: .working, sessionId: Sample.sessionA)])])]
        let archivedAt = Sample.start.addingTimeInterval(-60)
        let archive = FakeSessionArchive(userArchived: [Sample.sessionA: archivedAt])
        try await withHub(tree: tree, archive: archive, configure: { transcripts in
            await transcripts.setMeta(Self.meta, forSession: Sample.sessionA)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.archivedAt == archivedAt)
            #expect(harness.archive.turnStartedCalls == [FakeArchiveCall(sessionId: Sample.sessionA, date: Sample.start.addingTimeInterval(-300))])
            await harness.transcripts.waitForSubscribers(1, forSession: Sample.sessionA)

            var newTurn = Self.meta
            newTurn.turnStartedAt = Sample.start
            newTurn.turnEndedAt = nil
            await harness.transcripts.publishMeta(newTurn, toSession: Sample.sessionA)
            let updated = try await eventually { () async -> [WorkspaceNode]? in
                harness.clock.advance(by: .milliseconds(150))
                while socket.pendingCount > 0 {
                    if case .treeChanged(let tree) = try? await socket.nextMessage(),
                        TreeComposer.agent("w1:p1", in: tree)?.turnStartedAt == Sample.start
                    {
                        return tree
                    }
                }
                return nil
            }
            #expect(TreeComposer.agent("w1:p1", in: updated)?.archivedAt == nil)
            #expect(harness.archive.turnStartedCalls.last == FakeArchiveCall(sessionId: Sample.sessionA, date: Sample.start))
            #expect(harness.archive.userArchived.isEmpty)
        }
    }

    @Test func resumedSessionLeavesTheArchivedList() async throws {
        let archive = FakeSessionArchive(sessions: [Self.archivedRecord(Sample.sessionA), Self.archivedRecord(Sample.sessionC)])
        try await withHub(archive: archive) { harness async throws in
            _ = try await eventually { harness.archive.resumedCalls.contains(Sample.sessionA) ? true : nil }
            _ = try await eventually { await harness.hub.archivedSessions.map(\.id) == [Sample.sessionC] ? true : nil }
            let (socket, _) = try await harness.pairedClient()
            #expect(socket.receivedMessages.contains(.archived(sessions: [Self.archivedRecord(Sample.sessionC)])))

            harness.herdr.setAgent(HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: Sample.sessionC))
            harness.herdr.emit(.sessionChanged("w1:p1", sessionId: Sample.sessionC))
            let sessions = try await eventually { () async -> [ArchivedSession]? in
                let current = harness.archive.currentSessions
                return current.map(\.id) == [Sample.sessionA] ? current : nil
            }
            #expect(sessions.first?.reason == .cleared)
            #expect(harness.archive.resumedCalls.first == Sample.sessionA)
            #expect(harness.archive.resumedCalls.contains(Sample.sessionC))
            _ = try await socket.nextMessage { $0 == .archived(sessions: sessions) }
        }
    }

    @Test func sessionChatTakesTheWorkspaceLabelFromTheArchive() async throws {
        let archive = FakeSessionArchive(sessions: [Self.archivedRecord(Sample.sessionC, workspaceLabel: "anotacoes")])
        try await withHub(archive: archive, configure: { transcripts in
            await transcripts.setMeta(TranscriptMeta(title: "Rascunho"), forSession: Sample.sessionC)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            guard case .chatPage(let page) = try await socket.reply(to: .openChat(target: .session(Sample.sessionC))) else {
                Issue.record("expected a chat page")
                return
            }
            #expect(page.meta.workspaceLabel == "anotacoes")
            #expect(page.meta.status == .unknown)

            harness.archive.setSessions([Self.archivedRecord(Sample.sessionC, workspaceLabel: "Core")])
            _ = try await Self.nextArchived(socket)
            guard case .chatMeta(let target, let meta) = try await socket.nextMessage() else {
                Issue.record("expected chatMeta")
                return
            }
            #expect(target == .session(Sample.sessionC))
            #expect(meta.workspaceLabel == "Core")
        }
    }
}
