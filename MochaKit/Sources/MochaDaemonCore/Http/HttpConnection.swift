import Foundation

struct HttpConnection: Sendable {
    private enum HeadReading {
        case head(HttpRequestHead, leftover: [UInt8])
        case rejected(HttpStatus)
        case closed
    }

    private enum HandlerOutcome: Sendable {
        case response(HttpResponse)
        case abandoned
        case peerClosed
    }

    private static let headChunkSize = 16 * 1024
    private static let bodyChunkSize = 256 * 1024

    let io: ConnectionIO
    let router: HttpRouter
    let configuration: HttpServerConfiguration

    func run() async {
        defer { io.cancel() }
        switch await readHead() {
        case .closed:
            return
        case .rejected(let status):
            httpLogger.debug("rejected request head with \(status.code, privacy: .public)")
            await respondEarly(HttpResponse(status: status), pendingBody: nil)
        case .head(let head, let leftover):
            await serve(head, leftover: leftover)
        }
    }

    private func readHead() async -> HeadReading {
        let deadline = io.scheduleCancellation(after: configuration.headReadTimeout)
        defer { deadline.cancel() }
        var buffer: [UInt8] = []
        var searchStart = 0
        while true {
            let chunk = await io.receive(maximumLength: Self.headChunkSize)
            buffer.append(contentsOf: chunk.bytes)
            if let end = HttpRequestHead.endOfHead(in: buffer, searchingFrom: searchStart) {
                guard end + 4 <= configuration.maxHeadSize else { return .rejected(.requestHeaderFieldsTooLarge) }
                switch HttpRequestHead.parse(buffer[..<end]) {
                case .success(let head):
                    return .head(head, leftover: Array(buffer[(end + 4)...]))
                case .failure(let error):
                    return .rejected(error.status)
                }
            }
            if buffer.count > configuration.maxHeadSize { return .rejected(.requestHeaderFieldsTooLarge) }
            if chunk.isEnd { return .closed }
            searchStart = max(buffer.count - 3, 0)
        }
    }

    private func serve(_ head: HttpRequestHead, leftover: [UInt8]) async {
        guard !head.headers.contains("Transfer-Encoding") else {
            await respondEarly(HttpResponse(status: .lengthRequired), head: head, pendingBody: nil)
            return
        }
        let contentLength: Int
        switch head.contentLength {
        case .absent:
            contentLength = 0
        case .value(let value):
            contentLength = value
        case .invalid:
            await respondEarly(HttpResponse(status: .badRequest), head: head, pendingBody: nil)
            return
        }
        let pendingBody = max(contentLength - leftover.count, 0)
        switch router.resolve(head.method, head.path) {
        case .notFound:
            await respondEarly(HttpResponse(status: .notFound), head: head, pendingBody: pendingBody)
        case .methodNotAllowed(let allowed):
            let allow = allowed.map(\.rawValue).joined(separator: ", ")
            await respondEarly(HttpResponse(status: .methodNotAllowed, headers: ["Allow": allow]), head: head, pendingBody: pendingBody)
        case .endpoint(.http(let route)):
            guard contentLength <= route.maxBodySize ?? configuration.defaultMaxBodySize else {
                await respondEarly(HttpResponse(status: .contentTooLarge), head: head, pendingBody: pendingBody)
                return
            }
            guard let body = await readBody(length: contentLength, leftover: leftover) else { return }
            await handle(HttpRequest(head: head, body: body), with: route.handler)
        case .endpoint(.webSocket(let route)):
            guard contentLength == 0 else {
                await respondEarly(HttpResponse(status: .badRequest), head: head, pendingBody: pendingBody)
                return
            }
            await upgrade(head, leftover: leftover, route: route)
        }
    }

    private func readBody(length: Int, leftover: [UInt8]) async -> Data? {
        var body = Data(capacity: length)
        body.append(contentsOf: leftover.prefix(length))
        while body.count < length {
            let chunk = await io.receive(maximumLength: min(length - body.count, Self.bodyChunkSize))
            body.append(chunk.bytes)
            if chunk.isEnd, body.count < length { return nil }
        }
        return body
    }

    private func handle(_ request: HttpRequest, with handler: @escaping HttpHandler) async {
        await withTaskGroup(of: HandlerOutcome.self) { group in
            group.addTask {
                do {
                    return .response(try await handler(request))
                } catch {
                    if Task.isCancelled { return .abandoned }
                    httpLogger.error("handler for \(request.path, privacy: .public) threw \(String(describing: type(of: error)), privacy: .public)")
                    return .response(HttpResponse(status: .internalServerError))
                }
            }
            group.addTask { [io] in
                await Self.waitForPeerClose(io)
                return .peerClosed
            }
            guard let first = await group.next() else { return }
            switch first {
            case .response(let response):
                _ = await io.send(response.serialized())
                httpLogger.debug("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) \(response.status.code, privacy: .public)")
                io.cancel()
            case .abandoned:
                io.cancel()
            case .peerClosed:
                httpLogger.debug("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) abandoned by client")
                group.cancelAll()
            }
        }
    }

    private func upgrade(_ head: HttpRequestHead, leftover: [UInt8], route: HttpRouter.WebSocketRoute) async {
        switch WebSocketHandshake.evaluate(head) {
        case .rejected(let response):
            await respondEarly(response, head: head, pendingBody: 0)
        case .accepted(let acceptValue):
            guard await io.send(WebSocketHandshake.switchingProtocolsResponse(acceptValue: acceptValue)) else { return }
            httpLogger.debug("websocket opened on \(head.path, privacy: .public)")
            let socket = WebSocketConnection(io: io, options: route.options, bufferedBytes: leftover)
            let request = HttpRequest(head: head, body: Data())
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await socket.run()
                }
                group.addTask {
                    await route.handler(request, socket)
                    await socket.close()
                }
            }
        }
    }

    private func respondEarly(_ response: HttpResponse, head: HttpRequestHead? = nil, pendingBody: Int?) async {
        if let head {
            httpLogger.debug("\(head.method.rawValue, privacy: .public) \(head.path, privacy: .public) \(response.status.code, privacy: .public)")
        }
        guard await io.send(response.serialized(), closingWrite: pendingBody == nil) else { return }
        await drain(upTo: min(pendingBody ?? configuration.maxDrainSize, configuration.maxDrainSize))
    }

    private func drain(upTo limit: Int) async {
        guard limit > 0 else { return }
        let deadline = io.scheduleCancellation(after: configuration.drainTimeout)
        defer { deadline.cancel() }
        var drained = 0
        while drained < limit {
            let chunk = await io.receive(maximumLength: min(limit - drained, Self.bodyChunkSize))
            drained += chunk.bytes.count
            if chunk.isEnd { return }
        }
    }

    private static func waitForPeerClose(_ io: ConnectionIO) async {
        var chunk = await io.receive(maximumLength: headChunkSize)
        while !chunk.isEnd {
            chunk = await io.receive(maximumLength: headChunkSize)
        }
    }
}
