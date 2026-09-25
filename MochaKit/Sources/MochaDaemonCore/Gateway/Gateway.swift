public struct Gateway: Sendable {
    public typealias EventSink = @Sendable (GatewayEvent) -> Void

    public static let healthPath = "/v1/health"
    public static let webSocketPath = "/v1"

    let version: String
    let herdrAvailable: @Sendable () async -> Bool
    let events: EventSink
    private let connectionNumbers = GatewayConnectionNumbers()

    public init(
        version: String = DaemonVersion.current,
        herdrAvailable: @escaping @Sendable () async -> Bool = { false },
        events: @escaping EventSink = { _ in }
    ) {
        self.version = version
        self.herdrAvailable = herdrAvailable
        self.events = events
    }

    public func makeRouter() -> HttpRouter {
        var router = HttpRouter()
        router.route(.get, Self.healthPath) { request in
            events(.httpRequest(request))
            return try .json(GatewayHealth(ok: true, version: version, herdr: await herdrAvailable()))
        }
        router.webSocket(Self.webSocketPath) { request, socket in
            await echo(request, socket)
        }
        return router
    }

    private func echo(_ request: HttpRequest, _ socket: WebSocketConnection) async {
        let connection = await connectionNumbers.next()
        let clock = ContinuousClock()
        let openedAt = clock.now
        events(.webSocketOpened(connection: connection, request: request))
        var count = 0
        for await message in socket.messages {
            count += 1
            events(.webSocketMessage(connection: connection, message: message))
            switch message {
            case .text(let text):
                try? await socket.send(text: text)
            case .binary(let data):
                try? await socket.send(binary: data)
            }
        }
        events(.webSocketClosed(
            connection: connection,
            code: await socket.closeCode,
            reason: await socket.closeReason,
            messages: count,
            duration: clock.now - openedAt
        ))
    }
}

actor GatewayConnectionNumbers {
    private var last = 0

    func next() -> Int {
        last += 1
        return last
    }
}
