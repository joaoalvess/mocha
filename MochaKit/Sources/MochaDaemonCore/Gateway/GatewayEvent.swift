public enum GatewayEvent: Sendable {
    case httpRequest(HttpRequest)
    case webSocketOpened(connection: Int, request: HttpRequest)
    case webSocketClosed(connection: Int, code: WebSocketCloseCode?, reason: String?, duration: Duration)
}
