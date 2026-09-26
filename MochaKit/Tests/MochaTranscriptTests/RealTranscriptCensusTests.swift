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
        var lastVersions: [String: Int] = [:]
        for project in projects {
            let entries = (try? FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.pathExtension == "jsonl" {
                let document = try TranscriptDocument.read(path: entry.path(percentEncoded: false))
                files += 1
                dropped += document.statistics.dropped
                orphans += document.statistics.orphanResults
                unknown.merge(document.statistics.unknown, uniquingKeysWith: +)
                for item in document.items {
                    kinds[item.kind.type, default: 0] += 1
                    if case .toolCall(let call) = item.kind, call.status == .running { runningTools += 1 }
                }
                lastVersions[document.header.claudeVersion ?? "?", default: 0] += 1
            }
        }
        print("census: arquivos=\(files) descartadas=\(dropped) órfãos=\(orphans) toolCall running=\(runningTools)")
        print("census: desconhecidos=\(unknown.sorted { $0.key < $1.key })")
        print("census: itens=\(kinds.sorted { $0.key < $1.key })")
        print("census: versão da última linha por arquivo=\(lastVersions.sorted { $0.key < $1.key })")
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
