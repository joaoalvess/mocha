import Foundation
import os

let uploadLogger = Logger(subsystem: "com.joaoalves.mocha", category: "uploads")

public enum UploadStoreError: Error, Sendable, Equatable {
    case directoryPermissions(path: String, errno: Int32)
}

public struct UploadStore: Sendable {
    public static let maxBodySize = 20 << 20
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let cleanupInterval: Duration = .seconds(6 * 60 * 60)

    public let directory: URL
    private let makeName: @Sendable () -> String

    public init(directory: URL) {
        self.init(directory: directory, makeName: { UUID().uuidString })
    }

    init(directory: URL, makeName: @escaping @Sendable () -> String) {
        self.directory = directory
        self.makeName = makeName
    }

    public func save(_ data: Data, as type: UploadImageType) throws -> String {
        try prepareDirectory()
        let file = directory.appending(path: "\(makeName()).\(type.fileExtension)", directoryHint: .notDirectory)
        try AtomicFile.write(data, to: file, permissions: 0o600)
        uploadLogger.info("saved \(file.lastPathComponent, privacy: .public) (\(data.count, privacy: .public) bytes)")
        return file.fileSystemPath
    }

    @discardableResult
    public func removeExpired(now: Date) -> [String] {
        let directoryPath = directory.fileSystemPath
        guard FileManager.default.fileExists(atPath: directoryPath) else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directoryPath)
        } catch {
            uploadLogger.error("failed to list uploads: \(String(describing: error), privacy: .public)")
            return []
        }
        var removed: [String] = []
        for name in names.sorted() {
            let path = directory.appending(path: name, directoryHint: .notDirectory).fileSystemPath
            guard let modified = Self.regularFileModificationDate(atPath: path),
                  now.timeIntervalSince(modified) > Self.retention else {
                continue
            }
            if unlink(path) == 0 {
                removed.append(name)
            } else {
                let failure = errno
                uploadLogger.error("failed to remove \(name, privacy: .public): errno \(failure, privacy: .public)")
            }
        }
        if !removed.isEmpty {
            uploadLogger.info("removed \(removed.count, privacy: .public) expired uploads")
        }
        return removed
    }

    public func removeExpiredPeriodically(clock: any GatewayClock, every interval: Duration = UploadStore.cleanupInterval) async {
        while true {
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
            removeExpired(now: clock.now())
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.fileSystemPath, 0o700) == 0 else {
            throw UploadStoreError.directoryPermissions(path: directory.fileSystemPath, errno: errno)
        }
    }

    private static func regularFileModificationDate(atPath path: String) -> Date? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }
}
