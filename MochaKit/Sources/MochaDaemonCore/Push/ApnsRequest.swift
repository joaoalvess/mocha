import Foundation
import MochaProtocol

extension ApnsEnvironment {
    public var host: String {
        switch self {
        case .sandbox: "api.sandbox.push.apple.com"
        case .production: "api.push.apple.com"
        }
    }
}

public enum ApnsPushType: String, Sendable, Equatable {
    case alert
    case liveactivity
}

public enum ApnsPriority: Int, Sendable, Equatable {
    case low = 5
    case high = 10
}

public enum ApnsExpiration: Sendable, Equatable {
    case deliverOnce
    case at(Date)

    var headerValue: String {
        switch self {
        case .deliverOnce: "0"
        case .at(let date): String(Int(date.timeIntervalSince1970.rounded(.up)))
        }
    }
}

public enum ApnsTopic {
    public static func alert(bundleId: String) -> String {
        bundleId
    }

    public static func liveActivity(bundleId: String) -> String {
        bundleId + ".push-type.liveactivity"
    }
}

public struct ApnsRequest: Sendable, Equatable {
    public static let maxPayloadBytes = 4096
    public static let maxCollapseIdBytes = 64

    public var deviceToken: String
    public var environment: ApnsEnvironment
    public var pushType: ApnsPushType
    public var topic: String
    public var priority: ApnsPriority
    public var expiration: ApnsExpiration?
    public var collapseId: String?
    public var apnsId: UUID
    public var payload: Data

    public init(
        deviceToken: String,
        environment: ApnsEnvironment,
        pushType: ApnsPushType,
        topic: String,
        priority: ApnsPriority,
        expiration: ApnsExpiration? = nil,
        collapseId: String? = nil,
        apnsId: UUID = UUID(),
        payload: Data
    ) {
        self.deviceToken = deviceToken.lowercased()
        self.environment = environment
        self.pushType = pushType
        self.topic = topic
        self.priority = priority
        self.expiration = expiration
        self.collapseId = collapseId
        self.apnsId = apnsId
        self.payload = payload
    }

    public static func isValidDeviceToken(_ token: String) -> Bool {
        !token.isEmpty && token.count.isMultiple(of: 2) && token.allSatisfy(\.isHexDigit)
    }

    public func validate() throws {
        guard Self.isValidDeviceToken(deviceToken) else { throw ApnsError.invalidDeviceToken }
        if let collapseId, collapseId.utf8.count > Self.maxCollapseIdBytes {
            throw ApnsError.collapseIdTooLong(bytes: collapseId.utf8.count)
        }
        guard payload.count <= Self.maxPayloadBytes else { throw ApnsError.payloadTooLarge(bytes: payload.count) }
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = environment.host
        components.path = "/3/device/" + deviceToken
        return components.url
    }

    public var headers: [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = [
            ("apns-push-type", pushType.rawValue),
            ("apns-topic", topic),
            ("apns-priority", String(priority.rawValue)),
            ("apns-id", apnsId.uuidString.lowercased()),
        ]
        if let expiration {
            headers.append(("apns-expiration", expiration.headerValue))
        }
        if let collapseId {
            headers.append(("apns-collapse-id", collapseId))
        }
        return headers
    }

    public func urlRequest(authorizationToken: String) throws -> URLRequest {
        try validate()
        guard let url else { throw ApnsError.invalidDeviceToken }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("bearer " + authorizationToken, forHTTPHeaderField: "authorization")
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }
}
