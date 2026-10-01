import CryptoKit
import Foundation

public struct TranscriptImageStore: Sendable, Hashable {
    public static let fileExtensions: [String: String] = [
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/webp": "webp",
    ]

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func path(forBase64 base64: String, mediaType: String) -> String? {
        guard let fileExtension = Self.fileExtensions[mediaType.lowercased()] else { return nil }
        let name = SHA256.hash(data: Data(base64.utf8)).map { String(format: "%02x", $0) }.joined()
        let path = directory.appending(path: "\(name).\(fileExtension)", directoryHint: .notDirectory).path(percentEncoded: false)
        switch Self.refresh(path) {
        case .refreshed:
            return path
        case .notRegularFile:
            return nil
        case .missing:
            guard let data = Data(base64Encoded: base64), prepareDirectory(), Self.write(data, to: path) else { return nil }
            return path
        }
    }

    private enum Refresh {
        case refreshed
        case missing
        case notRegularFile
    }

    private static func refresh(_ path: String) -> Refresh {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .missing }
        guard info.st_mode & S_IFMT == S_IFREG, utimes(path, nil) == 0 else { return .notRegularFile }
        return .refreshed
    }

    private func prepareDirectory() -> Bool {
        let path = directory.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        return chmod(path, 0o700) == 0
    }

    private static func write(_ data: Data, to path: String) -> Bool {
        let url = URL(filePath: path)
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
            .path(percentEncoded: false)
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }
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
        guard written, fchmod(descriptor, 0o600) == 0, fsync(descriptor) == 0 else {
            close(descriptor)
            unlink(temporary)
            return false
        }
        close(descriptor)
        guard rename(temporary, path) == 0 else {
            unlink(temporary)
            return false
        }
        return true
    }
}
