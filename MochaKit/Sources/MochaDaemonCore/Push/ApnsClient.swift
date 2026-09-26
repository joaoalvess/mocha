import Foundation

public struct ApnsClient: Sendable {
    private let tokens: ApnsTokenProvider
    private let transport: any ApnsTransport

    public init(tokens: ApnsTokenProvider, transport: any ApnsTransport = URLSessionApnsTransport()) {
        self.tokens = tokens
        self.transport = transport
    }

    public func send(_ request: ApnsRequest) async throws -> ApnsResponse {
        try request.validate()
        let response = try await attempt(request)
        guard response.reason == ApnsReason.expiredProviderToken else { return response }
        await tokens.invalidate()
        return try await attempt(request)
    }

    private func attempt(_ request: ApnsRequest) async throws -> ApnsResponse {
        let urlRequest = try request.urlRequest(authorizationToken: try await tokens.token())
        return try await transport.send(urlRequest)
    }
}

public enum ApnsReason {
    public static let expiredProviderToken = "ExpiredProviderToken"
    public static let badDeviceToken = "BadDeviceToken"
    public static let configuration: Set<String> = [
        "BadEnvironmentKeyInToken",
        "BadEnvironmentKeyIdInToken",
        "InvalidProviderToken",
        "TopicDisallowed",
    ]
}
