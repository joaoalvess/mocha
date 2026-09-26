import Foundation
import MochaProtocol

enum DeepLink: Equatable {
    case agent(AgentID)
    case pair(PairingLink)

    static let scheme = "mocha"
    static let agentHost = "agent"
    static let pairHost = "pair"

    init?(_ url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == Self.scheme
        else { return nil }
        switch components.host?.lowercased() {
        case Self.agentHost:
            let agentId = String(components.path.drop { $0 == "/" })
            guard !agentId.isEmpty else { return nil }
            self = .agent(agentId)
        case Self.pairHost:
            guard let link = PairingLink(url) else { return nil }
            self = .pair(link)
        default:
            return nil
        }
    }
}
