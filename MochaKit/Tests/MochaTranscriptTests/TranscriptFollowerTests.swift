import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaTranscript

final class TemporaryTranscript {
    let directory: URL
    let url: URL

    init(contents: [UInt8] = []) throws {
        directory = URL.temporaryDirectory.appending(path: "mocha-transcript-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "session.jsonl")
        try Data(contents).write(to: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    var path: String {
        url.path(percentEncoded: false)
    }

    func append(_ bytes: some Collection<UInt8>) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(bytes))
    }
}

enum ChunkPlan {
    static let sizes = [1, 17, 211, 1_024, 4_096, 333, 50, 2_900]

    static func chunks(of bytes: [UInt8]) -> [ArraySlice<UInt8>] {
        var chunks: [ArraySlice<UInt8>] = []
        var start = 0
        var step = 0
        while start < bytes.count {
            let end = min(bytes.count, start + sizes[step % sizes.count])
            chunks.append(bytes[start..<end])
            start = end
            step += 1
        }
        return chunks
    }
}

@Suite
struct TranscriptFollowerTests {
    @Test(arguments: ["clear-and-compact", "tool-calls"])
    func chunkedWritesProduceTheSameChangesAsTheFullRead(_ name: String) throws {
        let document = try TranscriptFixtures.document(name)
        let bytes = try TranscriptFixtures.bytes(name)
        let transcript = try TemporaryTranscript()
        let follower = try TranscriptFollower(path: transcript.path, start: .beginningOfFile)
        var changes: [TranscriptChange] = []
        var list = ChatItemList()
        var cutLines = 0
        for chunk in ChunkPlan.chunks(of: bytes) {
            try transcript.append(chunk)
            let update = try follower.readAppendedLines()
            if follower.pendingByteCount > 0 { cutLines += 1 }
            for change in update.changes {
                let applied = list.apply(change)
                #expect(applied, "update de item desconhecido: \(change.item.id)")
            }
            changes.append(contentsOf: update.changes)
        }
        #expect(cutLines > 0)
        #expect(changes == document.changes)
        #expect(list.items == document.items)
        #expect(follower.header == document.header)
        #expect(follower.pendingByteCount == 0)
        #expect(changes.contains { if case .update = $0 { true } else { false } })
    }

    @Test func followingExistingLinesContinuesFromThePage() throws {
        let document = try TranscriptFixtures.document("tool-calls")
        let bytes = try TranscriptFixtures.bytes("tool-calls")
        let cut = try #require(try FixtureLines.offsets(of: "tool-calls", containing: "A4nrNC\",\"type\":\"tool_result\"").first)
        let transcript = try TemporaryTranscript(contents: Array(bytes[..<Int(cut)]))
        let follower = try TranscriptFollower(path: transcript.path, start: .afterExistingLines)
        var list = ChatItemList(try follower.lastPage(limit: 500).items)
        try transcript.append(bytes[Int(cut)...])
        let update = try follower.readAppendedLines()
        guard case .update(let first) = update.changes.first, case .toolCall(let call) = first.kind else {
            Issue.record("a primeira mudança deveria ser o resultado do Bash")
            return
        }
        #expect(call.name == "Bash")
        #expect(call.status == .succeeded)
        for change in update.changes {
            let applied = list.apply(change)
            #expect(applied)
        }
        #expect(list.items == document.items)
        #expect(follower.header == document.header)
    }

    @Test func malformedEndsWithDroppedLinesPartialLineAndUnknowns() throws {
        let document = try TranscriptFixtures.document("malformed")
        #expect(document.statistics.dropped == 2)
        #expect(document.statistics.orphanResults == 1)
        #expect(document.statistics.unknown == [
            "type:future-thing": 1,
            "subtype:future_notice": 1,
            "block:server_tool_use": 1,
            "block:document": 1,
        ])
        #expect(document.pendingByteCount > 0)
        #expect(!document.items.contains { $0.kind == .assistantText(markdown: "parcial") })

        let transcript = try TemporaryTranscript(contents: try TranscriptFixtures.bytes("malformed"))
        let follower = try TranscriptFollower(path: transcript.path, start: .afterExistingLines)
        #expect(follower.pendingByteCount == document.pendingByteCount)
        #expect(try follower.lastPage(limit: 500).items == document.items)
        try transcript.append(Array("\"}]},\"uuid\":\"fim\"}\n".utf8))
        let update = try follower.readAppendedLines()
        #expect(update.changes.map(\.item.kind) == [.assistantText(markdown: "parcial")])
        #expect(follower.pendingByteCount == 0)
    }

    @Test func unknownNamesAreReportedPerBatch() throws {
        let transcript = try TemporaryTranscript()
        let follower = try TranscriptFollower(path: transcript.path, start: .beginningOfFile)
        try transcript.append(Array((TranscriptLines.json(["type": "coisa-nova"]) + "\n").utf8))
        #expect(try follower.readAppendedLines().unknownNames == ["type:coisa-nova"])
    }
}

@Suite
struct TranscriptHeaderScannerTests {
    @Test(arguments: TranscriptFixtures.names)
    func headerFromTheEndMatchesTheFullRead(_ name: String) throws {
        let header = try TranscriptHeaderScanner.header(ofFileAt: TranscriptFixtures.path(name))
        #expect(header == (try TranscriptFixtures.document(name)).header)
    }

    @Test func headerScanCrossesChunkBoundaries() throws {
        var lines = [
            TranscriptLines.json(["type": "ai-title", "aiTitle": "Título antigo"]),
            TranscriptLines.json(["type": "permission-mode", "permissionMode": "plan"]),
            TranscriptLines.assistant([["type": "text", "text": "oi"]], model: "claude-opus-5-5", branch: "main"),
        ]
        lines.append(TranscriptLines.user([["type": "image", "source": ["data": String(repeating: "A", count: 700_000)]]]))
        for index in 0..<2_000 {
            lines.append(TranscriptLines.json(["type": "mode", "mode": "normal", "n": index]))
        }
        lines.append(TranscriptLines.user(String(repeating: "texto longo ", count: 40_000)))
        lines.append(TranscriptLines.json(["type": "last-prompt", "version": "2.1.283"]))
        let transcript = try TemporaryTranscript(contents: Array((lines.joined(separator: "\n") + "\n{\"partial").utf8))
        let header = try TranscriptHeaderScanner.header(ofFileAt: transcript.path)
        #expect(header == TranscriptHeader(
            title: "Título antigo",
            model: "claude-opus-5-5",
            branch: "main",
            permissionMode: "plan",
            claudeVersion: "2.1.283"
        ))
        #expect(header == (try TranscriptDocument.read(path: transcript.path)).header)
    }

    @Test func missingFileThrowsNotFound() {
        #expect(throws: TranscriptFileError.notFound) {
            try TranscriptHeaderScanner.header(ofFileAt: "/tmp/mocha-nao-existe-\(UUID().uuidString).jsonl")
        }
    }
}
