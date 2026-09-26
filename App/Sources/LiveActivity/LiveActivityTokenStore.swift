import Foundation

struct LiveActivityTokens: Codable, Equatable, Sendable {
    struct ActivityRecord: Codable, Equatable, Sendable {
        var updateToken: String
        var receivedAt: Date
        var appState: String
    }

    var pushToStartToken: String?
    var pushToStartReceivedAt: Date?
    var activities: [String: ActivityRecord] = [:]
}

struct LiveActivityTokenStore: Sendable {
    let url: URL

    init(url: URL = URL.applicationSupportDirectory.appending(path: "live-activity-tokens.json")) {
        self.url = url
    }

    func load() -> LiveActivityTokens {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let tokens = try? decoder.decode(LiveActivityTokens.self, from: data) else {
            return LiveActivityTokens()
        }
        return tokens
    }

    func save(_ tokens: LiveActivityTokens) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tokens).write(to: url, options: .atomic)
    }
}
