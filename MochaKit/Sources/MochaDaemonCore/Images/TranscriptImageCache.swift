import Foundation
import MochaTranscript
import os

let transcriptImageLogger = Logger(subsystem: "com.joaoalves.mocha", category: "transcript-images")

public struct TranscriptImageCache: Sendable {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let maxTotalSize = 200 << 20
    public static let cleanupInterval: Duration = .seconds(6 * 60 * 60)

    private struct Entry {
        let name: String
        let path: String
        let size: Int
        let modified: Date
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var store: TranscriptImageStore {
        TranscriptImageStore(directory: directory)
    }

    func markUsed(_ file: URL) {
        let cached = directory.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let parent = file.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
        guard Self.withoutTrailingSlash(parent) == Self.withoutTrailingSlash(cached) else { return }
        utimes(file.standardizedFileURL.path(percentEncoded: false), nil)
    }

    @discardableResult
    public func removeExpired(now: Date) -> [String] {
        let directoryPath = directory.fileSystemPath
        guard FileManager.default.fileExists(atPath: directoryPath) else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directoryPath)
        } catch {
            transcriptImageLogger.error("failed to list transcript images: \(String(describing: error), privacy: .public)")
            return []
        }
        var kept: [Entry] = []
        var removed: [String] = []
        for name in names.sorted() {
            let path = directory.appending(path: name, directoryHint: .notDirectory).fileSystemPath
            guard let entry = Self.regularFile(name: name, path: path) else { continue }
            if now.timeIntervalSince(entry.modified) > Self.retention {
                if Self.remove(entry) {
                    removed.append(name)
                }
            } else {
                kept.append(entry)
            }
        }
        var total = kept.reduce(0) { $0 + $1.size }
        for entry in kept.sorted(by: { ($0.modified, $0.name) < ($1.modified, $1.name) }) where total > Self.maxTotalSize {
            if Self.remove(entry) {
                removed.append(entry.name)
                total -= entry.size
            }
        }
        if !removed.isEmpty {
            transcriptImageLogger.info("removed \(removed.count, privacy: .public) transcript images")
        }
        return removed
    }

    public func removeExpiredPeriodically(clock: any GatewayClock, every interval: Duration = TranscriptImageCache.cleanupInterval) async {
        while true {
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
            removeExpired(now: clock.now())
        }
    }

    private static func remove(_ entry: Entry) -> Bool {
        guard unlink(entry.path) == 0 else {
            let failure = errno
            transcriptImageLogger.error("failed to remove \(entry.name, privacy: .public): errno \(failure, privacy: .public)")
            return false
        }
        return true
    }

    private static func regularFile(name: String, path: String) -> Entry? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let modified = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        return Entry(name: name, path: path, size: Int(info.st_size), modified: modified)
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
