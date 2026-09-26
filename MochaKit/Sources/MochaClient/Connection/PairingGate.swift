import Foundation
import MochaProtocol

public struct PairingGate: Sendable, Equatable {
    public private(set) var isRequired = false
    public private(set) var problem: ConnectionProblem?
    public private(set) var connectingHost: String?

    public init() {}

    public var showsPairing: Bool {
        isRequired || connectingHost != nil
    }

    @discardableResult
    public mutating func begin(_ link: PairingLink) -> Bool {
        let wasShowing = showsPairing
        problem = nil
        connectingHost = Self.displayName(for: link.url)
        return !wasShowing
    }

    @discardableResult
    public mutating func apply(_ state: ConnectionState) -> Bool {
        let wasShowing = showsPairing
        switch state {
        case .connected:
            isRequired = false
            problem = nil
            connectingHost = nil
        case .pairingRequired(let newProblem):
            isRequired = true
            problem = newProblem
            connectingHost = nil
        case .waitingToRetry(let failure), .failed(let failure):
            if connectingHost != nil {
                isRequired = true
                problem = failure
                connectingHost = nil
            }
        case .idle:
            connectingHost = nil
        case .connecting:
            break
        }
        return !wasShowing && showsPairing
    }

    public static func displayName(for url: URL) -> String {
        guard let host = url.host(), !host.isEmpty else { return url.absoluteString }
        return host.split(separator: ".").first.map(String.init) ?? host
    }
}
