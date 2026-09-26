import Foundation

public struct HttpRequest: Sendable {
    public let method: HttpMethod
    public let path: String
    public let query: String?
    public let version: String
    public let headers: HttpHeaders
    public let body: Data

    public init(
        method: HttpMethod,
        path: String,
        query: String? = nil,
        version: String = "HTTP/1.1",
        headers: HttpHeaders = [:],
        body: Data = Data()
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.version = version
        self.headers = headers
        self.body = body
    }

    public var queryItems: [URLQueryItem] {
        guard let query else { return [] }
        return URLComponents(string: "/?" + query)?.queryItems ?? []
    }

    init(head: HttpRequestHead, body: Data) {
        self.init(
            method: head.method,
            path: head.path,
            query: head.query,
            version: head.version,
            headers: head.headers,
            body: body
        )
    }
}
