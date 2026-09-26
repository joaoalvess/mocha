import Foundation
import MochaProtocol

public protocol TranscriptProviding: Sendable {
    func open(session: TranscriptSession, limit: Int) async throws -> TranscriptSubscription
    func page(session: TranscriptSession, before: String, limit: Int) async throws -> TranscriptPage
    func meta(forSession session: TranscriptSession) async -> TranscriptMeta?
    func stats(forSession session: TranscriptSession) async -> TranscriptStats?
}

public struct TranscriptSession: Sendable, Hashable {
    public var sessionId: String
    public var transcriptPath: String?

    public init(sessionId: String, transcriptPath: String? = nil) {
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
    }
}

public struct TranscriptPage: Sendable, Equatable {
    public var items: [ChatItem]
    public var before: String?
    public var hasMore: Bool
    public var meta: TranscriptMeta

    public init(items: [ChatItem], before: String?, hasMore: Bool, meta: TranscriptMeta) {
        self.items = items
        self.before = before
        self.hasMore = hasMore
        self.meta = meta
    }
}

public struct TranscriptSubscription: Sendable {
    public var page: TranscriptPage
    public var deltas: AsyncStream<TranscriptDelta>
    private let onCancel: @Sendable () -> Void

    public init(page: TranscriptPage, deltas: AsyncStream<TranscriptDelta>, onCancel: @escaping @Sendable () -> Void) {
        self.page = page
        self.deltas = deltas
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel()
    }
}

public enum TranscriptDelta: Sendable, Equatable {
    case append([ChatItem])
    case update([ChatItem])
    case meta(TranscriptMeta)
}

public struct TranscriptMeta: Sendable, Equatable {
    public var title: String?
    public var model: String?
    public var branch: String?
    public var permissionMode: String?
    public var claudeVersion: String?
    public var lastModified: Date?

    public init(
        title: String? = nil,
        model: String? = nil,
        branch: String? = nil,
        permissionMode: String? = nil,
        claudeVersion: String? = nil,
        lastModified: Date? = nil
    ) {
        self.title = title
        self.model = model
        self.branch = branch
        self.permissionMode = permissionMode
        self.claudeVersion = claudeVersion
        self.lastModified = lastModified
    }
}

public struct TranscriptStats: Sendable, Equatable {
    public var dropped: Int
    public var orphanResults: Int
    public var unknown: [String: Int]
    public var claudeVersion: String?

    public init(dropped: Int = 0, orphanResults: Int = 0, unknown: [String: Int] = [:], claudeVersion: String? = nil) {
        self.dropped = dropped
        self.orphanResults = orphanResults
        self.unknown = unknown
        self.claudeVersion = claudeVersion
    }
}

public enum TranscriptError: Error, Sendable, Equatable {
    case invalidCursor
}
