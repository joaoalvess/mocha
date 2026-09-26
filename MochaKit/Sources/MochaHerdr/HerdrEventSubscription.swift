import Foundation

public final class HerdrEventSubscription: Sendable {
    public let events: AsyncStream<HerdrEvent>

    private let connection: HerdrSocketConnection

    init(connection: HerdrSocketConnection) {
        self.connection = connection
        let (events, continuation) = AsyncStream.makeStream(of: HerdrEvent.self, bufferingPolicy: .unbounded)
        self.events = events
        continuation.onTermination = { _ in
            connection.close()
        }
        Task {
            while let line = await connection.readLine() {
                if let event = HerdrEvent(line: line) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }

    public func cancel() {
        connection.close()
    }
}
