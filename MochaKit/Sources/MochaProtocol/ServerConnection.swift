public enum ServerConnectionError: Error, Sendable, Equatable {
    case notConnected
}

public protocol ServerConnection: Sendable {
    var messages: AsyncStream<ServerEnvelope> { get }
    var states: AsyncStream<ConnectionState> { get }
    func start() async
    func stop() async
    func pair(_ link: PairingLink) async
    func send(_ message: ClientMessage, id: String) async throws
}
