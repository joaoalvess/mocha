import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

enum UsageSample {
    static let cacheFixture = "usage/claude-statusline.json"
    static let accountFixture = "usage/claude.json"
    static let fetchedAt = Date(timeIntervalSince1970: 1_790_392_863)
    static let fixtureSnapshot = UsageSnapshot(
        plan: "Max 20x",
        account: "d•••@e•••.com",
        windows: [
            UsageWindow(kind: .fiveHour, usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_790_406_000)),
            UsageWindow(kind: .weekly, usedPercent: 71, resetsAt: Date(timeIntervalSince1970: 1_790_604_000)),
        ],
        fetchedAt: fetchedAt
    )

    static func cache(fetchedAt: Int, fiveHour: Double, weekly: Double, contexts: [String: Double] = [:]) -> Data {
        let contextEntries = contexts.sorted { $0.key < $1.key }.map { #""\#($0.key)": {"used_percent": \#($0.value)}"# }
        return Data(#"""
            {
              "fetched_at_unix": \#(fetchedAt),
              "windows": [
                {"kind": "five_hour", "used_percent": \#(fiveHour), "remaining_percent": \#(100 - fiveHour), "resets_at": 1790406000},
                {"kind": "weekly", "used_percent": \#(weekly), "remaining_percent": \#(100 - weekly), "resets_at": 1790604000}
              ],
              "session_contexts": {\#(contextEntries.joined(separator: ", "))}
            }
            """#.utf8)
    }
}

struct UsageHarness {
    let directory: URL
    let cacheFile: URL
    let accountFile: URL
    let watcher: FakeDirectoryWatcher
    let clock: ManualClock
    let monitor: UsageMonitor

    func replaceCache(_ data: Data) throws {
        try UsageHarness.replace(cacheFile, with: data)
    }

    func removeCache() throws {
        try FileManager.default.removeItem(at: cacheFile)
    }

    func changeAndSettle() async throws {
        let before = await monitor.completedReloads
        watcher.signal()
        try await clock.waitForSleepers(1)
        clock.advance(by: UsageMonitor.defaultDebounce)
        _ = try await eventually { await monitor.completedReloads > before ? true : nil }
    }

    static func replace(_ url: URL, with data: Data) throws {
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

func withUsageMonitor(
    cache: Data? = nil,
    account: Data? = nil,
    _ body: (UsageHarness) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-usage-\(UUID().uuidString)", directoryHint: .isDirectory)
    let pluginDirectory = directory.appending(path: "plugin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cacheFile = pluginDirectory.appending(path: "claude-statusline.json")
    let accountFile = directory.appending(path: "claude.json")
    if let cache {
        try UsageHarness.replace(cacheFile, with: cache)
    }
    if let account {
        try account.write(to: accountFile)
    }
    let watcher = FakeDirectoryWatcher()
    let clock = ManualClock(origin: Sample.start)
    let monitor = UsageMonitor(cacheFile: cacheFile, accountFile: accountFile, watcher: watcher, clock: clock)
    await monitor.start()
    let harness = UsageHarness(
        directory: directory,
        cacheFile: cacheFile,
        accountFile: accountFile,
        watcher: watcher,
        clock: clock,
        monitor: monitor
    )
    do {
        try await body(harness)
    } catch {
        await monitor.stop()
        throw error
    }
    await monitor.stop()
}
