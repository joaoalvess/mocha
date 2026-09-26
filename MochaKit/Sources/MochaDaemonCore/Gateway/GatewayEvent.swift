public enum GatewayEvent: Sendable {
    case httpRequest(HttpRequest)
    case webSocketOpened(connection: Int, request: HttpRequest)
    case webSocketMessage(connection: Int, message: WebSocketMessage)
    case webSocketClosed(connection: Int, code: WebSocketCloseCode?, reason: String?, messages: Int, duration: Duration)
}
