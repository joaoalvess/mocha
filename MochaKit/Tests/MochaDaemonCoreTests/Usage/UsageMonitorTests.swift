import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct UsageMonitorTests {
    @Test func fixtureGivesWindowsFetchedAtContextsPlanAndMaskedAccount() async throws {
        try await withUsageMonitor(
            cache: try Fixtures.data(UsageSample.cacheFixture),
            account: try Fixtures.data(UsageSample.accountFixture)
        ) { harness async throws in
            let snapshot = try #require(await harness.monitor.snapshot)
            #expect(snapshot == UsageSample.fixtureSnapshot)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionA) == 36)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionB) == 81.5)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionC) == nil)
            #expect(harness.watcher.watchedDirectories == [harness.cacheFile.deletingLastPathComponent()])

            let envelope = try JSONDecoder().decode(ServerEnvelope.self, from: try Fixtures.data("protocol/server.usage.json"))
            #expect(envelope.message == .usage(snapshot))
        }
    }

    @Test func renamedCacheFileBecomesAnEventAfterTheDebounce() async throws {
        try await withUsageMonitor(cache: try Fixtures.data(UsageSample.cacheFixture)) { harness async throws in
            var events = harness.monitor.events().makeAsyncIterator()
            let first = try #require(await events.next())
            #expect(first?.fetchedAt == UsageSample.fetchedAt)
            #expect(first?.plan == nil)

            try harness.replaceCache(UsageSample.cache(fetchedAt: 1_790_393_000, fiveHour: 20, weekly: 72, contexts: [Sample.sessionA: 50]))
            harness.watcher.signal()
            harness.watcher.signal()
            try await harness.clock.waitForSleepers(1)
            #expect(harness.clock.sleeperCount == 1)
            harness.clock.advance(by: .milliseconds(499))
            #expect(await harness.monitor.snapshot?.fetchedAt == UsageSample.fetchedAt)
            harness.clock.advance(by: .milliseconds(1))

            let changed = try #require(await events.next())
            #expect(changed?.fetchedAt == Date(timeIntervalSince1970: 1_790_393_000))
            #expect(changed?.windows.map(\.usedPercent) == [20, 72])
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionA) == 50)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionB) == nil)
        }
    }

    @Test func directoryEventWithTheSameFilePublishesNothing() async throws {
        try await withUsageMonitor(cache: try Fixtures.data(UsageSample.cacheFixture)) { harness async throws in
            let received = Mutex<[UsageSnapshot?]>([])
            let events = harness.monitor.events()
            let consumer = Task {
                for await snapshot in events {
                    received.withLock { $0.append(snapshot) }
                }
            }
            defer { consumer.cancel() }
            _ = try await eventually { received.withLock { $0.count == 1 ? true : nil } }

            try await harness.changeAndSettle()
            try harness.replaceCache(UsageSample.cache(fetchedAt: 1_790_393_100, fiveHour: 1, weekly: 2))
            try await harness.changeAndSettle()
            _ = try await eventually { received.withLock { $0.count >= 2 ? true : nil } }
            #expect(received.withLock { $0.map { $0?.fetchedAt } } == [UsageSample.fetchedAt, Date(timeIntervalSince1970: 1_790_393_100)])
        }
    }

    @Test func missingCacheFileMeansNoUsageUntilItAppears() async throws {
        try await withUsageMonitor(account: try Fixtures.data(UsageSample.accountFixture)) { harness async throws in
            #expect(await harness.monitor.snapshot == nil)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionA) == nil)
            var events = harness.monitor.events().makeAsyncIterator()
            #expect(try #require(await events.next()) == nil)

            try harness.replaceCache(try Fixtures.data(UsageSample.cacheFixture))
            try await harness.changeAndSettle()
            #expect(try #require(await events.next()) == UsageSample.fixtureSnapshot)

            try harness.removeCache()
            try await harness.changeAndSettle()
            #expect(try #require(await events.next()) == nil)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionA) == nil)
        }
    }

    @Test(arguments: [
        "não é json",
        "[]",
        #"{"windows": []}"#,
        #"{"fetched_at_unix": "ontem"}"#,
    ])
    func invalidCacheFileMeansNoUsage(content: String) async throws {
        try await withUsageMonitor(cache: Data(content.utf8), account: try Fixtures.data(UsageSample.accountFixture)) { harness async throws in
            #expect(await harness.monitor.snapshot == nil)
            #expect(await harness.monitor.contextUsedPercent(forSession: Sample.sessionA) == nil)
        }
    }

    @Test func otherWindowKindsAndBrokenEntriesAreIgnored() {
        let data = Data(#"""
            {
              "fetched_at_unix": 1790392863.5,
              "windows": [
                {"kind": "weekly_opus", "used_percent": 10, "resets_at": 1790604000},
                {"kind": "five_hour", "used_percent": "muito"},
                {"kind": "weekly", "used_percent": 71, "resets_at": null},
                "lixo",
                {"kind": "five_hour", "used_percent": 12}
              ],
              "session_contexts": {
                "a": {"used_percent": 40},
                "b": {"used_percent": "cheio"},
                "c": {"cache": {}},
                "d": 3
              }
            }
            """#.utf8)
        let cache = StatuslineCache.parse(data)
        #expect(cache?.fetchedAt == Date(timeIntervalSince1970: 1_790_392_863.5))
        #expect(cache?.windows == [UsageWindow(kind: .weekly, usedPercent: 71), UsageWindow(kind: .fiveHour, usedPercent: 12)])
        #expect(cache?.contexts == ["a": 40])
    }

    @Test(arguments: [
        ("default_claude_max_20x", "Max 20x"),
        ("default_claude_max_5x", "Max 5x"),
        ("claude_pro", "Pro"),
        ("DEFAULT_CLAUDE_MAX_20X", "Max 20x"),
        ("default_claude_ai", nil),
        ("enterprise", nil),
        ("", nil),
    ] as [(String, String?)])
    func planComesFromTheRateLimitTier(tier: String, expected: String?) {
        #expect(ClaudeAccount.plan(forTier: tier) == expected)
    }

    @Test(arguments: [
        ("dev@example.com", "d•••@e•••.com"),
        ("joao.alves@mail.company.co", "j•••@m•••.co"),
        ("x@localhost", "x•••@l•••"),
        ("sem-arroba", nil),
        ("@example.com", nil),
        ("dev@", nil),
        ("a@b@c.com", nil),
    ] as [(String, String?)])
    func accountIsTheMaskedEmail(email: String, expected: String?) {
        #expect(ClaudeAccount.maskedEmail(email) == expected)
    }

    @Test func accountFileReadsOnlyTheTwoKeys() {
        #expect(ClaudeAccount.parse(Data(#"{"oauthAccount": {"emailAddress": "dev@example.com"}, "projects": {"x": 1}}"#.utf8))
            == ClaudeAccount(plan: nil, account: "d•••@e•••.com"))
        #expect(ClaudeAccount.parse(Data(#"{"oauthAccount": {"organizationRateLimitTier": 5, "emailAddress": "dev@example.com"}}"#.utf8))
            == ClaudeAccount(plan: nil, account: "d•••@e•••.com"))
        #expect(ClaudeAccount.parse(Data(#"{"oauthAccount": "x"}"#.utf8)) == ClaudeAccount())
        #expect(ClaudeAccount.parse(Data("lixo".utf8)) == ClaudeAccount())
    }

    @Test func withoutTheAccountFileTheUsageHasNoPlanNorAccount() async throws {
        try await withUsageMonitor(cache: try Fixtures.data(UsageSample.cacheFixture)) { harness async throws in
            let snapshot = try #require(await harness.monitor.snapshot)
            #expect(snapshot.plan == nil)
            #expect(snapshot.account == nil)
            #expect(snapshot.windows == UsageSample.fixtureSnapshot.windows)
        }
    }

    @Test func accountIsCachedByModificationTime() async throws {
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        try await withUsageMonitor(account: try Fixtures.data(UsageSample.accountFixture)) { harness async throws in
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: harness.accountFile.path(percentEncoded: false))
            try harness.replaceCache(UsageSample.cache(fetchedAt: 1_790_393_000, fiveHour: 1, weekly: 1))
            try await harness.changeAndSettle()
            #expect(await harness.monitor.snapshot?.account == "d•••@e•••.com")

            let original = try Data(contentsOf: harness.accountFile)
            let edited = Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "dev@", with: "zed@").utf8)
            let handle = try FileHandle(forWritingTo: harness.accountFile)
            try handle.write(contentsOf: edited)
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: harness.accountFile.path(percentEncoded: false))
            try harness.replaceCache(UsageSample.cache(fetchedAt: 1_790_393_001, fiveHour: 1, weekly: 1))
            try await harness.changeAndSettle()
            #expect(await harness.monitor.snapshot?.fetchedAt == Date(timeIntervalSince1970: 1_790_393_001))
            #expect(await harness.monitor.snapshot?.account == "d•••@e•••.com")

            try FileManager.default.setAttributes([.modificationDate: stamp.addingTimeInterval(60)], ofItemAtPath: harness.accountFile.path(percentEncoded: false))
            try harness.replaceCache(UsageSample.cache(fetchedAt: 1_790_393_002, fiveHour: 1, weekly: 1))
            try await harness.changeAndSettle()
            #expect(await harness.monitor.snapshot?.fetchedAt == Date(timeIntervalSince1970: 1_790_393_002))
            #expect(await harness.monitor.snapshot?.account == "z•••@e•••.com")
        }
    }

    @Test func stopFinishesTheEvents() async throws {
        try await withUsageMonitor(cache: try Fixtures.data(UsageSample.cacheFixture)) { harness async throws in
            var events = harness.monitor.events().makeAsyncIterator()
            _ = await events.next()
            await harness.monitor.stop()
            #expect(await events.next() == nil)
            _ = try await eventually { harness.watcher.subscriberCount == 0 ? true : nil }
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct DispatchDirectoryWatcherTests {
    @Test func renameIntoTheDirectoryIsAChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let count = try await Self.countChanges(of: directory, watcher: DispatchDirectoryWatcher()) {
            try UsageHarness.replace(directory.appending(path: "claude-statusline.json"), with: Data("{}".utf8))
        }
        #expect(count > 0)
    }

    @Test func directoryThatAppearsLaterIsWatchedAfterTheRetry() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "mocha-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directory = parent.appending(path: "plugin", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: parent) }
        let count = try await Self.countChanges(of: directory, watcher: DispatchDirectoryWatcher(retryInterval: .milliseconds(20))) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try UsageHarness.replace(directory.appending(path: "claude-statusline.json"), with: Data("{}".utf8))
        }
        #expect(count > 0)
    }

    private static func countChanges(of directory: URL, watcher: DispatchDirectoryWatcher, touch: () throws -> Void) async throws -> Int {
        let counter = Mutex(0)
        let changes = watcher.changes(in: directory)
        let consumer = Task {
            for await _ in changes {
                counter.withLock { $0 += 1 }
            }
        }
        defer { consumer.cancel() }
        return try await eventually {
            try? touch()
            let count = counter.withLock { $0 }
            return count > 0 ? count : nil
        }
    }
}
