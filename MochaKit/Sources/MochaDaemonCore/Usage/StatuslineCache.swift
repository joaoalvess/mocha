import Foundation
import MochaProtocol

public struct StatuslineCache: Sendable, Equatable {
    public var fetchedAt: Date
    public var windows: [UsageWindow]
    public var contexts: [String: Double]

    public init(fetchedAt: Date, windows: [UsageWindow], contexts: [String: Double]) {
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.contexts = contexts
    }

    public static func parse(_ data: Data) -> StatuslineCache? {
        guard let file = try? JSONDecoder().decode(CacheFile.self, from: data), file.fetchedAtUnix.isFinite else { return nil }
        return StatuslineCache(
            fetchedAt: Date(timeIntervalSince1970: file.fetchedAtUnix),
            windows: (file.windows ?? []).compactMap(\.window),
            contexts: (file.sessionContexts ?? [:]).compactMapValues(\.usedPercent)
        )
    }

    public static func read(_ url: URL) -> StatuslineCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    private struct CacheFile: Decodable {
        let fetchedAtUnix: Double
        let windows: [LossyWindow]?
        let sessionContexts: [String: LossyContext]?

        enum CodingKeys: String, CodingKey {
            case fetchedAtUnix = "fetched_at_unix"
            case windows
            case sessionContexts = "session_contexts"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fetchedAtUnix = try container.decode(Double.self, forKey: .fetchedAtUnix)
            windows = try? container.decodeIfPresent([LossyWindow].self, forKey: .windows)
            sessionContexts = try? container.decodeIfPresent([String: LossyContext].self, forKey: .sessionContexts)
        }
    }

    private struct LossyWindow: Decodable {
        let window: UsageWindow?

        enum CodingKeys: String, CodingKey {
            case kind
            case usedPercent = "used_percent"
            case resetsAt = "resets_at"
        }

        init(from decoder: any Decoder) {
            guard
                let container = try? decoder.container(keyedBy: CodingKeys.self),
                let kind = (try? container.decode(String.self, forKey: .kind)).flatMap(Self.kind),
                let used = try? container.decode(Double.self, forKey: .usedPercent),
                used.isFinite
            else {
                window = nil
                return
            }
            let resetsAt = try? container.decodeIfPresent(Double.self, forKey: .resetsAt)
            window = UsageWindow(kind: kind, usedPercent: used, resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) })
        }

        private static func kind(_ raw: String) -> UsageWindowKind? {
            switch raw {
            case "five_hour": .fiveHour
            case "weekly": .weekly
            default: nil
            }
        }
    }

    private struct LossyContext: Decodable {
        let usedPercent: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
        }

        init(from decoder: any Decoder) {
            let value = (try? decoder.container(keyedBy: CodingKeys.self))
                .flatMap { try? $0.decodeIfPresent(Double.self, forKey: .usedPercent) }
            usedPercent = value.flatMap { $0.isFinite ? $0 : nil }
        }
    }
}
