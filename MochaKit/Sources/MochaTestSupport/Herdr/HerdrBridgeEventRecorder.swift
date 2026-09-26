import Foundation
import MochaDaemonCore

public actor HerdrBridgeEventRecorder {
    private var recorded: [HerdrBridgeEvent] = []
    private var consumer: Task<Void, Never>?

    public init(_ stream: AsyncStream<HerdrBridgeEvent>) {
        consumer = nil
        Task { await self.consume(stream) }
    }

    public var events: [HerdrBridgeEvent] {
        recorded
    }

    public func waitFor(
        timeout: Duration = .seconds(5),
        _ predicate: @Sendable (HerdrBridgeEvent) -> Bool
    ) async -> HerdrBridgeEvent? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let match = recorded.first(where: predicate) {
                return match
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return recorded.first(where: predicate)
    }

    public func count(where predicate: @Sendable (HerdrBridgeEvent) -> Bool) -> Int {
        recorded.filter(predicate).count
    }

    public func cancel() {
        consumer?.cancel()
        consumer = nil
    }

    private func consume(_ stream: AsyncStream<HerdrBridgeEvent>) {
        consumer = Task { [weak self] in
            for await event in stream {
                await self?.append(event)
            }
        }
    }

    private func append(_ event: HerdrBridgeEvent) {
        recorded.append(event)
    }
}

public enum HerdrWait {
    public static func until(
        timeout: Duration = .seconds(5),
        _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }
}
