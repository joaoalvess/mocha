import Darwin
import Foundation

struct UsageFileStamp: Sendable, Equatable {
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int

    static func of(_ url: URL) -> UsageFileStamp? {
        var info = stat()
        guard stat(url.fileSystemPath, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return UsageFileStamp(
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec
        )
    }

    var modificationDate: Date {
        Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1e9)
    }
}
