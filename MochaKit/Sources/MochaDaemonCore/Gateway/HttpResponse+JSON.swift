import Foundation

extension HttpResponse {
    static func json(_ value: some Encodable, status: HttpStatus = .ok) throws -> HttpResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return HttpResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: try encoder.encode(value)
        )
    }
}
