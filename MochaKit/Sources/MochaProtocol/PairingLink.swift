import Foundation

public struct PairingLink: Sendable, Equatable {
    public var url: URL
    public var code: String

    public init(url: URL, code: String) {
        self.url = url
        self.code = code
    }

    public init?(_ link: URL) {
        guard
            let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == Self.scheme,
            components.host?.lowercased() == Self.host,
            let urlValue = Self.queryValue(named: Self.urlKey, in: components),
            let url = URL(string: urlValue),
            let socketScheme = url.scheme?.lowercased(),
            Self.socketSchemes.contains(socketScheme),
            let socketHost = url.host(),
            !socketHost.isEmpty,
            let code = Self.queryValue(named: Self.codeKey, in: components),
            Self.isBase64URL(code)
        else { return nil }
        self.init(url: url, code: code)
    }

    public var link: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.percentEncodedQuery = [
            Self.urlKey + "=" + Self.percentEncoded(url.absoluteString),
            Self.codeKey + "=" + Self.percentEncoded(code),
        ].joined(separator: "&")
        return components.url ?? url
    }

    private static let scheme = "mocha"
    private static let host = "pair"
    private static let urlKey = "url"
    private static let codeKey = "code"
    private static let socketSchemes: Set<String> = ["ws", "wss"]
    private static let alphanumerics = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    private static let unreservedCharacters = CharacterSet(charactersIn: alphanumerics + "-._~")
    private static let base64URLCharacters = CharacterSet(charactersIn: alphanumerics + "-_")
    private static let maximumPadding = 2

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? value
    }

    private static func queryValue(named name: String, in components: URLComponents) -> String? {
        components.queryItems?.first { $0.name == name }?.value
    }

    private static func isBase64URL(_ code: String) -> Bool {
        let body = code.prefix { $0 != "=" }
        let padding = code.dropFirst(body.count)
        return !body.isEmpty
            && body.unicodeScalars.allSatisfy(base64URLCharacters.contains)
            && padding.count <= maximumPadding
            && padding.allSatisfy { $0 == "=" }
    }
}
