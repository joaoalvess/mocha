public struct HttpMethod: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }

    public static let get: HttpMethod = "GET"
    public static let head: HttpMethod = "HEAD"
    public static let post: HttpMethod = "POST"
    public static let put: HttpMethod = "PUT"
    public static let patch: HttpMethod = "PATCH"
    public static let delete: HttpMethod = "DELETE"
    public static let options: HttpMethod = "OPTIONS"
}
