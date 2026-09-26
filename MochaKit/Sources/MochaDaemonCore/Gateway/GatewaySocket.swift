public protocol GatewaySocket: Sendable {
    func send(text: String) async throws
    func close(code: WebSocketCloseCode, reason: String) async
}

extension WebSocketConnection: GatewaySocket {}
