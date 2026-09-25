public struct HttpStatus: Hashable, Sendable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let code: Int

    public init(code: Int) {
        self.code = code
    }

    public init(integerLiteral value: Int) {
        self.code = value
    }

    public var description: String {
        "\(code) \(reasonPhrase)"
    }

    public var reasonPhrase: String {
        switch code {
        case 100: "Continue"
        case 101: "Switching Protocols"
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 426: "Upgrade Required"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        case 505: "HTTP Version Not Supported"
        default: ""
        }
    }

    var allowsBody: Bool {
        !((100..<200).contains(code) || code == 204 || code == 304)
    }

    public static let ok: HttpStatus = 200
    public static let created: HttpStatus = 201
    public static let accepted: HttpStatus = 202
    public static let noContent: HttpStatus = 204
    public static let badRequest: HttpStatus = 400
    public static let unauthorized: HttpStatus = 401
    public static let forbidden: HttpStatus = 403
    public static let notFound: HttpStatus = 404
    public static let methodNotAllowed: HttpStatus = 405
    public static let requestTimeout: HttpStatus = 408
    public static let conflict: HttpStatus = 409
    public static let lengthRequired: HttpStatus = 411
    public static let contentTooLarge: HttpStatus = 413
    public static let unsupportedMediaType: HttpStatus = 415
    public static let upgradeRequired: HttpStatus = 426
    public static let tooManyRequests: HttpStatus = 429
    public static let requestHeaderFieldsTooLarge: HttpStatus = 431
    public static let internalServerError: HttpStatus = 500
    public static let notImplemented: HttpStatus = 501
    public static let serviceUnavailable: HttpStatus = 503
    public static let httpVersionNotSupported: HttpStatus = 505
}
