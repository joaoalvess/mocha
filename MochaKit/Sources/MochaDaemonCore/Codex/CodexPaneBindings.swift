import Foundation
import MochaProtocol

struct CodexPaneBinding: Codable, Sendable, Equatable {
    let threadId: String
    let cwd: String
}

struct CodexPaneBindingStore: Sendable {
    static let fileName = "codex-panes.json"

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(socketPath: String) {
        url = URL(filePath: socketPath).deletingLastPathComponent().appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    func load() -> [AgentID: CodexPaneBinding] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            return try JSONDecoder().decode([AgentID: CodexPaneBinding].self, from: data)
        } catch {
            codexLogger.error("ignoring unreadable \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    func save(_ bindings: [AgentID: CodexPaneBinding]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try AtomicFile.write(try encoder.encode(bindings), to: url, permissions: 0o600)
        } catch {
            codexLogger.error("failed to save \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
