import Foundation
import MochaProtocol

public enum PendingRespondResult: Sendable, Equatable {
    case accepted
    case gone
    case refused
    case unauthorized
    case notPaired
    case unreachable
    case unexpectedStatus(Int)
}

public protocol PendingResponding: Sendable {
    func respond(to requestId: RequestID, with response: PendingResponse) async -> PendingRespondResult
}

public struct GatewayPendingResponder: PendingResponding {
    static let respondPath = "/v1/respond"
    public static let requestTimeout: TimeInterval = 15

    private struct Body: Encodable {
        let requestId: RequestID
        let response: PendingResponse
    }

    private let tokenStore: any TokenStore
    private let transport: any HTTPUploadTransport

    public init(tokenStore: any TokenStore, transport: any HTTPUploadTransport = URLSessionUploadTransport(session: GatewayPendingResponder.session)) {
        self.tokenStore = tokenStore
        self.transport = transport
    }

    public func respond(to requestId: RequestID, with response: PendingResponse) async -> PendingRespondResult {
        guard
            let credential = try? await tokenStore.load(),
            let url = Self.respondURL(forPairingURL: credential.url)
        else { return .notPaired }
        guard let body = try? JSONEncoder().encode(Body(requestId: requestId, response: response)) else { return .refused }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let reply: URLResponse
        do {
            (_, reply) = try await transport.upload(for: request, from: body)
        } catch {
            return .unreachable
        }
        guard let status = (reply as? HTTPURLResponse)?.statusCode else { return .unreachable }
        return Self.result(forStatus: status)
    }

    static func respondURL(forPairingURL pairingURL: URL) -> URL? {
        guard
            var components = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false),
            let host = components.host, !host.isEmpty
        else { return nil }
        switch components.scheme?.lowercased() {
        case "wss", "https":
            components.scheme = "https"
        case "ws", "http":
            components.scheme = "http"
        default:
            return nil
        }
        components.user = nil
        components.password = nil
        components.path = respondPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func result(forStatus status: Int) -> PendingRespondResult {
        switch status {
        case 200: .accepted
        case 404: .gone
        case 400: .refused
        case 401: .unauthorized
        default: .unexpectedStatus(status)
        }
    }

    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
