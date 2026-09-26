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
}
