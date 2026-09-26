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
        let urlRequest = try request.urlRequest(authorizationToken: try await tokens.token())
        let response = try await transport.send(urlRequest)
        if response.reason == "ExpiredProviderToken" {
            await tokens.invalidate()
        }
        return response
    }
}
