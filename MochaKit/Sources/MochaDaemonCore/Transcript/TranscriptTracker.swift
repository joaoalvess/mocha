import Dispatch
import Foundation
import MochaProtocol
import MochaTranscript

struct TranscriptStoreHooks: Sendable {
    var afterPageRead: (@Sendable (TranscriptSession) -> Void)?

    init(afterPageRead: (@Sendable (TranscriptSession) -> Void)? = nil) {
        self.afterPageRead = afterPageRead
    }
}

extension TranscriptPage {
    init(slice: TranscriptPageSlice, sessionId: String, meta: TranscriptMeta) {
        let cursor = slice.hasMore ? slice.firstLineOffset.map { TranscriptCursor(sessionId: sessionId, offset: $0).text } : nil
        self.init(items: slice.items, before: cursor, hasMore: slice.hasMore, meta: meta)
    }
}

actor TranscriptTracker {
    private static var fileEvents: DispatchSource.FileSystemEvent {
        [.write, .extend, .delete, .rename, .attrib]
    }

    private static var directoryEvents: DispatchSource.FileSystemEvent {
        [.write, .delete, .rename]
    }

    private var session: TranscriptSession
    private let locator: TranscriptLocator
    private let hooks: TranscriptStoreHooks
    private var subscribers: [UUID: AsyncStream<TranscriptDelta>.Continuation] = [:]
    private var follower: TranscriptFollower?
    private var followedFile: TranscriptFileStatus?
    private var liveMeta = TranscriptMeta()
    private var fileWatch: FileSystemWatch?
    private var directoryWatches: [String: FileSystemWatch] = [:]
    private var events: AsyncStream<Void>.Continuation?
    private var eventLoop: Task<Void, Never>?
    private var loggedUnknowns: Set<String> = []

    init(session: TranscriptSession, locator: TranscriptLocator, hooks: TranscriptStoreHooks) {
        self.session = session
        self.locator = locator
        self.hooks = hooks
    }

    var subscriberCount: Int {
        subscribers.count
    }

    var isActive: Bool {
        eventLoop != nil
    }

    var isFollowingFile: Bool {
        follower != nil
    }

    func subscribe(session requested: TranscriptSession, limit: Int) -> TranscriptSubscription {
        if isActive {
            catchUp()
        } else {
            session = requested
            activate()
        }
        let page = lastPage(limit: limit)
        hooks.afterPageRead?(session)
        let (deltas, continuation) = AsyncStream.makeStream(of: TranscriptDelta.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        if follower != nil {
            startFileWatch()
            catchUp()
        } else {
            attachOrWait()
        }
        return TranscriptSubscription(page: page, deltas: deltas, onCancel: { continuation.finish() })
    }

    func followedMeta() -> TranscriptMeta? {
        guard let follower else { return nil }
        catchUp()
        var meta = liveMeta
        if let modified = follower.status()?.modificationDate {
            meta.lastModified = modified
        }
        return meta
    }

    func unsubscribe(_ id: UUID) {
        guard let continuation = subscribers.removeValue(forKey: id) else { return }
        continuation.finish()
        if subscribers.isEmpty {
            deactivate()
        }
    }

    func page(beforeOffset offset: UInt64, limit: Int) -> TranscriptPageSlice? {
        do {
            if let follower {
                return try follower.page(beforeOffset: offset, limit: limit)
            }
            guard let path = locator.path(for: session) else { return nil }
            return try TranscriptPageReader(path: path).page(beforeOffset: offset, limit: limit)
        } catch TranscriptFileError.notFound {
            return nil
        } catch {
            transcriptLogger.error("page read failed for \(self.session.sessionId, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func activate() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        events = continuation
        eventLoop = Task { [weak self] in
            for await _ in stream {
                await self?.handleFileSystemEvent()
            }
        }
        openFollower(start: .afterExistingLines)
    }

    private func deactivate() {
        fileWatch?.cancel()
        fileWatch = nil
        cancelDirectoryWatches()
        events?.finish()
        events = nil
        eventLoop?.cancel()
        eventLoop = nil
        follower = nil
        followedFile = nil
        liveMeta = TranscriptMeta()
    }

    @discardableResult
    private func openFollower(start: TranscriptFollower.Start) -> Bool {
        guard let path = locator.path(for: session) else { return false }
        do {
            let opened = try TranscriptFollower(path: path, start: start)
            follower = opened
            followedFile = opened.status()
            liveMeta = TranscriptMeta(header: opened.header, lastModified: followedFile?.modificationDate)
            return true
        } catch TranscriptFileError.notFound {
            return false
        } catch {
            transcriptLogger.error("cannot open transcript \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func lastPage(limit: Int) -> TranscriptPage {
        guard let follower else {
            return TranscriptPage(slice: .empty, sessionId: session.sessionId, meta: liveMeta)
        }
        do {
            return TranscriptPage(slice: try follower.lastPage(limit: limit), sessionId: session.sessionId, meta: liveMeta)
        } catch {
            transcriptLogger.error("page read failed for \(self.session.sessionId, privacy: .public): \(String(describing: error), privacy: .public)")
            return TranscriptPage(slice: .empty, sessionId: session.sessionId, meta: liveMeta)
        }
    }

    private func handleFileSystemEvent() {
        guard isActive else { return }
        guard let follower else {
            attachOrWait()
            return
        }
        let descriptorStatus = follower.status()
        guard let followedFile,
              let pathStatus = TranscriptFileStatus.of(path: follower.path),
              pathStatus.isSameFile(as: followedFile),
              (descriptorStatus?.linkCount ?? 0) > 0 else {
            catchUp()
            detachFollower()
            attachOrWait()
            return
        }
        if let size = descriptorStatus?.size, size < follower.endOffset + UInt64(follower.pendingByteCount) {
            transcriptLogger.warning("transcript truncated, reading again: \(follower.path, privacy: .public)")
            detachFollower()
            attachOrWait()
            return
        }
        catchUp()
    }

    private func detachFollower() {
        fileWatch?.cancel()
        fileWatch = nil
        follower = nil
        followedFile = nil
    }

    private func attachOrWait() {
        guard follower == nil else { return }
        if openFollower(start: .beginningOfFile) {
            cancelDirectoryWatches()
            startFileWatch()
            catchUp()
        } else {
            refreshDirectoryWatches()
        }
    }

    private func startFileWatch() {
        guard let follower, fileWatch == nil else { return }
        let events = events
        fileWatch = FileSystemWatch(path: follower.path, events: Self.fileEvents) {
            events?.yield(())
        }
    }

    private func refreshDirectoryWatches() {
        let targets = Set(locator.directoriesToWatch(for: session))
        for (path, watch) in directoryWatches where !targets.contains(path) {
            watch.cancel()
            directoryWatches[path] = nil
        }
        let events = events
        for path in targets where directoryWatches[path] == nil {
            directoryWatches[path] = FileSystemWatch(path: path, events: Self.directoryEvents) {
                events?.yield(())
            }
        }
    }

    private func cancelDirectoryWatches() {
        for watch in directoryWatches.values {
            watch.cancel()
        }
        directoryWatches.removeAll()
    }

    private func catchUp() {
        guard let follower else { return }
        let update: TranscriptFollowUpdate
        do {
            update = try follower.readAppendedLines()
        } catch {
            transcriptLogger.error("transcript read failed for \(follower.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        guard update.lineCount > 0 else { return }
        let meta = TranscriptMeta(header: follower.header, lastModified: follower.status()?.modificationDate)
        let batch = TranscriptChangeBatch(update.changes)
        var deltas: [TranscriptDelta] = []
        if !batch.updated.isEmpty {
            deltas.append(.update(batch.updated))
        }
        if !batch.appended.isEmpty {
            deltas.append(.append(batch.appended))
        }
        if !meta.hasSameContent(as: liveMeta) {
            deltas.append(.meta(meta))
        }
        liveMeta = meta
        logUnknownNames(update.unknownNames, in: follower.path)
        for continuation in subscribers.values {
            for delta in deltas {
                continuation.yield(delta)
            }
        }
    }

    private func logUnknownNames(_ names: Set<String>, in path: String) {
        let fileName = (path as NSString).lastPathComponent
        for name in names.sorted() where loggedUnknowns.insert(name).inserted {
            transcriptLogger.warning("unknown transcript entry \(name, privacy: .public) in \(fileName, privacy: .public)")
        }
    }
}
