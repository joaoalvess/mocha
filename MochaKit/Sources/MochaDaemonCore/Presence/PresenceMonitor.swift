import Foundation
import os

let presenceLogger = Logger(subsystem: "com.joaoalves.mocha", category: "presence")

public actor PresenceMonitor {
    public static let pollInterval: Duration = .seconds(3)

    private let reader: any ConsoleLockReading
    private let clock: any GatewayClock
    private let interval: Duration
    private var lock: ConsoleLock?
    private var subscribers: [UUID: AsyncStream<ConsoleLock>.Continuation] = [:]
    private var polling: Task<Void, Never>?

    public init(
        reader: any ConsoleLockReading = IORegistryConsoleLockReader(),
        clock: any GatewayClock = SystemGatewayClock(),
        interval: Duration = PresenceMonitor.pollInterval
    ) {
        self.reader = reader
        self.clock = clock
        self.interval = interval
    }

    public func start() {
        guard polling == nil else { return }
        current()
        let clock = clock
        let interval = interval
        polling = Task { [weak self] in
            while (try? await clock.sleep(for: interval)) != nil {
                guard let self else { return }
                await self.current()
            }
        }
    }

    public func shutdown() {
        polling?.cancel()
        polling = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    @discardableResult
    public func current() -> ConsoleLock {
        let read = reader.consoleLock()
        guard read != lock else { return read }
        let isFirstRead = lock == nil
        lock = read
        presenceLogger.notice("presence: \(read.rawValue, privacy: .public)")
        if !isFirstRead {
            for continuation in subscribers.values {
                continuation.yield(read)
            }
        }
        return read
    }

    public func transitions() -> AsyncStream<ConsoleLock> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConsoleLock.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }
}
