import Foundation

public struct HttpResponse: Sendable {
    public var status: HttpStatus
    public var headers: HttpHeaders
    public var body: Data

    public init(status: HttpStatus = .ok, headers: HttpHeaders = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

extension HttpResponse {
    private static let serverManagedHeaders: Set<String> = ["content-length", "connection", "transfer-encoding"]

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status.code) \(status.reasonPhrase)\r\n"
        for field in headers where Self.isSerializable(field) {
            head += "\(field.name): \(field.value)\r\n"
        }
        let includesBody = status.allowsBody
        if includesBody {
            head += "Content-Length: \(body.count)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        if includesBody {
            data.append(body)
        }
        return data
    }

    private static func isSerializable(_ field: HttpHeaders.Field) -> Bool {
        !field.name.isEmpty
            && !serverManagedHeaders.contains(field.name.lowercased())
            && field.name.utf8.allSatisfy(HttpRequestHead.isTokenByte)
            && !field.value.utf8.contains { $0 == 0x0D || $0 == 0x0A || $0 == 0x00 }
    }
}
