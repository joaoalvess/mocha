import Foundation
import MochaProtocol

public enum AgentsActivityRegistrationResult: Sendable, Equatable {
    case delivered
    case refused
    case unauthorized
    case notPaired
    case unreachable
    case unexpectedStatus(Int)
}

public protocol AgentsActivityRegistering: Sendable {
    func register(_ registration: LiveActivityRegistration) async -> AgentsActivityRegistrationResult
}

public struct GatewayAgentsActivityRegistrar: AgentsActivityRegistering {
    static let registrationPath = "/v1/live-activity"

    private let tokenStore: any TokenStore
    private let transport: any HTTPUploadTransport

    public init(tokenStore: any TokenStore, transport: any HTTPUploadTransport = URLSessionUploadTransport(session: GatewayPendingResponder.session)) {
        self.tokenStore = tokenStore
        self.transport = transport
    }

    public func register(_ registration: LiveActivityRegistration) async -> AgentsActivityRegistrationResult {
        guard
            let credential = try? await tokenStore.load(),
            let url = Self.registrationURL(forPairingURL: credential.url)
        else { return .notPaired }
        guard let body = try? JSONEncoder().encode(registration) else { return .refused }
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

    static func registrationURL(forPairingURL pairingURL: URL) -> URL? {
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
        components.path = registrationPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func result(forStatus status: Int) -> AgentsActivityRegistrationResult {
        switch status {
        case 200: .delivered
        case 400: .refused
        case 401: .unauthorized
        default: .unexpectedStatus(status)
        }
    }
}

public struct SocketAgentsActivityRegistrar: AgentsActivityRegistering {
    private let send: @Sendable (LiveActivityRegistration) async -> Bool

    public init(send: @escaping @Sendable (LiveActivityRegistration) async -> Bool) {
        self.send = send
    }

    public func register(_ registration: LiveActivityRegistration) async -> AgentsActivityRegistrationResult {
        await send(registration) ? .delivered : .unreachable
    }
}
