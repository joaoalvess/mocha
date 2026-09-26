#if DEBUG
import Foundation

struct PushProbeSnapshot: Codable, Sendable {
    struct Activity: Codable, Sendable {
        let id: String
        let state: String
        let updateToken: String?
    }

    let writtenAt: Date
    let apnsToken: String?
    let env: String
    let envSource: String
    let authorization: String
    let pushToStartToken: String?
    let activities: [Activity]
}

struct PushProbeEvent: Codable, Sendable {
    let at: Date
    let kind: String
    let detail: String
    let sentAt: Date?
    let delayMs: Double?
}

struct PushProbeFiles: Sendable {
    let snapshotURL = URL.documentsDirectory.appending(path: "push-probe.json")
    let eventsURL = URL.documentsDirectory.appending(path: "push-probe-events.jsonl")

    func write(_ snapshot: PushProbeSnapshot) throws {
        try Self.encoder(pretty: true).encode(snapshot).write(to: snapshotURL, options: .atomic)
    }

    func append(_ event: PushProbeEvent) throws {
        var line = try Self.encoder(pretty: false).encode(event)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: eventsURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: eventsURL, options: .atomic)
        }
    }

    private static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }
}
#endif
