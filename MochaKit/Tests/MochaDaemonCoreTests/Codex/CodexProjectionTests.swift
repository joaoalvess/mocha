import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexProjectionTests {
    @Test func mapsThreadPageAndPreservesItemIdentity() throws {
        let raw = try OrderedJSON.parse(Fixtures.data("codex/thread-page.json"))
        let page = try #require(CodexProjection.page(thread: raw["thread"] ?? .null, turns: raw["turns"] ?? .null))

        #expect(page.threadId == "01900000-0000-7000-8000-000000000001")
        #expect(page.status == .working)
        #expect(page.activeTurnId == "turn-2")
        #expect(page.before == "older-1")
        #expect(page.items.map(\.id) == ["user-1", "agent-1", "collab-1", "user-2", "command-2"])
        #expect(page.items[2].kind.type == "subagent")
        #expect(page.items[3].kind == .userPrompt(text: "Verifique este arquivo", imageCount: 1))
    }

    @Test func planItemBecomesAPlanAndAgentMessageStaysText() throws {
        let at = Date(timeIntervalSince1970: 1_790_337_600)
        let plan = try OrderedJSON.parse(Data(#"{"type":"plan","id":"plan-1","text":"1. Ler o README"}"#.utf8))
        let message = try OrderedJSON.parse(Data(#"{"type":"agentMessage","id":"agent-1","text":"Pronto."}"#.utf8))

        #expect(CodexProjection.item(plan, at: at)?.kind == .plan(markdown: "1. Ler o README"))
        #expect(CodexProjection.item(message, at: at)?.kind == .assistantText(markdown: "Pronto."))
    }

    @Test func usesDurationAndResetReturnedByCodex() throws {
        let raw = try OrderedJSON.parse(Fixtures.data("codex/rate-limits.json"))
        let snapshot = try #require(CodexProjection.usage(raw))

        #expect(snapshot.provider == .codex)
        #expect(snapshot.windows.map(\.windowDurationMins) == [300, 10080])
        #expect(snapshot.windows.map(\.usedPercent) == [41.5, 16])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1780003000))
    }

    @Test func imagePathsMustBeFilesFromMochaUploads() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-codex-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appending(path: "upload.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)

        let input = try CodexService.promptInput("Analise\n[imagem: \(image.path)]", uploadsDirectory: directory)
        #expect(input.count == 2)
        #expect(input[0]["type"]?.stringValue == "text")
        #expect(input[1]["type"]?.stringValue == "localImage")
        #expect(input[1]["path"]?.stringValue == image.path)

        #expect(throws: CodexServiceError.invalidImage) {
            try CodexService.promptInput("[imagem: /etc/passwd]", uploadsDirectory: directory)
        }
    }
}
