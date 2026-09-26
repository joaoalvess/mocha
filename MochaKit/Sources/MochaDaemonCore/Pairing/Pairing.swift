import Foundation
import MochaProtocol

public struct PairingCode: Sendable, Equatable, Encodable {
    public let code: String
    public let url: URL
    public let expiresAt: Date

    public init(code: String, url: URL, expiresAt: Date) {
        self.code = code
        self.url = url
        self.expiresAt = expiresAt
    }

    public var link: PairingLink {
        PairingLink(url: url, code: code)
    }

    private enum CodingKeys: String, CodingKey {
        case code, url, expiresAt
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(url.absoluteString, forKey: .url)
        try container.encode(ProtocolDate.string(from: expiresAt), forKey: .expiresAt)
    }
}

public actor Pairing {
    public static let codeValidity: TimeInterval = 10 * 60

    private let clock: any GatewayClock
    private var codes: [String: Date] = [:]

    public init(clock: any GatewayClock = SystemGatewayClock()) {
        self.clock = clock
    }

    public func issueCode(url: URL) -> PairingCode {
        let now = clock.now()
        removeExpired(at: now)
        let code = SecureToken.generate()
        let expiresAt = now.addingTimeInterval(Self.codeValidity)
        codes[code] = expiresAt
        return PairingCode(code: code, url: url, expiresAt: expiresAt)
    }

    public func redeem(_ code: String) -> Bool {
        let now = clock.now()
        removeExpired(at: now)
        return codes.removeValue(forKey: code) != nil
    }

    private func removeExpired(at now: Date) {
        codes = codes.filter { $0.value > now }
    }
}
