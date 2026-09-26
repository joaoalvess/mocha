public struct Gateway: Sendable {
    public typealias EventSink = @Sendable (GatewayEvent) -> Void

    public static let healthPath = "/v1/health"
    public static let webSocketPath = "/v1"
    public static let port: UInt16 = 47421
    public static let binding = HttpBinding.loopback(port: port)

    let version: String
    let herdr: any HerdrBridging
    let hub: SessionHub
    let events: EventSink
    private let connectionNumbers = GatewayConnectionNumbers()

    public init(
        version: String = DaemonVersion.current,
        herdr: any HerdrBridging,
        hub: SessionHub,
        events: @escaping EventSink = { _ in }
    ) {
        self.version = version
        self.herdr = herdr
        self.hub = hub
        self.events = events
    }

    public func makeRouter() -> HttpRouter {
        var router = HttpRouter()
        router.route(.get, Self.healthPath) { request in
            events(.httpRequest(request))
            return try .json(GatewayHealth(ok: true, version: version, herdr: await herdr.isAvailable))
        }
        router.webSocket(Self.webSocketPath) { request, socket in
            await serve(request, socket)
        }
        return router
    }

    public func shutdown() async {
        await hub.shutdown()
    }

    private func serve(_ request: HttpRequest, _ socket: WebSocketConnection) async {
        let connection = await connectionNumbers.next()
        let clock = ContinuousClock()
        let openedAt = clock.now
        events(.webSocketOpened(connection: connection, request: request))
        await hub.serve(socket, messages: socket.messages)
        events(.webSocketClosed(
            connection: connection,
            code: await socket.closeCode,
            reason: await socket.closeReason,
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
