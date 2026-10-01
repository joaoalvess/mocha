import CoreGraphics
import Foundation
import ImageIO
import MochaHerdr
import MochaProtocol
import MochaTranscript
import Testing
import UniformTypeIdentifiers
@testable import MochaDaemonCore

extension ClaudeScreenIntegrationTests {
    @Suite struct ClaudeImagePasteIntegrationTests {
        private struct FoundLine {
            let file: URL
            let index: Int
            let bytes: Data
        }

        let pane = ClaudeLabPane.id ?? ""
        let client = HerdrClient(configuration: HerdrClientConfiguration(socketPath: HerdrSocketPath.resolve()))

        @Test func pastedImagePathsBecomeNativeAttachments() async throws {
            let files = try TestImages.directory()
            defer { try? FileManager.default.removeItem(at: files) }
            let png = try TestImages.write(try TestImages.solid(width: 64, height: 48, red: 0.9, green: 0.1, blue: 0.1), to: files.appending(path: "pequena.png"), type: .png)
            let jpeg = try TestImages.write(try Self.photo(width: 2_000, height: 1_500), to: files.appending(path: "grande.jpg"), type: .jpeg)
            let nonce = String(UUID().uuidString.prefix(8))
            let text = "responda só ok \(nonce)"
            let started = Date()

            _ = try await client.agentPrompt(target: pane, text: [text, png.fileSystemPath, jpeg.fileSystemPath].joined(separator: "\n"))

            let found = try #require(try await Self.waitForLine(containing: nonce, after: started), "nenhuma linha user com \(nonce) e imagePasteIds no transcript do laboratório")
            let turnEnded = try await Self.waitForTurnEnd(after: found)
            _ = try? await client.agentWait(target: pane, until: [.idle, .done], timeout: .seconds(10))
            let root = try #require(try JSONSerialization.jsonObject(with: found.bytes) as? [String: Any])
            let line = Self.redacted(root)
            #expect(turnEnded, "o turno não terminou; linha real:\n\(line)")

            let ids = (root["imagePasteIds"] as? [Int]) ?? []
            let blocks = ((root["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            let images = blocks.filter { $0["type"] as? String == "image" }
            let lineText = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            #expect(ids.count == 2, "linha real:\n\(line)")
            #expect(images.count == 2, "linha real:\n\(line)")
            #expect(ids.allSatisfy { lineText.contains("[Image #\($0)]") }, "linha real:\n\(line)")

            let cache = try TestImages.directory()
            defer { try? FileManager.default.removeItem(at: cache) }
            let store = TranscriptImageStore(directory: cache.appending(path: "transcript-images", directoryHint: .isDirectory))
            let item = try #require(TranscriptDocument(bytes: Array(found.bytes) + [0x0A], imageStore: store).items.first, "linha real:\n\(line)")
            #expect(item.kind == .userPrompt(text: text, imageCount: 2), "linha real:\n\(line)")
            #expect(item.imagePaths.count == 2, "linha real:\n\(line)")
            #expect(item.imagePaths.allSatisfy { FileManager.default.fileExists(atPath: $0) && $0.hasPrefix(store.directory.path(percentEncoded: false)) })

            if images.count == 2 {
                print("colagem: \(Self.sameBytesReport(original: try Data(contentsOf: jpeg), block: images[1]))")
            }
        }

        private static var labTranscripts: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let lab = home.appending(path: "Developer/mocha-lab/claude-update", directoryHint: .isDirectory).path(percentEncoded: false)
            var trimmed = lab
            while trimmed.hasSuffix("/") {
                trimmed.removeLast()
            }
            let project = String(trimmed.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
            return home.appending(path: ".claude/projects/\(project)", directoryHint: .isDirectory)
        }

        private static func lines(of file: URL) -> [Data] {
            guard let data = try? Data(contentsOf: file) else { return [] }
            return data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        }

        private static func waitForLine(containing nonce: String, after started: Date) async throws -> FoundLine? {
            let nonceBytes = Data(nonce.utf8)
            let marker = Data("\"imagePasteIds\"".utf8)
            for _ in 0..<200 {
                try await Task.sleep(for: .milliseconds(100))
                let candidates = ((try? FileManager.default.contentsOfDirectory(
                    at: labTranscripts,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )) ?? []).filter { file in
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    return file.pathExtension == "jsonl" && (modified ?? .distantPast) >= started.addingTimeInterval(-1)
                }
                for file in candidates {
                    for (index, line) in lines(of: file).enumerated() where line.range(of: nonceBytes) != nil && line.range(of: marker) != nil {
                        return FoundLine(file: file, index: index, bytes: line)
                    }
                }
            }
            return nil
        }

        private static func waitForTurnEnd(after found: FoundLine) async throws -> Bool {
            let turnDuration = Data("\"turn_duration\"".utf8)
            for _ in 0..<300 {
                if lines(of: found.file).dropFirst(found.index + 1).contains(where: { $0.range(of: turnDuration) != nil }) {
                    return true
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            return false
        }

        private static func redacted(_ root: [String: Any]) -> String {
            var copy = root
            if var message = copy["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] {
                message["content"] = blocks.map { block -> [String: Any] in
                    guard var source = block["source"] as? [String: Any], let data = source["data"] as? String else { return block }
                    source["data"] = "<\(data.count) caracteres>"
                    var redactedBlock = block
                    redactedBlock["source"] = source
                    return redactedBlock
                }
                copy["message"] = message
            }
            let data = (try? JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }

        private static func sameBytesReport(original: Data, block: [String: Any]) -> String {
            let source = block["source"] as? [String: Any]
            let mediaType = source?["media_type"] as? String ?? "?"
            guard let stored = (source?["data"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
                return "JPEG de 2000×1500: o bloco não tem base64 legível (\(mediaType))"
            }
            let size = CGImageSourceCreateWithData(stored as CFData, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
                .map { "\($0[kCGImagePropertyPixelWidth] ?? "?")×\($0[kCGImagePropertyPixelHeight] ?? "?")" } ?? "?"
            let verdict = stored == original ? "mesmos bytes" : "bytes diferentes"
            return "JPEG de 2000×1500 (\(original.count) bytes) chegou ao transcript com \(verdict): \(mediaType), \(size), \(stored.count) bytes"
        }

        private static func photo(width: Int, height: Int) throws -> CGImage {
            try TestImages.image(width: width, height: height) { context in
                let cell = 25
                for row in 0..<(height / cell) {
                    for column in 0..<(width / cell) {
                        let red = CGFloat((column * 37 + row * 11) % 256) / 255
                        let green = CGFloat((row * 53 + column * 7) % 256) / 255
                        let blue = CGFloat((column * row * 13) % 256) / 255
                        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
                        context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
                    }
                }
            }
        }
    }
}
