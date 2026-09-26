import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubUsageTests {
    static let transcriptMeta = TranscriptMeta(model: "claude-opus-5-5", contextTokens: 250_000)

    static func snapshot(fetchedAt offset: TimeInterval = 0, fiveHour: Double = 12) -> UsageSnapshot {
        UsageSnapshot(
            plan: "Max 20x",
            account: "d•••@e•••.com",
            windows: [UsageWindow(kind: .fiveHour, usedPercent: fiveHour), UsageWindow(kind: .weekly, usedPercent: 71)],
            fetchedAt: UsageSample.fetchedAt.addingTimeInterval(offset)
        )
    }

    static func nextTree(
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

    @Test func helloSendsHelloOkTreeArchivedAndUsageInThisOrder() async throws {
        let usage = FakeUsageProvider(snapshot: Self.snapshot())
        let archived = ArchivedSession(id: Sample.sessionC, title: "Rascunho", workspaceLabel: "anotacoes", reason: .ended, endedAt: Sample.start)
        try await withHub(usage: usage, archive: FakeSessionArchive(sessions: [archived])) { harness async throws in
            let code = await harness.pairing.issueCode(url: Sample.pairingURL)
            let socket = harness.connect()
            try socket.deliver(.hello(HelloPayload(pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0")), id: "hello-1")
            var envelopes: [ServerEnvelope] = []
            for _ in 0..<4 {
                envelopes.append(try await socket.next())
            }
            #expect(envelopes.map(\.message.type) == ["helloOk", "tree", "archived", "usage"])
            #expect(envelopes.map(\.id) == ["hello-1", "hello-1", nil, nil])
            #expect(envelopes[2].message == .archived(sessions: [archived]))
            #expect(envelopes[3].message == .usage(Self.snapshot()))
        }
    }

    @Test func withoutTheCacheTheHelloHasNoUsage() async throws {
        try await withHub { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            #expect(socket.receivedMessages.map(\.type) == ["helloOk", "tree", "archived"])
            #expect(try await socket.reply(to: .ping, id: "c-1") == .pong)
        }
    }

    @Test func everyCacheChangeIsBroadcastAndAMissingCacheSendsNothing() async throws {
        let usage = FakeUsageProvider(snapshot: Self.snapshot())
        try await withHub(usage: usage) { harness async throws in
            let (first, _) = try await harness.pairedClient(name: "iPhone")
            let (second, _) = try await harness.pairedClient(name: "iPad")
            harness.usage.update(Self.snapshot(fetchedAt: 60, fiveHour: 20))
            #expect(try await first.nextMessage() == .usage(Self.snapshot(fetchedAt: 60, fiveHour: 20)))
            #expect(try await second.nextMessage() == .usage(Self.snapshot(fetchedAt: 60, fiveHour: 20)))

            harness.usage.update(nil)
            _ = try await eventually { await harness.hub.usageSnapshot == nil ? true : nil }
            #expect(try await first.reply(to: .ping, id: "c-1") == .pong)

            let (late, _) = try await harness.pairedClient(name: "Mac")
            #expect(late.receivedMessages.map(\.type) == ["helloOk", "tree", "archived"])
        }
    }

    @Test func pluginContextBeatsTheTranscript() async throws {
        let usage = FakeUsageProvider(snapshot: Self.snapshot(), contexts: [Sample.sessionA: 40])
        try await withHub(usage: usage, configure: { transcripts in
            await transcripts.setMeta(Self.transcriptMeta, forSession: Sample.sessionA)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.contextLeftPercent == 60)
        }
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(Self.transcriptMeta, forSession: Sample.sessionA)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            #expect(TreeComposer.agent("w1:p1", in: try #require(socket.initialTree))?.contextLeftPercent == 75)
        }
    }

    @Test func pluginContextChangeUpdatesTheTree() async throws {
        let usage = FakeUsageProvider(snapshot: Self.snapshot(), contexts: [Sample.sessionA: 40])
        try await withHub(usage: usage, configure: { transcripts in
            await transcripts.setMeta(Self.transcriptMeta, forSession: Sample.sessionA)
        }) { harness async throws in
            let (socket, _) = try await harness.pairedClient()
            harness.usage.update(Self.snapshot(fetchedAt: 60), contexts: [Sample.sessionA: 54.6])
            let tree = try await Self.nextTree(socket, harness: harness) {
                TreeComposer.agent("w1:p1", in: $0)?.contextLeftPercent == 45
            }
            #expect(TreeComposer.agent("w1:p1", in: tree)?.contextLeftPercent == 45)

            harness.usage.update(Self.snapshot(fetchedAt: 120), contexts: [:])
            _ = try await Self.nextTree(socket, harness: harness) {
                TreeComposer.agent("w1:p1", in: $0)?.contextLeftPercent == 75
            }
        }
    }

    @Test func pluginContextGoesIntoTheArchivedRecord() async throws {
        let usage = FakeUsageProvider(contexts: [Sample.sessionA: 81.5])
        try await withHub(usage: usage) { harness async throws in
            _ = try await harness.pairedClient()
            harness.herdr.setAgent(HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: Sample.sessionB))
            harness.herdr.emit(.sessionChanged("w1:p1", sessionId: Sample.sessionB))
            let record = try await eventually { harness.archive.endedCalls.first }
            #expect(record.contextLeftPercent == 19)
            #expect(record.reason == .cleared)
        }
    }
}
