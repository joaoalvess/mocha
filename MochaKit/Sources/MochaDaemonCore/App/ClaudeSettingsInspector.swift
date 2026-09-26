import Foundation

public struct ClaudeHooksSummary: Sendable, Equatable {
    public var mochaEvents: [String]
    public var moshiEvents: [String]

    public init(mochaEvents: [String] = [], moshiEvents: [String] = []) {
        self.mochaEvents = mochaEvents
        self.moshiEvents = moshiEvents
    }
}

public enum ClaudeSettingsInspection: Sendable, Equatable {
    case missing
    case unreadable
    case hooks(ClaudeHooksSummary)
}

public struct ClaudeSettingsInspector: Sendable {
    public static let mochaMarker = "127.0.0.1:47420/hooks/"
    public static let moshiMarker = "moshi-hook"

    let url: URL

    public init(url: URL = DaemonPaths().claudeSettingsFile) {
        self.url = url
    }

    public func inspect() -> ClaudeSettingsInspection {
        guard FileManager.default.fileExists(atPath: url.fileSystemPath) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unreadable }
        var summary = ClaudeHooksSummary()
        let events = object["hooks"] as? [String: Any] ?? [:]
        for event in events.keys.sorted() {
            let targets = Self.targets(in: events[event])
            if targets.contains(where: { $0.contains(Self.mochaMarker) }) {
                summary.mochaEvents.append(event)
            }
            if targets.contains(where: { $0.contains(Self.moshiMarker) }) {
                summary.moshiEvents.append(event)
            }
        }
        return .hooks(summary)
    }

    private static func targets(in value: Any?) -> [String] {
        guard let groups = value as? [[String: Any]] else { return [] }
        return groups.flatMap { group -> [String] in
            let hooks = group["hooks"] as? [[String: Any]] ?? []
            return hooks.flatMap { hook in
                [hook["command"] as? String, hook["url"] as? String].compactMap { $0 }
            }
        }
    }
}
