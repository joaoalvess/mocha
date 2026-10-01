import CryptoKit
import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

@Suite
struct ImagePasteTests {
    private typealias L = TranscriptLines

    private struct Prompt {
        let text: String
        let imageCount: Int
        let imagePaths: [String]
    }

    private static let png = Data("png colado".utf8).base64EncodedString()
    private static let jpeg = Data("jpeg colado".utf8).base64EncodedString()
    private static let uploads = ImageMarkers.uploadsDirectory

    private static func image(_ data: String, mediaType: String = "image/png") -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data]]
    }

    private static func pasted(_ text: String, ids: [Int], images: [[String: Any]]) -> String {
        L.user([["type": "text", "text": text]] + images, extra: ["imagePasteIds": ids, "promptSource": "typed"])
    }

    private static func hashName(_ base64: String, _ fileExtension: String) -> String {
        SHA256.hash(data: Data(base64.utf8)).map { String(format: "%02x", $0) }.joined() + "." + fileExtension
    }

    private func withStore(_ body: (TranscriptImageStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mocha-transcript-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(TranscriptImageStore(directory: root.appending(path: "cache/transcript-images", directoryHint: .isDirectory)))
    }

    private func onlyPrompt(_ line: String, store: TranscriptImageStore? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Prompt {
        let document = TranscriptDocument(bytes: Array((line + "\n").utf8), imageStore: store)
        #expect(document.items.count == 1, sourceLocation: sourceLocation)
        let item = try #require(document.items.first, sourceLocation: sourceLocation)
        guard case .userPrompt(let text, let imageCount) = item.kind else {
            Issue.record("não é userPrompt", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        return Prompt(text: text, imageCount: imageCount, imagePaths: item.imagePaths)
    }

    private func storedPath(_ store: TranscriptImageStore, _ base64: String, _ fileExtension: String) -> String {
        store.directory.appending(path: Self.hashName(base64, fileExtension), directoryHint: .notDirectory).path(percentEncoded: false)
    }

    @Test func chipsAtTheStartLeaveOnlyTheText() throws {
        let images = [Self.image(Self.png), Self.image(Self.jpeg, mediaType: "image/jpeg"), Self.image(Self.png)]
        let prompt = try onlyPrompt(Self.pasted("[Image #17] [Image #18] [Image #19]Compara as três em 10 palavras", ids: [17, 18, 19], images: images))
        #expect(prompt.text == "Compara as três em 10 palavras")
        #expect(prompt.imageCount == 3)
        #expect(prompt.imagePaths.isEmpty)
    }

    @Test func chipsInTheMiddleTakeTheSpaceAfterThem() throws {
        let prompt = try onlyPrompt(Self.pasted("olha [Image #5] e me diz o que é", ids: [5], images: [Self.image(Self.png)]))
        #expect(prompt.text == "olha e me diz o que é")
        #expect(prompt.imageCount == 1)
    }

    @Test func chipsOutsideImagePasteIdsStay() throws {
        let partial = try onlyPrompt(Self.pasted("[Image #3] [Image #4]texto", ids: [4], images: [Self.image(Self.png)]))
        #expect(partial.text == "[Image #3] texto")
        let withoutIds = try onlyPrompt(L.user([["type": "text", "text": "[Image #1] colada"], Self.image(Self.png)]))
        #expect(withoutIds.text == "[Image #1] colada")
        #expect(withoutIds.imageCount == 1)
    }

    @Test func chipsBeforePastedContentLeaveTheUnwrappedText() throws {
        let text = "[Image #24]\n\n<pasted_content id=\"e292\">\nlinha 1\nlinha 2\nlinha 3\nlinha 4, responda ok\n</pasted_content id=\"e292\">\n"
        let prompt = try onlyPrompt(Self.pasted(text, ids: [24], images: [Self.image(Self.png)]))
        #expect(prompt.text == "linha 1\nlinha 2\nlinha 3\nlinha 4, responda ok")
        #expect(prompt.imageCount == 1)
    }

    @Test func chipsAloneLeaveAnEmptyText() throws {
        let prompt = try onlyPrompt(Self.pasted("[Image #2]", ids: [2], images: [Self.image(Self.jpeg, mediaType: "image/jpeg")]))
        #expect(prompt.text.isEmpty)
        #expect(prompt.imageCount == 1)
    }

    @Test func aQueuedCommandUsesTheImagePasteIdsOfTheAttachment() throws {
        try withStore { store in
            let line = L.json([
                "type": "attachment",
                "uuid": UUID().uuidString,
                "timestamp": "2026-09-25T15:00:00.000Z",
                "attachment": [
                    "type": "queued_command",
                    "commandMode": "prompt",
                    "origin": ["kind": "human"],
                    "imagePasteIds": [11],
                    "prompt": [["type": "text", "text": "[Image #11] ta certo isso?"], Self.image(Self.png)],
                ],
            ])
            let prompt = try onlyPrompt(line, store: store)
            #expect(prompt.text == "ta certo isso?")
            #expect(prompt.imageCount == 1)
            #expect(prompt.imagePaths == [storedPath(store, Self.png, "png")])
        }
    }

    @Test func textWithoutPastedChipsIsUntouched() {
        #expect(ImagePasteChips.removing(ids: [1], from: "  sem chip  ") == "  sem chip  ")
        #expect(ImagePasteChips.removing(ids: [], from: "[Image #1] fica") == "[Image #1] fica")
        #expect(ImagePasteChips.removing(ids: [1], from: "[Image #x] [Image #] fica") == "[Image #x] [Image #] fica")
    }

    @Test func pngAndJpegBlocksBecomeStoredFilesInOrder() throws {
        try withStore { store in
            let line = Self.pasted("[Image #1] [Image #2]duas", ids: [1, 2], images: [Self.image(Self.png), Self.image(Self.jpeg, mediaType: "image/jpeg")])
            let prompt = try onlyPrompt(line, store: store)
            let expected = [storedPath(store, Self.png, "png"), storedPath(store, Self.jpeg, "jpg")]
            #expect(prompt.text == "duas")
            #expect(prompt.imageCount == 2)
            #expect(prompt.imagePaths == expected)
            #expect(try Data(contentsOf: URL(filePath: expected[0])) == Data("png colado".utf8))
            #expect(try Data(contentsOf: URL(filePath: expected[1])) == Data("jpeg colado".utf8))
        }
    }

    @Test func gifAndWebpGetTheirExtensions() throws {
        try withStore { store in
            #expect(store.path(forBase64: Self.png, mediaType: "image/gif") == storedPath(store, Self.png, "gif"))
            #expect(store.path(forBase64: Self.jpeg, mediaType: "image/webp") == storedPath(store, Self.jpeg, "webp"))
        }
    }

    @Test func unsupportedOrInvalidBlocksCountWithoutAPath() throws {
        try withStore { store in
            let images: [[String: Any]] = [
                Self.image(Self.png, mediaType: "image/bmp"),
                Self.image("@@ inválido @@", mediaType: "image/png"),
                ["type": "image", "source": ["type": "url", "url": "https://example.com/a.png"]],
                Self.image(Self.jpeg, mediaType: "image/jpeg"),
            ]
            let prompt = try onlyPrompt(Self.pasted("[Image #1] [Image #2] [Image #3] [Image #4]quatro", ids: [1, 2, 3, 4], images: images), store: store)
            #expect(prompt.text == "quatro")
            #expect(prompt.imageCount == 4)
            #expect(prompt.imagePaths == [storedPath(store, Self.jpeg, "jpg")])
            #expect(directoryEntries(store.directory) == [Self.hashName(Self.jpeg, "jpg")])
        }
    }

    @Test func withoutAStoreBlocksHaveNoPathAndNothingIsWritten() throws {
        try withStore { store in
            let prompt = try onlyPrompt(Self.pasted("[Image #1]sem cache", ids: [1], images: [Self.image(Self.png)]))
            #expect(prompt.imageCount == 1)
            #expect(prompt.imagePaths.isEmpty)
            #expect(FileManager.default.fileExists(atPath: store.directory.path(percentEncoded: false)) == false)
        }
    }

    @Test func blockPathsComeBeforeMarkerPaths() throws {
        try withStore { store in
            let text = "[Image #7]olha\n[imagem: \(Self.uploads)A.jpg]\n\(Self.uploads)B.jpg"
            let prompt = try onlyPrompt(Self.pasted(text, ids: [7], images: [Self.image(Self.png)]), store: store)
            #expect(prompt.text == "olha")
            #expect(prompt.imageCount == 3)
            #expect(prompt.imagePaths == [storedPath(store, Self.png, "png"), Self.uploads + "A.jpg", Self.uploads + "B.jpg"])
        }
    }

    @Test func storeNamesTheFileByTheHashOfTheBase64WithOwnerOnlyPermissions() throws {
        try withStore { store in
            let path = try #require(store.path(forBase64: Self.png, mediaType: "IMAGE/PNG"))
            #expect(path == storedPath(store, Self.png, "png"))
            #expect(fileMode(path) == 0o600)
            #expect(fileMode(store.directory.path(percentEncoded: false)) == 0o700)
            #expect(directoryEntries(store.directory) == [Self.hashName(Self.png, "png")])
        }
    }

    @Test func storeDoesNotRewriteAnExistingFileAndRenewsItsDate() throws {
        try withStore { store in
            let path = try #require(store.path(forBase64: Self.png, mediaType: "image/png"))
            try Data("já estava".utf8).write(to: URL(filePath: path))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: path)
            let before = inode(path)

            #expect(store.path(forBase64: Self.png, mediaType: "image/png") == path)

            #expect(try Data(contentsOf: URL(filePath: path)) == Data("já estava".utf8))
            #expect(inode(path) == before)
            let modified = try #require(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            #expect(Date().timeIntervalSince(modified) < 60)
        }
    }

    @Test func storeTightensAnExistingDirectory() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            #expect(store.path(forBase64: Self.png, mediaType: "image/png") != nil)
            #expect(fileMode(store.directory.path(percentEncoded: false)) == 0o700)
        }
    }

    @Test func storeIgnoresANonRegularFileWithTheSameName() throws {
        try withStore { store in
            let blocker = store.directory.appending(path: Self.hashName(Self.png, "png"), directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
            #expect(store.path(forBase64: Self.png, mediaType: "image/png") == nil)
        }
    }

    @Test func followerPagerAndDocumentPassTheStore() throws {
        try withStore { store in
            let transcript = FileManager.default.temporaryDirectory.appending(path: "mocha-paste-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: transcript) }
            try Data((Self.pasted("[Image #1]primeira", ids: [1], images: [Self.image(Self.png)]) + "\n").utf8).write(to: transcript)
            let path = transcript.path(percentEncoded: false)
            let pngPath = storedPath(store, Self.png, "png")
            let jpegPath = storedPath(store, Self.jpeg, "jpg")

            #expect(try TranscriptDocument.read(path: path, imageStore: store).items.map(\.imagePaths) == [[pngPath]])
            #expect(try TranscriptPageReader(path: path, imageStore: store).lastPage(limit: 10).items.map(\.imagePaths) == [[pngPath]])
            #expect(try TranscriptPageReader(path: path).lastPage(limit: 10).items.map(\.imagePaths) == [[]])

            let follower = try TranscriptFollower(path: path, start: .afterExistingLines, imageStore: store)
            #expect(try follower.lastPage(limit: 10).items.map(\.imagePaths) == [[pngPath]])
            let handle = try FileHandle(forWritingTo: transcript)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((Self.pasted("[Image #2]segunda", ids: [2], images: [Self.image(Self.jpeg, mediaType: "image/jpeg")]) + "\n").utf8))
            #expect(Self.appendedPaths(try follower.readAppendedLines()) == [[jpegPath]])

            follower.imageStore = nil
            try handle.write(contentsOf: Data((Self.pasted("[Image #3]terceira", ids: [3], images: [Self.image(Self.png)]) + "\n").utf8))
            try handle.close()
            #expect(Self.appendedPaths(try follower.readAppendedLines()) == [[]])
            #expect(try follower.lastPage(limit: 10).items.map(\.imagePaths) == [[], [], []])
        }
    }

    @Test func followerWithoutAStoreWritesNothing() throws {
        try withStore { store in
            let transcript = FileManager.default.temporaryDirectory.appending(path: "mocha-paste-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: transcript) }
            try Data((Self.pasted("[Image #1]x", ids: [1], images: [Self.image(Self.png)]) + "\n").utf8).write(to: transcript)
            let follower = try TranscriptFollower(path: transcript.path(percentEncoded: false), start: .afterExistingLines)
            #expect(try follower.lastPage(limit: 10).items.map(\.imagePaths) == [[]])
            #expect(FileManager.default.fileExists(atPath: store.directory.path(percentEncoded: false)) == false)
        }
    }

    private static func appendedPaths(_ update: TranscriptFollowUpdate) -> [[String]] {
        update.changes.compactMap {
            if case .append(let item) = $0 { return item.imagePaths }
            return nil
        }
    }

    private func directoryEntries(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
    }

    private func fileMode(_ path: String) -> Int? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Int(info.st_mode & 0o777)
    }

    private func inode(_ path: String) -> UInt64? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return UInt64(info.st_ino)
    }
}
