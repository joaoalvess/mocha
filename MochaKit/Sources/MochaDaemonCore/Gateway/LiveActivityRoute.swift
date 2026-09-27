import Foundation
import MochaProtocol

struct LiveActivityRoute: Sendable {
    static let maxBodySize = 16 * 1024

    let registrar: any LiveActivityRegistering
    let authenticator: BearerAuthenticator

    func respond(to request: HttpRequest) async -> HttpResponse {
        guard let device = await authenticator.device(for: request) else { return HttpResponse(status: .unauthorized) }
        guard let registration = try? JSONDecoder().decode(LiveActivityRegistration.self, from: request.body) else {
            return HttpResponse(status: .badRequest)
        }
        do {
            try await registrar.register(registration, from: device.id)
            return try .json(EmptyReply())
        } catch LiveActivityRegistrationError.invalidToken {
            return HttpResponse(status: .badRequest)
        } catch {
            gatewayLogger.error("failed to register a live activity: \(String(describing: error), privacy: .public)")
            return HttpResponse(status: .internalServerError)
        }
    }

    private struct EmptyReply: Encodable {}
}
