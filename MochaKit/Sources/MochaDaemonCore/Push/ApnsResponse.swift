import Foundation

public struct ApnsResponse: Sendable, Equatable {
    public var status: Int
    public var apnsId: String?
    public var uniqueId: String?
    public var reason: String?
    public var inactiveSince: Date?
    public var networkProtocol: String?

    public init(
        status: Int,
        apnsId: String? = nil,
        uniqueId: String? = nil,
        reason: String? = nil,
        inactiveSince: Date? = nil,
        networkProtocol: String? = nil
    ) {
        self.status = status
        self.apnsId = apnsId
        self.uniqueId = uniqueId
        self.reason = reason
        self.inactiveSince = inactiveSince
        self.networkProtocol = networkProtocol
    }

    public init(status: Int, headerValue: (String) -> String?, body: Data, networkProtocol: String?) {
        let error = try? JSONDecoder().decode(ErrorBody.self, from: body)
        self.init(
            status: status,
            apnsId: headerValue("apns-id"),
            uniqueId: headerValue("apns-unique-id"),
            reason: error?.reason,
            inactiveSince: error?.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) },
            networkProtocol: networkProtocol
        )
    }

    public var isSuccess: Bool {
        status == 200
    }

    public var deviceTokenIsInvalid: Bool {
        status == 410 || reason == "BadDeviceToken"
    }

    private struct ErrorBody: Decodable {
        let reason: String?
        let timestamp: Double?
    }
}
