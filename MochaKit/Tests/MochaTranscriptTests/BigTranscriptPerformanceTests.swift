import Foundation
import MochaTestSupport
import MochaTranscript
import Testing

@Suite(.tags(.integration), .enabled(if: IntegrationGate.isEnabled))
struct BigTranscriptPerformanceTests {
    @Test func firstPageOfFiftyMegabytesTakesLessThan300Milliseconds() throws {
        let path = TranscriptFixtures.bigFixture.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            Issue.record("Fixture grande ausente em \(path). Gere com: swift scripts/gen-big-transcript.swift")
            return
        }
        let clock = ContinuousClock()
        var slice = TranscriptPageSlice.empty
        var header = TranscriptHeader()
        let elapsed = try clock.measure {
            let follower = try TranscriptFollower(path: path, start: .afterExistingLines)
            slice = try follower.lastPage(limit: 60)
            header = follower.header
        }
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        print("big-50mb.jsonl: primeira página (60 itens) em \(String(format: "%.1f", milliseconds)) ms")
        #expect(slice.items.count >= 60)
        #expect(slice.hasMore)
        #expect(header.title != nil)
        #expect(header.model != nil)
        #expect(elapsed < .milliseconds(300))
    }
}
