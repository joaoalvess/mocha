import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct UploadStoreTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let day: TimeInterval = 24 * 60 * 60

    private func withUploadsDirectory(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mocha-uploads-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root.appending(path: "Mocha/uploads", directoryHint: .isDirectory))
    }

    @Test func saveCreatesOwnerOnlyDirectoryAndFileWithAGeneratedName() async throws {
        try await withUploadsDirectory { directory in
            let store = UploadStore(directory: directory)

            let path = try store.save(Data(UploadSamples.jpeg), as: .jpeg)

            let file = URL(filePath: path)
            #expect(file.deletingLastPathComponent().fileSystemPath == directory.fileSystemPath)
            #expect(isUUIDFileName(file.lastPathComponent, extension: "jpg"))
            #expect(fileMode(directory) == 0o700)
            #expect(fileMode(directory.deletingLastPathComponent()) == 0o700)
            #expect(fileMode(file) == 0o600)
            #expect(try Data(contentsOf: file) == Data(UploadSamples.jpeg))
        }
    }

    @Test func saveTightensAnExistingDirectoryTo0700() async throws {
        try await withUploadsDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            #expect(fileMode(directory) == 0o755)

            _ = try UploadStore(directory: directory).save(Data(UploadSamples.png), as: .png)

            #expect(fileMode(directory) == 0o700)
        }
    }

    @Test(arguments: UploadImageType.allCases)
    func extensionFollowsTheContentType(_ type: UploadImageType) async throws {
        try await withUploadsDirectory { directory in
            let path = try UploadStore(directory: directory).save(Data(UploadSamples.bytes(for: type)), as: type)
            let expected = ["image/jpeg": "jpg", "image/png": "png", "image/heic": "heic"][type.rawValue]
            #expect(type.fileExtension == expected)
            #expect(isUUIDFileName(URL(filePath: path).lastPathComponent, extension: try #require(expected)))
        }
    }

    @Test func contentTypeParsingAcceptsOnlyTheThreeImageTypes() {
        #expect(UploadImageType(contentType: "image/jpeg") == .jpeg)
        #expect(UploadImageType(contentType: "IMAGE/PNG") == .png)
        #expect(UploadImageType(contentType: "image/heic; charset=binary") == .heic)
        #expect(UploadImageType(contentType: nil) == nil)
        #expect(UploadImageType(contentType: "") == nil)
        #expect(UploadImageType(contentType: "image/jpg") == nil)
        #expect(UploadImageType(contentType: "image/gif") == nil)
        #expect(UploadImageType(contentType: "application/octet-stream") == nil)
    }

    @Test func saveLeavesNoTemporaryFiles() async throws {
        try await withUploadsDirectory { directory in
            let store = UploadStore(directory: directory)
            let first = URL(filePath: try store.save(Data(UploadSamples.jpeg), as: .jpeg)).lastPathComponent
            let second = URL(filePath: try store.save(Data(UploadSamples.heic), as: .heic)).lastPathComponent

            #expect(first != second)
            #expect(directoryEntries(directory) == [first, second].sorted())
        }
    }

    @Test func saveReplacesTheTargetByRenameInsteadOfWritingInPlace() async throws {
        try await withUploadsDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appending(path: "fixo.png")
            try Data("antigo".utf8).write(to: target)
            let before = try #require(inode(target))

            let path = try UploadStore(directory: directory, makeName: { "fixo" }).save(Data(UploadSamples.png), as: .png)

            #expect(path == target.fileSystemPath)
            #expect(try Data(contentsOf: target) == Data(UploadSamples.png))
            #expect(inode(target) != before)
            #expect(fileMode(target) == 0o600)
            #expect(directoryEntries(directory) == ["fixo.png"])
        }
    }

    @Test func failedWriteLeavesNoPartialOrTemporaryFile() async throws {
        try await withUploadsDirectory { directory in
            let blocker = directory.appending(path: "fixo.jpg", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: blocker.appending(path: "dentro"))

            #expect(throws: AtomicFileError.self) {
                try UploadStore(directory: directory, makeName: { "fixo" }).save(Data(UploadSamples.jpeg), as: .jpeg)
            }

            #expect(directoryEntries(directory) == ["fixo.jpg"])
            #expect(directoryEntries(blocker) == ["dentro"])
        }
    }

    @Test func removeExpiredDeletesOnlyFilesOlderThanSevenDays() async throws {
        try await withUploadsDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ages: [String: TimeInterval] = [
                "antigo.jpg": 30 * Self.day,
                "passou.png": 7 * Self.day + 1,
                "limite.heic": 7 * Self.day,
                "quase.jpg": 7 * Self.day - 1,
                "novo.jpg": Self.day,
                ".fixo.jpg.sobra.tmp": 8 * Self.day,
            ]
            for (name, age) in ages {
                let file = directory.appending(path: name)
                try Data(name.utf8).write(to: file)
                try setModificationDate(Self.now.addingTimeInterval(-age), of: file)
            }
            let folder = directory.appending(path: "pasta", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try setModificationDate(Self.now.addingTimeInterval(-30 * Self.day), of: folder)

            let removed = UploadStore(directory: directory).removeExpired(now: Self.now)

            #expect(removed == [".fixo.jpg.sobra.tmp", "antigo.jpg", "passou.png"])
            #expect(directoryEntries(directory) == ["limite.heic", "novo.jpg", "pasta", "quase.jpg"])
        }
    }

    @Test func removeExpiredWithoutTheDirectoryDoesNothing() async throws {
        try await withUploadsDirectory { directory in
            #expect(UploadStore(directory: directory).removeExpired(now: Self.now).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: directory.fileSystemPath))
        }
    }

    @Test func periodicCleanupRunsEverySixHours() async throws {
        try await withUploadsDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let expiring = directory.appending(path: "vence.jpg")
            let recent = directory.appending(path: "recente.jpg")
            try Data("a".utf8).write(to: expiring)
            try Data("b".utf8).write(to: recent)
            try setModificationDate(Self.now.addingTimeInterval(-(7 * Self.day) + 3 * 60 * 60), of: expiring)
            try setModificationDate(Self.now.addingTimeInterval(-Self.day), of: recent)
            let clock = ManualClock(origin: Self.now)
            let store = UploadStore(directory: directory)

            let task = Task {
                await store.removeExpiredPeriodically(clock: clock)
            }
            try await clock.waitForSleepers(1)
            #expect(clock.pendingDelays == [.seconds(6 * 60 * 60)])
            #expect(directoryEntries(directory) == ["recente.jpg", "vence.jpg"])

            clock.advance(by: .seconds(6 * 60 * 60))
            _ = try await eventually { directoryEntries(directory) == ["recente.jpg"] ? true : nil }
            try await clock.waitForSleepers(1)
            #expect(clock.pendingDelays == [.seconds(6 * 60 * 60)])

            task.cancel()
            await task.value
            #expect(clock.sleeperCount == 0)
        }
    }
}
