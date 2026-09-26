import Foundation
import MochaProtocol

public enum DeviceStoreError: Error, Sendable, Equatable {
    case writeFailed(path: String, errno: Int32)
}

public actor DeviceStore {
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Mocha/devices.json", directoryHint: .notDirectory)
    }

    public nonisolated let fileURL: URL

    public init(fileURL: URL = DeviceStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func devices() throws -> [DeviceRecord] {
        try read()
    }

    public func device(matchingToken token: String) throws -> DeviceRecord? {
        let hash = SecureToken.sha256Hex(token)
        var match: DeviceRecord?
        for record in try read() where SecureToken.constantTimeEquals(record.tokenSha256, hash) {
            match = record
        }
        return match
    }

    public func register(name: String, token: String, at date: Date) throws -> DeviceRecord {
        let record = DeviceRecord(
            id: UUID().uuidString,
            name: name,
            tokenSha256: SecureToken.sha256Hex(token),
            createdAt: date,
            lastSeenAt: date
        )
        var records = try read()
        records.append(record)
        try write(records)
        return record
    }

    public func markSeen(_ id: DeviceID, at date: Date) throws {
        var records = try read()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].lastSeenAt = date
        try write(records)
    }

    public func remove(_ id: DeviceID) throws -> Bool {
        var records = try read()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records.remove(at: index)
        try write(records)
        return true
    }

    private var path: String {
        fileURL.path(percentEncoded: false)
    }

    private func read() throws -> [DeviceRecord] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([DeviceRecord].self, from: data)
    }

    private func write(_ records: [DeviceRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)
        let temporaryPath = directory
            .appending(path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
            .path(percentEncoded: false)
        guard FileManager.default.createFile(atPath: temporaryPath, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw DeviceStoreError.writeFailed(path: temporaryPath, errno: errno)
        }
        guard chmod(temporaryPath, 0o600) == 0, rename(temporaryPath, path) == 0 else {
            let failure = errno
            unlink(temporaryPath)
            throw DeviceStoreError.writeFailed(path: path, errno: failure)
        }
    }
}
