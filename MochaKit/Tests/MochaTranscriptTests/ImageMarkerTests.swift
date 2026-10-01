import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

@Suite
struct ImageMarkerTests {
    private typealias L = TranscriptLines
    private typealias H = HomeLines

    private static let uploads = ImageMarkers.uploadsDirectory

    private static func marker(_ name: String) -> String {
        "[imagem: \(uploads)\(name)]"
    }

    private func onlyPrompt(_ lines: [String], sourceLocation: SourceLocation = #_sourceLocation) throws -> (text: String, imageCount: Int, imagePaths: [String]) {
        let document = L.document(lines)
        #expect(document.items.count == 1, sourceLocation: sourceLocation)
        let item = try #require(document.items.first, sourceLocation: sourceLocation)
        guard case .userPrompt(let text, let imageCount) = item.kind else {
            Issue.record("não é userPrompt", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        return (text, imageCount, item.imagePaths)
    }

    @Test func uploadsDirectoryIsTheMochaFolderInTheHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let expected = (home.hasSuffix("/") ? home : home + "/") + "Library/Application Support/Mocha/uploads/"
        #expect(Self.uploads == expected)
        #expect(ImageMarkers.uploadsDirectory(home: URL(filePath: "/Users/dev/", directoryHint: .isDirectory)) == "/Users/dev/Library/Application Support/Mocha/uploads/")
        #expect(ImageMarkers.uploadsDirectory(home: URL(filePath: "/Users/dev", directoryHint: .notDirectory)) == "/Users/dev/Library/Application Support/Mocha/uploads/")
    }

    @Test func oneMarkerLeavesTheTextAndCountsOneImage() throws {
        let prompt = try onlyPrompt([L.user("Olha esse print\n\(Self.marker("5B0E7C1A-3F2D-4E8B-9A61-7C4D2E9F8B30.jpg"))")])
        #expect(prompt.text == "Olha esse print")
        #expect(prompt.imageCount == 1)
        #expect(prompt.imagePaths == ["\(Self.uploads)5B0E7C1A-3F2D-4E8B-9A61-7C4D2E9F8B30.jpg"])
    }

    @Test func threeMarkersCountThreeImagesInOrder() throws {
        let text = ["Compara as três telas", Self.marker("A.jpg"), Self.marker("B.png"), Self.marker("C.heic")].joined(separator: "\n")
        let prompt = try onlyPrompt([L.user(text)])
        #expect(prompt.text == "Compara as três telas")
        #expect(prompt.imageCount == 3)
        #expect(prompt.imagePaths == ["A.jpg", "B.png", "C.heic"].map { Self.uploads + $0 })
    }

    @Test func markersInTextBlocksAddToImageBlocks() throws {
        let image: [String: Any] = ["type": "image", "source": ["type": "base64", "data": "AAAA"]]
        let prompt = try onlyPrompt([L.user([["type": "text", "text": "veja\n\(Self.marker("A.jpg"))"], image, ["type": "text", "text": Self.marker("B.jpg")]])])
        #expect(prompt.text == "veja")
        #expect(prompt.imageCount == 3)
        #expect(prompt.imagePaths == ["A.jpg", "B.jpg"].map { Self.uploads + $0 })
    }

    @Test func pastedImageBlocksCountWithoutAPath() throws {
        let image: [String: Any] = ["type": "image", "source": ["type": "base64", "data": "AAAA"]]
        let prompt = try onlyPrompt([L.user([image, ["type": "text", "text": "colada"]])])
        #expect(prompt.text == "colada")
        #expect(prompt.imageCount == 1)
        #expect(prompt.imagePaths.isEmpty)
    }

    @Test func markersInTheMiddleAreRemovedAndTrailingEmptyLinesTrimmed() throws {
        let middle = try onlyPrompt([L.user("antes\n\(Self.marker("A.jpg"))\ndepois")])
        #expect(middle.text == "antes\ndepois")
        #expect(middle.imageCount == 1)
        let trailing = try onlyPrompt([L.user("texto\n\n\(Self.marker("A.jpg"))\n\(Self.marker("B.jpg"))\n")])
        #expect(trailing.text == "texto")
        #expect(trailing.imageCount == 2)
        #expect(trailing.imagePaths == ["A.jpg", "B.jpg"].map { Self.uploads + $0 })
    }

    @Test func textWithoutMarkersIsUntouched() throws {
        let prompt = try onlyPrompt([L.user("linha\n\n")])
        #expect(prompt.text == "linha\n\n")
        #expect(prompt.imageCount == 0)
        #expect(prompt.imagePaths.isEmpty)
    }

    @Test(arguments: [
        "/tmp/mocha/A.jpg",
        "~/Library/Application Support/Mocha/uploads/A.jpg",
        "Library/Application Support/Mocha/uploads/A.jpg",
        "/Users/outro/Library/Application Support/Mocha/uploads/A.jpg",
        "\(ImageMarkers.uploadsDirectory)",
        "\(ImageMarkers.uploadsDirectory)../devices.json",
        "\(ImageMarkers.uploadsDirectory)./A.jpg",
        "\(ImageMarkers.uploadsDirectory)sub//A.jpg",
        "\(ImageMarkers.uploadsDirectory.dropLast())-velhos/A.jpg",
    ])
    func markerOutsideUploadsStaysInTheText(_ path: String) throws {
        let text = "texto\n[imagem: \(path)]"
        let prompt = try onlyPrompt([L.user(text)])
        #expect(prompt.text == text)
        #expect(prompt.imageCount == 0)
        #expect(prompt.imagePaths.isEmpty)
    }

    @Test func onlyWholeMarkerLinesCount() throws {
        let marker = Self.marker("A.jpg")
        for text in [" \(marker)", "\(marker) ", "antes \(marker)", "\(marker) depois", "[Imagem: \(Self.uploads)A.jpg]", "[imagem:\(Self.uploads)A.jpg]"] {
            let prompt = try onlyPrompt([L.user("texto\n\(text)")])
            #expect(prompt.text == "texto\n\(text)")
            #expect(prompt.imageCount == 0)
        }
    }

    @Test func queuedCommandMarkersAreStripped() throws {
        let text = try onlyPrompt([H.queued("na fila\n\(Self.marker("A.jpg"))", at: "10:00:00")])
        #expect(text.text == "na fila")
        #expect(text.imageCount == 1)
        #expect(text.imagePaths == [Self.uploads + "A.jpg"])
        let blocks = try onlyPrompt([H.queued([["type": "text", "text": "com print\n\(Self.marker("A.jpg"))\n\(Self.marker("B.jpg"))"], ["type": "image"]], at: "10:00:00")])
        #expect(blocks.text == "com print")
        #expect(blocks.imageCount == 3)
        #expect(blocks.imagePaths == ["A.jpg", "B.jpg"].map { Self.uploads + $0 })
    }

    @Test func markerOnlyPromptPreviewsAsImagem() throws {
        let direct = try HomeMetaReadings.of([H.user(Self.marker("A.jpg"), at: "10:00:00")])
        direct.expectConsistent()
        #expect(direct.full.preview == MessagePreview(author: .user, text: "[imagem]"))
        let leadingEmptyLine = try onlyPrompt([H.user("\n\(Self.marker("A.jpg"))", at: "10:00:00")])
        #expect(leadingEmptyLine.text.isEmpty)
        #expect(leadingEmptyLine.imageCount == 1)

        let queued = try HomeMetaReadings.of([
            H.user("primeiro", at: "10:00:00"),
            H.queued("\(Self.marker("A.jpg"))\n\(Self.marker("B.jpg"))", at: "10:00:01"),
        ])
        queued.expectConsistent()
        #expect(queued.full.preview == MessagePreview(author: .user, text: "[imagem]"))

        let withText = try HomeMetaReadings.of([H.user("olha **isso**\n\(Self.marker("A.jpg"))", at: "10:00:00")])
        withText.expectConsistent()
        #expect(withText.full.preview == MessagePreview(author: .user, text: "olha isso"))
    }

    @Test func extractionUsesTheGivenUploadsDirectory() {
        let uploads = "/srv/mocha/uploads/"
        let result = ImageMarkers.extract(from: "oi\n[imagem: \(uploads)A.jpg]\n\(Self.marker("B.jpg"))", uploadsDirectory: uploads)
        #expect(result.count == 1)
        #expect(result.paths == ["\(uploads)A.jpg"])
        #expect(result.text == "oi\n\(Self.marker("B.jpg"))")
    }

    @Test func userPromptsDoNotLookForMentionsInTheText() throws {
        let prompt = try onlyPrompt([L.user("olha /Users/dev/projects/demo-app/a.png e `b.png`")])
        #expect(prompt.imageCount == 0)
        #expect(prompt.imagePaths.isEmpty)
    }
}
