import Foundation

public enum AtomicFileError: Error, Sendable, Equatable {
    case writeFailed(path: String, errno: Int32)
}

enum AtomicFile {
    static func write(_ data: Data, to url: URL, permissions: mode_t) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
            .fileSystemPath
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw AtomicFileError.writeFailed(path: temporary, errno: errno) }
        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count, let base = buffer.baseAddress {
                let count = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
        let failure = errno
        guard written, fchmod(descriptor, permissions) == 0, fsync(descriptor) == 0 else {
            close(descriptor)
            unlink(temporary)
            throw AtomicFileError.writeFailed(path: temporary, errno: written ? errno : failure)
        }
        close(descriptor)
        guard rename(temporary, url.fileSystemPath) == 0 else {
            let failure = errno
            unlink(temporary)
            throw AtomicFileError.writeFailed(path: url.fileSystemPath, errno: failure)
        }
    }
}
