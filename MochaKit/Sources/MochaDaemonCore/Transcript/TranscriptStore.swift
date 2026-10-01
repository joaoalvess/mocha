import Foundation
import MochaProtocol
import MochaTranscript

public actor TranscriptStore: TranscriptProviding {
    private struct FileStamp: Equatable {
        let size: UInt64
        let modificationDate: Date
        let inode: UInt64

        init(_ status: TranscriptFileStatus) {
            size = status.size
            modificationDate = status.modificationDate
            inode = status.inode
        }
    }

    private struct Cached<Value> {
        let stamp: FileStamp
        let value: Value
    }

    public static var defaultProjectsRoot: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects", directoryHint: .isDirectory)
            .path(percentEncoded: false)
    }

    private let locator: TranscriptLocator
    private let hooks: TranscriptStoreHooks
    private let imageStore: TranscriptImageStore?
    private var trackers: [String: TranscriptTracker] = [:]
    private var metaCache: [String: Cached<TranscriptMeta>] = [:]
    private var statsCache: [String: Cached<TranscriptStats>] = [:]
    private var loggedUnknowns: [String: Set<String>] = [:]

    public init(projectsRoot: String = TranscriptStore.defaultProjectsRoot, imageStore: TranscriptImageStore? = nil) {
        self.init(projectsRoot: projectsRoot, hooks: TranscriptStoreHooks(), imageStore: imageStore)
    }

    init(projectsRoot: String, hooks: TranscriptStoreHooks, imageStore: TranscriptImageStore? = nil) {
        locator = TranscriptLocator(projectsRoot: projectsRoot)
        self.hooks = hooks
        self.imageStore = imageStore
    }

    public func open(session: TranscriptSession, limit: Int) async throws -> TranscriptSubscription {
        await tracker(for: session).subscribe(session: session, limit: limit, readsImages: false)
    }

    public func openChat(session: TranscriptSession, limit: Int) async throws -> TranscriptSubscription {
        await tracker(for: session).subscribe(session: session, limit: limit, readsImages: true)
    }

    public func page(session: TranscriptSession, before: String, limit: Int) async throws -> TranscriptPage {
        guard let cursor = TranscriptCursor(before), cursor.sessionId == session.cursorKey else {
            throw TranscriptError.invalidCursor
        }
        guard let slice = await tracker(for: session).page(beforeOffset: cursor.offset, limit: limit) else {
            throw TranscriptError.invalidCursor
        }
        let meta = await meta(forSession: session) ?? TranscriptMeta()
        return TranscriptPage(slice: slice, sessionId: session.cursorKey, meta: meta)
    }

    public func meta(forSession session: TranscriptSession) async -> TranscriptMeta? {
        if let live = await trackers[session.cursorKey]?.followedMeta() {
            return live
        }
        guard let path = locator.path(for: session), let status = TranscriptFileStatus.of(path: path) else { return nil }
        let stamp = FileStamp(status)
        if let cached = metaCache[path], cached.stamp == stamp {
            return cached.value
        }
        guard let header = await Self.readHeader(path: path, mode: session.parseMode) else { return nil }
        let meta = TranscriptMeta(header: header, lastModified: status.modificationDate)
        metaCache[path] = Cached(stamp: stamp, value: meta)
        return meta
    }

    public func stats(forSession session: TranscriptSession) async -> TranscriptStats? {
        guard let path = locator.path(for: session), let status = TranscriptFileStatus.of(path: path) else { return nil }
        let stamp = FileStamp(status)
        if let cached = statsCache[path], cached.stamp == stamp {
            return cached.value
        }
        guard let summary = await Self.summarize(path: path, mode: session.parseMode) else { return nil }
        let stats = TranscriptStats(
            dropped: summary.statistics.dropped,
            orphanResults: summary.statistics.orphanResults,
            unknown: summary.statistics.unknown,
            claudeVersion: summary.header.claudeVersion
        )
        logUnknownNames(Set(stats.unknown.keys), in: path)
        statsCache[path] = Cached(stamp: stamp, value: stats)
        return stats
    }

    func subscriberCount(forSession sessionId: String) async -> Int {
        await trackers[sessionId]?.subscriberCount ?? 0
    }

    func isFollowingFile(forSession sessionId: String) async -> Bool {
        await trackers[sessionId]?.isFollowingFile ?? false
    }

    func isActive(forSession sessionId: String) async -> Bool {
        await trackers[sessionId]?.isActive ?? false
    }

    private func tracker(for session: TranscriptSession) -> TranscriptTracker {
        if let existing = trackers[session.cursorKey] {
            return existing
        }
        let created = TranscriptTracker(session: session, locator: locator, hooks: hooks, imageStore: imageStore)
        trackers[session.cursorKey] = created
        return created
    }

    private func logUnknownNames(_ names: Set<String>, in path: String) {
        let fileName = (path as NSString).lastPathComponent
        var logged = loggedUnknowns[path, default: []]
        for name in names.sorted() where logged.insert(name).inserted {
            transcriptLogger.warning("unknown transcript entry \(name, privacy: .public) in \(fileName, privacy: .public)")
        }
        loggedUnknowns[path] = logged
    }

    @concurrent
    private static func readHeader(path: String, mode: TranscriptParseMode) async -> TranscriptHeader? {
        try? TranscriptHeaderScanner.header(ofFileAt: path, mode: mode)
    }

    @concurrent
    private static func summarize(path: String, mode: TranscriptParseMode) async -> TranscriptDocument? {
        try? TranscriptDocument.summary(path: path, mode: mode)
    }
}
