import Foundation
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct TranscriptImageCacheTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let day: TimeInterval = 24 * 60 * 60
    private static let mebibyte = 1 << 20

    private func withCacheDirectory(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mocha-transcript-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root.appending(path: "com.joaoalves.mocha/transcript-images", directoryHint: .isDirectory))
    }

    private func file(_ name: String, in directory: URL, age: TimeInterval, size: Int = 1) throws {
        let url = directory.appending(path: name)
        try TestImages.sparseFile(at: url, size: size)
        try setModificationDate(Self.now.addingTimeInterval(-age), of: url)
    }

    @Test func constantsFollowTheContract() {
        #expect(TranscriptImageCache.retention == 7 * Self.day)
        #expect(TranscriptImageCache.maxTotalSize == 200 * Self.mebibyte)
        #expect(TranscriptImageCache.cleanupInterval == .seconds(6 * 60 * 60))
    }

    @Test func storeWritesIntoTheCacheDirectory() async throws {
        try await withCacheDirectory { directory in
            let cache = TranscriptImageCache(directory: directory)
            #expect(cache.store == TranscriptImageStore(directory: directory))
        }
    }

    @Test func removeExpiredDeletesOnlyFilesUnusedForMoreThanSevenDays() async throws {
        try await withCacheDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ages: [String: TimeInterval] = [
                "antigo.png": 30 * Self.day,
                "passou.jpg": 7 * Self.day + 1,
                "limite.gif": 7 * Self.day,
                "quase.webp": 7 * Self.day - 1,
                "novo.png": Self.day,
                ".abc.png.sobra.tmp": 8 * Self.day,
            ]
            for (name, age) in ages {
                try file(name, in: directory, age: age)
            }
            let folder = directory.appending(path: "pasta", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try setModificationDate(Self.now.addingTimeInterval(-30 * Self.day), of: folder)

            let removed = TranscriptImageCache(directory: directory).removeExpired(now: Self.now)

            #expect(removed == [".abc.png.sobra.tmp", "antigo.png", "passou.jpg"])
            #expect(directoryEntries(directory) == ["limite.gif", "novo.png", "pasta", "quase.webp"])
        }
    }

    @Test func aboveTheCapTheOldestUsedGoFirstUntilTheTotalFits() async throws {
        try await withCacheDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file("a.png", in: directory, age: 4 * Self.day, size: 70 * Self.mebibyte)
            try file("b.png", in: directory, age: 3 * Self.day, size: 60 * Self.mebibyte)
            try file("c.jpg", in: directory, age: 2 * Self.day, size: 100 * Self.mebibyte)
            try file("d.jpg", in: directory, age: Self.day, size: 50 * Self.mebibyte)
            try file("velho.png", in: directory, age: 10 * Self.day, size: 300 * Self.mebibyte)

            let removed = TranscriptImageCache(directory: directory).removeExpired(now: Self.now)

            #expect(removed == ["velho.png", "a.png", "b.png"])
            #expect(directoryEntries(directory) == ["c.jpg", "d.jpg"])
        }
    }

    @Test func exactlyAtTheCapNothingMoreIsRemoved() async throws {
        try await withCacheDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file("a.png", in: directory, age: 2 * Self.day, size: 120 * Self.mebibyte)
            try file("b.png", in: directory, age: Self.day, size: 80 * Self.mebibyte)

            #expect(TranscriptImageCache(directory: directory).removeExpired(now: Self.now).isEmpty)
            #expect(directoryEntries(directory) == ["a.png", "b.png"])

            try file("c.png", in: directory, age: 0, size: 1)
            #expect(TranscriptImageCache(directory: directory).removeExpired(now: Self.now) == ["a.png"])
        }
    }

    @Test func filesUsedAtTheSameTimeGoByName() async throws {
        try await withCacheDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file("b.png", in: directory, age: Self.day, size: 150 * Self.mebibyte)
            try file("a.png", in: directory, age: Self.day, size: 150 * Self.mebibyte)

            #expect(TranscriptImageCache(directory: directory).removeExpired(now: Self.now) == ["a.png"])
        }
    }

    @Test func removeExpiredWithoutTheDirectoryDoesNothing() async throws {
        try await withCacheDirectory { directory in
            #expect(TranscriptImageCache(directory: directory).removeExpired(now: Self.now).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: directory.fileSystemPath))
        }
    }

    @Test func periodicCleanupRunsEverySixHours() async throws {
        try await withCacheDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file("vence.png", in: directory, age: 7 * Self.day - 3 * 60 * 60)
            try file("recente.png", in: directory, age: Self.day)
            let clock = ManualClock(origin: Self.now)
            let cache = TranscriptImageCache(directory: directory)

            let task = Task {
                await cache.removeExpiredPeriodically(clock: clock)
            }
            try await clock.waitForSleepers(1)
            #expect(clock.pendingDelays == [.seconds(6 * 60 * 60)])
            #expect(directoryEntries(directory) == ["recente.png", "vence.png"])

            clock.advance(by: .seconds(6 * 60 * 60))
            _ = try await eventually { directoryEntries(directory) == ["recente.png"] ? true : nil }
            try await clock.waitForSleepers(1)
            #expect(clock.pendingDelays == [.seconds(6 * 60 * 60)])

            task.cancel()
            await task.value
            #expect(clock.sleeperCount == 0)
        }
    }

    @Test func markUsedRenewsOnlyFilesDirectlyInTheCache() async throws {
        try await withCacheDirectory { directory in
            let nested = directory.appending(path: "sub", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let outsideDirectory = directory.deletingLastPathComponent()
            try file("abc.png", in: directory, age: 30 * Self.day)
            try file("fundo.png", in: nested, age: 30 * Self.day)
            try file("fora.png", in: outsideDirectory, age: 30 * Self.day)
            let cache = TranscriptImageCache(directory: directory)

            for url in [directory.appending(path: "abc.png"), nested.appending(path: "fundo.png"), outsideDirectory.appending(path: "fora.png")] {
                cache.markUsed(url.resolvingSymlinksInPath())
            }

            #expect(try Date().timeIntervalSince(modificationDate(directory.appending(path: "abc.png"))) < 60)
            #expect(try modificationDate(nested.appending(path: "fundo.png")) == Self.now.addingTimeInterval(-30 * Self.day))
            #expect(try modificationDate(outsideDirectory.appending(path: "fora.png")) == Self.now.addingTimeInterval(-30 * Self.day))
        }
    }

    private func modificationDate(_ url: URL) throws -> Date {
        try #require(try FileManager.default.attributesOfItem(atPath: url.fileSystemPath)[.modificationDate] as? Date)
    }
}
