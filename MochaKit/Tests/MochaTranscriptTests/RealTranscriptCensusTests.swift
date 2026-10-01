import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

@Suite(.tags(.integration), .enabled(if: IntegrationGate.isEnabled))
struct RealTranscriptCensusTests {
    @Test func realTranscriptsParseWithCountsOnly() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var files = 0
        var dropped = 0
        var orphans = 0
        var unknown: [String: Int] = [:]
        var kinds: [String: Int] = [:]
        var runningTools = 0
        var promptsWithPastedTags = 0
        var images = ImageCensus()
        var pasted = PastedImageCensus()
        var lastVersions: [String: Int] = [:]
        let cache = FileManager.default.temporaryDirectory.appending(path: "mocha-census-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: cache) }
        let store = TranscriptImageStore(directory: cache)
        for project in projects {
            let entries = (try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.pathExtension == "jsonl" {
                let path = entry.path(percentEncoded: false)
                let document = try TranscriptDocument.read(path: path, imageStore: store)
                pasted.promptLines += try Self.pastedPromptLines(in: path)
                files += 1
                dropped += document.statistics.dropped
                orphans += document.statistics.orphanResults
                unknown.merge(document.statistics.unknown, uniquingKeysWith: +)
                for item in document.items {
                    kinds[item.kind.type, default: 0] += 1
                    if case .toolCall(let call) = item.kind, call.status == .running { runningTools += 1 }
                    if case .userPrompt(let text, _) = item.kind, text.contains("<pasted_content") { promptsWithPastedTags += 1 }
                    images.count(item)
                    pasted.count(item, cache: store.directory.path(percentEncoded: false))
                }
                lastVersions[document.header.claudeVersion ?? "?", default: 0] += 1
            }
        }
        print("census: arquivos=\(files) descartadas=\(dropped) órfãos=\(orphans) toolCall running=\(runningTools)")
        print("census: desconhecidos=\(unknown.sorted { $0.key < $1.key })")
        print("census: itens=\(kinds.sorted { $0.key < $1.key })")
        print("census: versão da última linha por arquivo=\(lastVersions.sorted { $0.key < $1.key })")
        print("census: imagens \(images.summary)")
        print("census: userPrompt com <pasted_content> no texto=\(promptsWithPastedTags)")
        print("census: anexos colados \(pasted.summary)")
        #expect(files > 0)
    }

    @Test func realTranscriptHomeMetaAgreesAcrossReadersWithCountsOnly() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var compared = 0
        var skippedLarge = 0
        var runningActivity = 0
        var mismatches: [String: Int] = [:]
        for project in projects {
            let entries = (try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.pathExtension == "jsonl" {
                let path = entry.path(percentEncoded: false)
                guard let size = TranscriptFileStatus.of(path: path)?.size else { continue }
                guard size <= TranscriptHeaderScanner.scanLimit else {
                    skippedLarge += 1
                    continue
                }
                let full = try TranscriptDocument.summary(path: path).header
                let scanned = try TranscriptHeaderScanner.header(ofFileAt: path)
                let followed = try TranscriptFollower(path: path, start: .afterExistingLines).header
                compared += 1
                if full.activity?.status == .running { runningActivity += 1 }
                for (name, reader) in [("varredura", scanned), ("acompanhamento", followed)] {
                    for field in Self.differingFields(full, reader) {
                        mismatches["\(name).\(field)", default: 0] += 1
                    }
                }
            }
        }
        print("home meta: comparados=\(compared) acima de 8 MB=\(skippedLarge) activity running=\(runningActivity)")
        print("home meta: divergências=\(mismatches.sorted { $0.key < $1.key })")
        #expect(compared > 0)
        #expect(mismatches.isEmpty)
    }

    private struct ImageCensus {
        var mentionItems = 0
        var mentionPaths = 0
        var existingMentionPaths = 0
        var readItems = 0
        var existingReadPaths = 0
        var promptItems = 0
        var existingPromptPaths = 0

        mutating func count(_ item: ChatItem) {
            guard !item.imagePaths.isEmpty else { return }
            let existing = item.imagePaths.count(where: { FileManager.default.fileExists(atPath: $0) })
            switch item.kind {
            case .assistantText:
                mentionItems += 1
                mentionPaths += item.imagePaths.count
                existingMentionPaths += existing
            case .toolCall(let call) where call.name == "Read":
                readItems += 1
                existingReadPaths += existing
            case .userPrompt:
                promptItems += 1
                existingPromptPaths += existing
            default:
                break
            }
        }

        var summary: String {
            "assistantText com imagePaths=\(mentionItems) (caminhos=\(mentionPaths), existem=\(existingMentionPaths)) "
                + "Read com imagePaths=\(readItems) (existem=\(existingReadPaths)) "
                + "userPrompt com imagePaths=\(promptItems) (existem=\(existingPromptPaths))"
        }
    }

    private struct PastedImageCensus {
        var promptLines = 0
        var blocksWithPath = 0
        var blocksWithoutPath = 0
        var leftoverChips = 0

        mutating func count(_ item: ChatItem, cache: String) {
            guard case .userPrompt(let text, let imageCount) = item.kind else { return }
            let stored = item.imagePaths.count(where: { $0.hasPrefix(cache) })
            let markers = item.imagePaths.count - stored
            blocksWithPath += stored
            blocksWithoutPath += imageCount - markers - stored
            if text.contains("[Image #") { leftoverChips += 1 }
        }

        var summary: String {
            "linhas user com imagePasteIds=\(promptLines) blocos image com caminho=\(blocksWithPath) sem caminho=\(blocksWithoutPath) "
                + "userPrompt com [Image # no texto=\(leftoverChips)"
        }
    }

    private static func pastedPromptLines(in path: String) throws -> Int {
        let needle = Array("\"imagePasteIds\"".utf8)
        var count = 0
        try TranscriptFile(path: path).forEachAppendedLine { _, bytes in
            let found = needle.withUnsafeBytes { pattern in
                guard let base = bytes.baseAddress, let patternBase = pattern.baseAddress else { return false }
                return memmem(base, bytes.count, patternBase, pattern.count) != nil
            }
            guard found,
                  let root = try? JSONParser.parse(bytes).objectValue,
                  root["type"]?.stringValue == "user",
                  root["isMeta"]?.isTrue != true,
                  root["imagePasteIds"]?.arrayValue?.isEmpty == false else {
                return
            }
            count += 1
        }
        return count
    }

    private static func differingFields(_ lhs: TranscriptHeader, _ rhs: TranscriptHeader) -> [String] {
        var fields: [String] = []
        if lhs.title != rhs.title { fields.append("title") }
        if lhs.model != rhs.model || lhs.branch != rhs.branch { fields.append("modelBranch") }
        if lhs.permissionMode != rhs.permissionMode { fields.append("permissionMode") }
        if lhs.claudeVersion != rhs.claudeVersion { fields.append("claudeVersion") }
        if lhs.preview != rhs.preview { fields.append("preview") }
        if lhs.activity != rhs.activity { fields.append("activity") }
        if lhs.contextTokens != rhs.contextTokens { fields.append("contextTokens") }
        if lhs.sessionStartedAt != rhs.sessionStartedAt { fields.append("sessionStartedAt") }
        if lhs.turnStartedAt != rhs.turnStartedAt { fields.append("turnStartedAt") }
        if lhs.turnEndedAt != rhs.turnEndedAt { fields.append("turnEndedAt") }
        return fields
    }
}
