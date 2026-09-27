import Foundation
import MochaProtocol

struct RespondRoute: Sendable {
    private struct Body: Decodable {
        let requestId: RequestID
        let response: PendingResponse
    }

    static let accepted = HttpResponse(status: .ok, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))

    let pending: any PendingProviding
    let authenticator: BearerAuthenticator

    func respond(to request: HttpRequest) async -> HttpResponse {
        guard await authenticator.device(for: request) != nil else { return HttpResponse(status: .unauthorized) }
        guard let body = try? JSONDecoder().decode(Body.self, from: request.body) else {
            return HttpResponse(status: .badRequest)
        }
        do {
            try await pending.respond(to: body.requestId, with: body.response)
            return Self.accepted
        } catch {
            switch error {
            case .requestNotFound:
                return HttpResponse(status: .notFound)
            case .invalidPayload(let message):
                gatewayLogger.info("POST /v1/respond refused: \(message, privacy: .public)")
                return HttpResponse(status: .badRequest)
            }
        }
    }
}
