import Foundation
import MochaProtocol
import MochaTranscript

public enum TranscriptFixtures {
    public static let names = [
        "basic-turn",
        "tool-calls",
        "permissions-and-interrupts",
        "ask-user-question",
        "plan-mode",
        "clear-and-compact",
        "slash-and-shell",
        "subagents",
        "images-and-queued",
        "malformed",
    ]

    public static let fixturesRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures", directoryHint: .isDirectory)

    public static let directory = fixturesRoot.appending(path: "transcripts", directoryHint: .isDirectory)

    public static let bigFixture = directory.appending(path: "generated/big-50mb.jsonl")

    public static func url(_ name: String) -> URL {
        directory.appending(path: "\(name).jsonl")
    }

    public static func path(_ name: String) -> String {
        url(name).path(percentEncoded: false)
    }

    public static func expectedURL(_ name: String) -> URL {
        directory.appending(path: "expected/\(name).json")
    }

    public static func bytes(_ name: String) throws -> [UInt8] {
        Array(try Data(contentsOf: url(name)))
    }

    public static func document(_ name: String) throws -> TranscriptDocument {
        try TranscriptDocument.read(path: path(name))
    }

    public static func expectedSnapshot(_ name: String) throws -> TranscriptSnapshot {
        try JSONDecoder().decode(TranscriptSnapshot.self, from: Data(contentsOf: expectedURL(name)))
    }
}

public struct TranscriptSnapshot: Codable, Equatable, Sendable {
    public struct Meta: Codable, Equatable, Sendable {
        public var title: String?
        public var model: String?
        public var branch: String?
        public var permissionMode: String?

        public init(title: String?, model: String?, branch: String?, permissionMode: String?) {
            self.title = title
            self.model = model
            self.branch = branch
            self.permissionMode = permissionMode
        }

        private enum CodingKeys: String, CodingKey {
            case title, model, branch, permissionMode
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            branch = try container.decodeIfPresent(String.self, forKey: .branch)
            permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(model, forKey: .model)
            try container.encode(branch, forKey: .branch)
            try container.encode(permissionMode, forKey: .permissionMode)
        }
    }

    public struct Stats: Codable, Equatable, Sendable {
        public var dropped: Int
        public var orphanResults: Int
        public var unknown: [String: Int]

        public init(dropped: Int, orphanResults: Int, unknown: [String: Int]) {
            self.dropped = dropped
            self.orphanResults = orphanResults
            self.unknown = unknown
        }
    }

    public var meta: Meta
    public var items: [ChatItem]
    public var stats: Stats

    public init(meta: Meta, items: [ChatItem], stats: Stats) {
        self.meta = meta
        self.items = items
        self.stats = stats
    }

    public init(document: TranscriptDocument) {
        meta = Meta(
            title: document.header.title,
            model: document.header.model,
            branch: document.header.branch,
            permissionMode: document.header.permissionMode
        )
        items = document.items
        stats = Stats(
            dropped: document.statistics.dropped,
            orphanResults: document.statistics.orphanResults,
            unknown: document.statistics.unknown
        )
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
