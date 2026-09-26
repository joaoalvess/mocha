public protocol ServerConnection: Sendable {
    var messages: AsyncStream<ServerEnvelope> { get }
    func send(_ message: ClientMessage) async throws -> String
}
