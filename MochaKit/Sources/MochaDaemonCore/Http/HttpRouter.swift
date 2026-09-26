public typealias HttpHandler = @Sendable (HttpRequest) async throws -> HttpResponse
public typealias WebSocketHandler = @Sendable (HttpRequest, WebSocketConnection) async -> Void

public struct HttpRouter: Sendable {
    struct HttpRoute: Sendable {
        let maxBodySize: Int?
        let handler: HttpHandler
    }

    struct WebSocketRoute: Sendable {
        let options: WebSocketOptions
        let handler: WebSocketHandler
    }

    enum Endpoint: Sendable {
        case http(HttpRoute)
        case webSocket(WebSocketRoute)
    }

    enum Resolution: Sendable {
        case endpoint(Endpoint)
        case methodNotAllowed([HttpMethod])
        case notFound
    }

    private var endpoints: [String: [HttpMethod: Endpoint]] = [:]

    public init() {}

    public mutating func route(
        _ method: HttpMethod,
        _ path: String,
        maxBodySize: Int? = nil,
        handler: @escaping HttpHandler
    ) {
        endpoints[path, default: [:]][method] = .http(HttpRoute(maxBodySize: maxBodySize, handler: handler))
    }

    public mutating func webSocket(
        _ path: String,
        options: WebSocketOptions = WebSocketOptions(),
        handler: @escaping WebSocketHandler
    ) {
        endpoints[path, default: [:]][.get] = .webSocket(WebSocketRoute(options: options, handler: handler))
    }

    func resolve(_ method: HttpMethod, _ path: String) -> Resolution {
        guard let byMethod = endpoints[path] else { return .notFound }
        guard let endpoint = byMethod[method] else {
            return .methodNotAllowed(byMethod.keys.sorted { $0.rawValue < $1.rawValue })
        }
        return .endpoint(endpoint)
    }
}
