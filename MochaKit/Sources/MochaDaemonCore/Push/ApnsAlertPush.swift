import Foundation

public enum ApnsInterruptionLevel: String, Sendable, Equatable {
    case active
    case timeSensitive = "time-sensitive"
}

public struct ApnsAlertPush: Sendable, Equatable {
    public var title: String
    public var body: String
    public var sound: String?
    public var threadId: String?
    public var category: String?
    public var interruptionLevel: ApnsInterruptionLevel?
    public var agentId: String?
    public var kind: String
    public var requestId: String?
    public var sentAt: Date

    public init(
        title: String,
        body: String,
        sound: String? = "default",
        threadId: String? = nil,
        category: String? = nil,
        interruptionLevel: ApnsInterruptionLevel? = nil,
        agentId: String? = nil,
        kind: String,
        requestId: String? = nil,
        sentAt: Date
    ) {
        self.title = title
        self.body = body
        self.sound = sound
        self.threadId = threadId
        self.category = category
        self.interruptionLevel = interruptionLevel
        self.agentId = agentId
        self.kind = kind
        self.requestId = requestId
        self.sentAt = sentAt
    }

    public func payload() throws -> Data {
        let body = Body(
            aps: Aps(
                alert: Alert(title: title, body: self.body),
                sound: sound,
                threadId: threadId,
                category: category,
                interruptionLevel: interruptionLevel?.rawValue
            ),
            agentId: agentId,
            kind: kind,
            requestId: requestId,
            sentAt: ApnsPayloadEncoding.milliseconds(sentAt)
        )
        return try ApnsPayloadEncoding.encoder.encode(body)
    }

    private struct Body: Encodable {
        let aps: Aps
        let agentId: String?
        let kind: String
        let requestId: String?
        let sentAt: Int64
    }

    private struct Aps: Encodable {
        let alert: Alert
        let sound: String?
        let threadId: String?
        let category: String?
        let interruptionLevel: String?

        enum CodingKeys: String, CodingKey {
            case alert
            case sound
            case threadId = "thread-id"
            case category
            case interruptionLevel = "interruption-level"
        }
    }

    private struct Alert: Encodable {
        let title: String
        let body: String
    }
}

enum ApnsPayloadEncoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func unixSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }
}
