import Foundation
import MochaProtocol

struct UploadRoute: Sendable {
    let store: UploadStore
    let authenticator: BearerAuthenticator

    func respond(to request: HttpRequest) async -> HttpResponse {
        guard await authenticator.device(for: request) != nil else { return HttpResponse(status: .unauthorized) }
        guard request.headers.contains("Content-Length") else { return HttpResponse(status: .lengthRequired) }
        guard let type = UploadImageType(contentType: request.headers["Content-Type"]) else {
            return HttpResponse(status: .unsupportedMediaType)
        }
        guard !request.body.isEmpty else { return HttpResponse(status: .badRequest) }
        do {
            return try .json(UploadResponse(path: try store.save(request.body, as: type)))
        } catch {
            gatewayLogger.error("failed to save an upload: \(String(describing: error), privacy: .public)")
            return HttpResponse(status: .internalServerError)
        }
    }
}
