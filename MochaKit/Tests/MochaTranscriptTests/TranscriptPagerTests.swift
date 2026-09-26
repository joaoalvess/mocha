import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaTranscript

enum FixtureLines {
    static func offsets(of name: String, containing marker: String) throws -> [UInt64] {
        let bytes = try TranscriptFixtures.bytes(name)
        var offsets: [UInt64] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            let line = String(decoding: bytes[start..<index], as: UTF8.self)
            if line.contains(marker) { offsets.append(UInt64(start)) }
            start = index + 1
        }
        return offsets
    }
}

@Suite
struct TranscriptPagerTests {
    private static let limits = [1, 3, 7, 60]

    @Test(arguments: TranscriptFixtures.names, limits)
    func walkingPagesBackwardRebuildsTheFullRead(_ name: String, limit: Int) throws {
        let document = try TranscriptFixtures.document(name)
        let reader = try TranscriptPageReader(path: TranscriptFixtures.path(name))
        var slice = try reader.lastPage(limit: limit)
        var pages = [slice.items]
        while slice.hasMore {
            let offset = try #require(slice.firstLineOffset)
            slice = try #require(try reader.page(beforeOffset: offset, limit: limit))
            pages.append(slice.items)
        }
        let combined = pages.reversed().flatMap { $0 }
        #expect(combined.count == document.items.count)
        #expect(combined == document.items)
        #expect(pages.dropLast().allSatisfy { $0.count >= limit - 1 })
    }

    @Test func lastPageHoldsTheNewestItems() throws {
        let document = try TranscriptFixtures.document("tool-calls")
        let slice = try TranscriptPageReader(path: TranscriptFixtures.path("tool-calls")).lastPage(limit: 5)
        #expect(slice.items == Array(document.items.suffix(5)))
        #expect(slice.hasMore)
        #expect(slice.firstLineOffset != nil)
    }

    @Test func wholeFilePageHasNoMore() throws {
        let document = try TranscriptFixtures.document("basic-turn")
        let slice = try TranscriptPageReader(path: TranscriptFixtures.path("basic-turn")).lastPage(limit: 500)
        #expect(slice.items == document.items)
        #expect(!slice.hasMore)
    }

    @Test func pageEndingInTheMiddleOfToolCallsAppliesLaterToolResults() throws {
        let reader = try TranscriptPageReader(path: TranscriptFixtures.path("tool-calls"))
        let readResult = try #require(try FixtureLines.offsets(of: "tool-calls", containing: "EFPuYc\",\"type\":\"tool_result\"").first)
        let slice = try #require(try reader.page(beforeOffset: readResult, limit: 3))
        guard case .toolCall(let read) = slice.items.last?.kind else {
            Issue.record("a página deveria terminar no Read")
            return
        }
        #expect(read.name == "Read")
        #expect(read.status == .succeeded)
        #expect(read.resultPreview?.hasPrefix("1\texport function login") == true)

        let bashResult = try #require(try FixtureLines.offsets(of: "tool-calls", containing: "7VU9xB\",\"type\":\"tool_result\"").first)
        let firstPage = try #require(try reader.page(beforeOffset: bashResult, limit: 10))
        guard case .toolCall(let bash) = firstPage.items.last?.kind else {
            Issue.record("a página deveria terminar no Bash")
            return
        }
        #expect(bash.status == .failed)
        #expect(!firstPage.hasMore)
    }

    @Test func offsetsThatAreNotLineStartsAreRejected() throws {
        let reader = try TranscriptPageReader(path: TranscriptFixtures.path("basic-turn"))
        let second = try #require(reader.lineOffsets.dropFirst().first)
        #expect(try reader.page(beforeOffset: second + 1, limit: 5) == nil)
        #expect(try reader.page(beforeOffset: 999_999_999, limit: 5) == nil)
        #expect(try reader.page(beforeOffset: second, limit: 5) != nil)
    }

    @Test func missingFileThrowsNotFound() {
        #expect(throws: TranscriptFileError.notFound) {
            try TranscriptPageReader(path: "/tmp/mocha-nao-existe-\(UUID().uuidString).jsonl")
        }
    }
}
