import Foundation
import MochaProtocol

public actor UsageMonitor: UsageProviding {
    public static let defaultDebounce: Duration = .milliseconds(500)

    private struct Cached<Value> {
        let stamp: UsageFileStamp
        let value: Value
    }

    public nonisolated let cacheFile: URL
    private let accountFile: URL
    private let watcher: any DirectoryWatching
    private let clock: any GatewayClock
    private let debounce: Duration
    private let broadcast = LatestValueBroadcast<UsageSnapshot?>(nil)
    private var cache: Cached<StatuslineCache>?
    private var account: Cached<ClaudeAccount>?
    private var watchTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var isStopped = false
    private(set) var completedReloads = 0

    public init(
        cacheFile: URL,
        accountFile: URL,
        watcher: any DirectoryWatching = DispatchDirectoryWatcher(),
        clock: any GatewayClock = SystemGatewayClock(),
        debounce: Duration = UsageMonitor.defaultDebounce
    ) {
        self.cacheFile = cacheFile
        self.accountFile = accountFile
        self.watcher = watcher
        self.clock = clock
        self.debounce = debounce
    }

    public func start() {
        guard watchTask == nil, !isStopped else { return }
        let changes = watcher.changes(in: cacheFile.deletingLastPathComponent())
        watchTask = Task { [weak self] in
            for await _ in changes {
                await self?.changeObserved()
            }
        }
        reload()
    }

    public func stop() {
        isStopped = true
        watchTask?.cancel()
        watchTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        broadcast.finish()
    }

    public nonisolated func events() -> AsyncStream<UsageSnapshot?> {
        broadcast.subscribe()
    }

    public var snapshot: UsageSnapshot? {
        broadcast.value
    }

    public func contextUsedPercent(forSession sessionId: String) -> Double? {
        cache?.value.contexts[sessionId]
    }

    private func changeObserved() {
        guard reloadTask == nil, !isStopped else { return }
        let clock = clock
        let delay = debounce
        reloadTask = Task { [weak self] in
            guard (try? await clock.sleep(for: delay)) != nil else { return }
            await self?.debouncedReload()
        }
    }

    private func debouncedReload() {
        reloadTask = nil
        guard !isStopped else { return }
        reload()
        completedReloads += 1
    }

    private func reload() {
        let previousSnapshot = broadcast.value
        let previousContexts = cache?.value.contexts
        guard let stamp = UsageFileStamp.of(cacheFile) else {
            cache = nil
            publish(nil, contextsChanged: previousContexts != nil, previous: previousSnapshot)
            return
        }
        if let cache, cache.stamp == stamp {
            return
        }
        guard let parsed = StatuslineCache.read(cacheFile) else {
            cache = nil
            publish(nil, contextsChanged: previousContexts != nil, previous: previousSnapshot)
            return
        }
        cache = Cached(stamp: stamp, value: parsed)
        let account = currentAccount()
        let snapshot = UsageSnapshot(plan: account.plan, account: account.account, windows: parsed.windows, fetchedAt: parsed.fetchedAt)
        publish(snapshot, contextsChanged: previousContexts != parsed.contexts, previous: previousSnapshot)
    }

    private func publish(_ snapshot: UsageSnapshot?, contextsChanged: Bool, previous: UsageSnapshot?) {
        guard snapshot != previous || contextsChanged else { return }
        broadcast.publish(snapshot)
    }

    private func currentAccount() -> ClaudeAccount {
        guard let stamp = UsageFileStamp.of(accountFile) else {
            account = nil
            return ClaudeAccount()
        }
        if let account, account.stamp == stamp {
            return account.value
        }
        let value = (try? Data(contentsOf: accountFile)).map(ClaudeAccount.parse) ?? ClaudeAccount()
        account = Cached(stamp: stamp, value: value)
        return value
    }
}
