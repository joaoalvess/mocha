public struct Gateway: Sendable {
    public typealias EventSink = @Sendable (GatewayEvent) -> Void

    public static let healthPath = "/v1/health"
    public static let webSocketPath = "/v1"
    public static let uploadPath = "/v1/upload"
    public static let respondPath = "/v1/respond"
    public static let port: UInt16 = 47421
    public static let binding = HttpBinding.loopback(port: port)

    let version: String
    let herdr: any HerdrBridging
    let hub: SessionHub
    let uploads: UploadStore?
    let events: EventSink
    private let connectionNumbers = GatewayConnectionNumbers()

    public init(
        version: String = DaemonVersion.current,
        herdr: any HerdrBridging,
        hub: SessionHub,
        uploads: UploadStore? = nil,
        events: @escaping EventSink = { _ in }
    ) {
        self.version = version
        self.herdr = herdr
        self.hub = hub
        self.uploads = uploads
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
        if let uploads {
            let upload = UploadRoute(store: uploads, authenticator: BearerAuthenticator(devices: hub.devices, clock: hub.clock))
            router.route(.post, Self.uploadPath, maxBodySize: UploadStore.maxBodySize) { request in
                events(.httpRequest(request))
                return await upload.respond(to: request)
            }
        }
        if let pending = hub.pending {
            let respond = RespondRoute(pending: pending, authenticator: BearerAuthenticator(devices: hub.devices, clock: hub.clock))
            router.route(.post, Self.respondPath) { request in
                events(.httpRequest(request))
                return await respond.respond(to: request)
            }
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
