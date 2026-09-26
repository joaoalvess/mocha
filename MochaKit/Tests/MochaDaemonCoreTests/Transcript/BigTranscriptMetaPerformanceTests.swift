import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

extension Tag {
    @Tag static var integration: Self
}

enum TranscriptIntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCHA_INTEGRATION"] == "1"
    }
}

@Suite(.tags(.integration), .enabled(if: TranscriptIntegrationGate.isEnabled))
struct BigTranscriptMetaPerformanceTests {
    @Test func metaOfFiftyMegabytesWithoutFollowingTakesLessThan50Milliseconds() async throws {
        let path = TranscriptFixtures.bigFixture.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            Issue.record("Fixture grande ausente em \(path). Gere com: swift scripts/gen-big-transcript.swift")
            return
        }
        let sandbox = try TranscriptSandbox()
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let session = TranscriptSession(sessionId: "big-50mb", transcriptPath: path)
        let clock = ContinuousClock()
        let start = clock.now
        let meta = await store.meta(forSession: session)
        let elapsed = clock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        print("big-50mb.jsonl: meta(forSession:) sem acompanhamento em \(String(format: "%.1f", milliseconds)) ms")
        #expect(meta?.title != nil)
        #expect(meta?.model != nil)
        #expect(meta?.preview != nil)
        #expect(meta?.activity != nil)
        #expect(meta?.contextTokens != nil)
        #expect(meta?.sessionStartedAt != nil)
        #expect(meta?.turnStartedAt != nil)
        #expect(meta?.turnEndedAt != nil)
        #expect(await store.isActive(forSession: "big-50mb") == false)
        #expect(elapsed < .milliseconds(50))
    }
}
