import Foundation

struct BearerAuthenticator: Sendable {
    private static let scheme = "bearer"

    let devices: DeviceStore
    let clock: any GatewayClock

    func device(for request: HttpRequest, marksSeen: Bool = true) async -> DeviceRecord? {
        guard let token = Self.token(in: request.headers) else { return nil }
        let record: DeviceRecord?
        do {
            record = try await devices.device(matchingToken: token)
        } catch {
            gatewayLogger.error("failed to read devices: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard let record else { return nil }
        guard marksSeen else { return record }
        do {
            try await devices.markSeen(record.id, at: clock.now())
        } catch {
            gatewayLogger.error("failed to update lastSeenAt: \(String(describing: error), privacy: .public)")
        }
        return record
    }

    static func token(in headers: HttpHeaders) -> String? {
        let values = headers.values(for: "Authorization")
        guard values.count == 1, let value = values.first else { return nil }
        let parts = value.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == scheme else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}
