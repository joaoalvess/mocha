import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

@Suite
struct ClaudeImageParsingTests {
    private typealias L = TranscriptLines

    private static let cwd = "/Users/dev/projects/demo-app"

    private func onlyItem(_ lines: [String], sourceLocation: SourceLocation = #_sourceLocation) throws -> ChatItem {
        let document = L.document(lines)
        #expect(document.items.count == 1, sourceLocation: sourceLocation)
        return try #require(document.items.first, sourceLocation: sourceLocation)
    }

    private func read(_ path: String, id: String = "t1") -> String {
        L.toolUse("Read", id: id, input: ["file_path": path])
    }

    @Test func assistantTextGetsTheMentionedPathsWithTheLineCwd() throws {
        let item = try onlyItem([L.assistant([["type": "text", "text": "Atualizei `docs/tela-login.png` e /tmp/b.jpg."]])])
        #expect(item.kind == .assistantText(markdown: "Atualizei `docs/tela-login.png` e /tmp/b.jpg."))
        #expect(item.imagePaths == ["\(Self.cwd)/docs/tela-login.png", "/tmp/b.jpg"])
    }

    @Test func assistantTextWithoutCwdKeepsOnlyAbsoluteAndHomePaths() throws {
        let item = try onlyItem([L.assistant([["type": "text", "text": "`docs/a.png` `/tmp/b.png` `~/Desktop/c.png`"]], extra: ["cwd": NSNull()])])
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop/c.png").standardized.path(percentEncoded: false)
        #expect(item.imagePaths == ["/tmp/b.png", home])
    }

    @Test func assistantTextWithoutMentionsHasNoPaths() throws {
        let item = try onlyItem([L.assistant([["type": "text", "text": "Pronto, rodei os testes."]])])
        #expect(item.imagePaths.isEmpty)
    }

    @Test func onlyTheTextBlockOfAMessageGetsTheMentions() throws {
        let document = L.document([L.assistant([
            ["type": "text", "text": "Vou abrir `docs/a.png`"],
            ["type": "tool_use", "id": "t1", "name": "Bash", "input": ["command": "open docs/a.png"]],
        ])])
        #expect(document.items.map(\.imagePaths) == [["\(Self.cwd)/docs/a.png"], []])
    }

    @Test func readOfAnImageGetsItsPath() throws {
        let path = "\(Self.cwd)/docs/tela-login.png"
        let item = try onlyItem([read(path)])
        guard case .toolCall(let call) = item.kind else {
            Issue.record("não é toolCall")
            return
        }
        #expect(call.name == "Read")
        #expect(call.summary == "docs/tela-login.png")
        #expect(item.imagePaths == [path])
        #expect(try onlyItem([read("/tmp/Print.HEIC")]).imagePaths == ["/tmp/Print.HEIC"])
    }

    @Test func readOfOtherFilesHasNoPath() throws {
        #expect(try onlyItem([read("\(Self.cwd)/src/a.txt")]).imagePaths.isEmpty)
        #expect(try onlyItem([read("docs/relativo.png")]).imagePaths.isEmpty)
        #expect(try onlyItem([L.toolUse("Write", id: "t1", input: ["file_path": "/tmp/a.png", "content": "x"])]).imagePaths.isEmpty)
        #expect(try onlyItem([L.toolUse("Bash", id: "t1", input: ["command": "open /tmp/a.png"])]).imagePaths.isEmpty)
    }

    @Test func readFromTheUploadsFolderHasNoPath() throws {
        let upload = ImageMarkers.uploadsDirectory + "5B0E7C1A-3F2D-4E8B-9A61-7C4D2E9F8B30.jpg"
        #expect(try onlyItem([read(upload)]).imagePaths.isEmpty)
    }

    @Test func readPathSurvivesTheToolResult() throws {
        let path = "/tmp/shots/tela.png"
        let document = L.document([
            read(path),
            L.toolResult("t1", content: [["type": "image", "source": ["type": "base64", "data": "AAAA"]]]),
        ])
        let item = try #require(document.items.first)
        guard case .toolCall(let call) = item.kind else {
            Issue.record("não é toolCall")
            return
        }
        #expect(call.status == .succeeded)
        #expect(item.imagePaths == [path])
    }

    @Test func toolResultUpdateCarriesThePath() throws {
        let path = "/tmp/shots/tela.png"
        var reducer = TranscriptReducer()
        let appended = reducer.apply(TranscriptLineParser.parse(Array(read(path).utf8), offset: 0))
        let updated = reducer.apply(TranscriptLineParser.parse(Array(L.toolResult("t1", content: "ok").utf8), offset: 100))
        guard case .append(let first) = try #require(appended.first), case .update(let second) = try #require(updated.first) else {
            Issue.record("mudanças inesperadas: \(appended) \(updated)")
            return
        }
        #expect(first.imagePaths == [path])
        #expect(second.id == first.id)
        #expect(second.imagePaths == [path])
        guard case .toolCall(let call) = second.kind else {
            Issue.record("não é toolCall")
            return
        }
        #expect(call.status == .succeeded)
    }
}
