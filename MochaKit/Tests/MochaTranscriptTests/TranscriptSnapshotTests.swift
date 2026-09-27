import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaTranscript

@Suite
struct TranscriptSnapshotTests {
    private static var isUpdating: Bool {
        ProcessInfo.processInfo.environment["MOCHA_UPDATE_SNAPSHOTS"] == "1"
    }

    @Test(arguments: TranscriptFixtures.snapshotNames)
    func fixtureMatchesExpectedSnapshot(_ name: String) throws {
        let snapshot = TranscriptSnapshot(document: try TranscriptFixtures.document(name))
        if Self.isUpdating {
            let url = TranscriptFixtures.expectedURL(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try snapshot.encoded().write(to: url, options: .atomic)
        }
        let expected = try TranscriptFixtures.expectedSnapshot(name)
        #expect(snapshot.meta == expected.meta)
        #expect(snapshot.stats == expected.stats)
        #expect(snapshot.items.count == expected.items.count)
        for (produced, stored) in zip(snapshot.items, expected.items) {
            #expect(produced == stored)
        }
    }

    @Test(arguments: TranscriptFixtures.snapshotNames)
    func snapshotSequenceMatchesReadme(_ name: String) throws {
        let row = try #require(try FixtureReadme.rows()["\(name).jsonl"])
        let items = try TranscriptFixtures.expectedSnapshot(name).items
        #expect(items.count == row.expectedItems.count, "\(name): \(items.count) itens, README tem \(row.expectedItems.count)")
        for (index, (token, item)) in zip(row.expectedItems, items).enumerated() {
            if let problem = FixtureReadme.mismatch(token: token, item: item) {
                Issue.record("\(name) item \(index): \(problem)")
            }
        }
    }

    @Test(arguments: TranscriptFixtures.snapshotNames)
    func snapshotMetaMatchesReadme(_ name: String) throws {
        let row = try #require(try FixtureReadme.rows()["\(name).jsonl"])
        let meta = try TranscriptFixtures.expectedSnapshot(name).meta
        let produced: [String: String?] = [
            "título": meta.title,
            "modelo": meta.model,
            "branch": meta.branch,
            "modo": meta.permissionMode,
        ]
        for (key, value) in row.finalMeta {
            #expect(produced[key] == value, "\(name): \(key)")
        }
    }

    @Test func snapshotsEncodeItemsWithProtocolCoding() throws {
        let data = try Data(contentsOf: TranscriptFixtures.expectedURL("tool-calls"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try #require(object["items"] as? [[String: Any]])
        let toolCall = try #require(items.first { $0["type"] as? String == "toolCall" })
        #expect(toolCall["toolUseId"] is String)
        #expect(toolCall["status"] as? String == "failed")
        #expect((toolCall["at"] as? String)?.hasSuffix("Z") == true)
        #expect(toolCall["kind"] == nil)
    }
}
