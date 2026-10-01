import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

@Suite
struct PastedContentTests {
    private typealias L = TranscriptLines

    private static let uploads = ImageMarkers.uploadsDirectory

    private func onlyPrompt(_ content: Any, sourceLocation: SourceLocation = #_sourceLocation) throws -> (text: String, imageCount: Int, imagePaths: [String]) {
        let document = L.document([L.user(content)])
        #expect(document.items.count == 1, sourceLocation: sourceLocation)
        let item = try #require(document.items.first, sourceLocation: sourceLocation)
        guard case .userPrompt(let text, let imageCount) = item.kind else {
            Issue.record("não é userPrompt", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        return (text, imageCount, item.imagePaths)
    }

    @Test func aPromptSentWithThreeImagesLosesTheTagsAndKeepsTheMarkers() throws {
        let names = ["17E055F2-E2AD-4287-A061-07FDD4B46C71.jpg", "2505AD03-213E-4430-9530-7F79CC38F6C8.jpg", "38C26300-E0C8-4BB7-B306-80D78524C1AA.jpg"]
        let markers = names.map { "[imagem: \(Self.uploads)\($0)]" }
        let content = "\n\n<pasted_content id=\"453a\">\nTa foda mano parabéns\n" + markers.joined(separator: "\n") + "\n</pasted_content id=\"453a\">\n"
        let prompt = try onlyPrompt(content)
        #expect(prompt.text == "Ta foda mano parabéns")
        #expect(prompt.imageCount == 3)
        #expect(prompt.imagePaths == names.map { Self.uploads + $0 })
    }

    @Test func textAroundThePasteStays() throws {
        let before = try onlyPrompt("login feito aqui o retorno:\n\n\n\n<pasted_content id=\"3a27\">\nLast login\n$ ls\n</pasted_content id=\"3a27\">")
        #expect(before.text == "login feito aqui o retorno:\n\n\n\nLast login\n$ ls")
        let after = try onlyPrompt("\n\n<pasted_content id=\"21ef\">\ndocs/proposta.md\n</pasted_content id=\"21ef\">\n\n ta em formato de .md")
        #expect(after.text == "docs/proposta.md\n\n ta em formato de .md")
    }

    @Test func aPasteInATextBlockIsUnwrapped() throws {
        let prompt = try onlyPrompt([["type": "text", "text": "\n\n<pasted_content id=\"8e0e\">\nlinha 1\nlinha 2\n</pasted_content id=\"8e0e\">\n"]])
        #expect(prompt.text == "linha 1\nlinha 2")
    }

    @Test func aTagInsideALineIsKept() throws {
        let text = "A tag <pasted_content id=\"x\"> aparece no meio\n</pasted_content> e no começo"
        let prompt = try onlyPrompt(text)
        #expect(prompt.text == text)
    }
}
