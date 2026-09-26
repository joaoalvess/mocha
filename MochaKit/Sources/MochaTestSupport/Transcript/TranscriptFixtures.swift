import Foundation
import MochaDaemonCore
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
        public var preview: MessagePreview?
        public var activity: ToolActivity?
        public var contextTokens: Int?
        public var sessionStartedAt: Date?
        public var turnStartedAt: Date?
        public var turnEndedAt: Date?

        public init(
            title: String?,
            model: String?,
            branch: String?,
            permissionMode: String?,
            preview: MessagePreview? = nil,
            activity: ToolActivity? = nil,
            contextTokens: Int? = nil,
            sessionStartedAt: Date? = nil,
            turnStartedAt: Date? = nil,
            turnEndedAt: Date? = nil
        ) {
            self.title = title
            self.model = model
            self.branch = branch
            self.permissionMode = permissionMode
            self.preview = preview
            self.activity = activity
            self.contextTokens = contextTokens
            self.sessionStartedAt = sessionStartedAt
            self.turnStartedAt = turnStartedAt
            self.turnEndedAt = turnEndedAt
        }

        public init(header: TranscriptHeader) {
            self.init(
                title: header.title,
                model: header.model,
                branch: header.branch,
                permissionMode: header.permissionMode,
                preview: header.preview,
                activity: header.activity,
                contextTokens: header.contextTokens,
                sessionStartedAt: header.sessionStartedAt,
                turnStartedAt: header.turnStartedAt,
                turnEndedAt: header.turnEndedAt
            )
        }

        public init(meta: TranscriptMeta) {
            self.init(
                title: meta.title,
                model: meta.model,
                branch: meta.branch,
                permissionMode: meta.permissionMode,
                preview: meta.preview,
                activity: meta.activity,
                contextTokens: meta.contextTokens,
                sessionStartedAt: meta.sessionStartedAt,
                turnStartedAt: meta.turnStartedAt,
                turnEndedAt: meta.turnEndedAt
            )
        }

        private enum CodingKeys: String, CodingKey {
            case title, model, branch, permissionMode, preview, activity, contextTokens, sessionStartedAt, turnStartedAt, turnEndedAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            branch = try container.decodeIfPresent(String.self, forKey: .branch)
            permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
            preview = try container.decodeIfPresent(MessagePreview.self, forKey: .preview)
            activity = try container.decodeIfPresent(ToolActivity.self, forKey: .activity)
            contextTokens = try container.decodeIfPresent(Int.self, forKey: .contextTokens)
            sessionStartedAt = try Self.decodeDate(container, .sessionStartedAt)
            turnStartedAt = try Self.decodeDate(container, .turnStartedAt)
            turnEndedAt = try Self.decodeDate(container, .turnEndedAt)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(model, forKey: .model)
            try container.encode(branch, forKey: .branch)
            try container.encode(permissionMode, forKey: .permissionMode)
            try container.encode(preview, forKey: .preview)
            try container.encode(activity, forKey: .activity)
            try container.encode(contextTokens, forKey: .contextTokens)
            try container.encode(sessionStartedAt.map(ProtocolDate.string(from:)), forKey: .sessionStartedAt)
            try container.encode(turnStartedAt.map(ProtocolDate.string(from:)), forKey: .turnStartedAt)
            try container.encode(turnEndedAt.map(ProtocolDate.string(from:)), forKey: .turnEndedAt)
        }

        private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date? {
            guard let text = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
            guard let date = ProtocolDate.date(from: text) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Data inválida: \(text)")
            }
            return date
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
        meta = Meta(header: document.header)
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
