import Foundation
import MochaProtocol

public enum DeepLink: Sendable, Equatable {
    case agent(AgentID)
    case pair(PairingLink)

    public init?(_ url: URL) {
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

    public var url: URL? {
        switch self {
        case .agent(let agentId):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = Self.agentHost
            components.percentEncodedPath = "/" + (agentId.addingPercentEncoding(withAllowedCharacters: Self.pathCharacters) ?? agentId)
            return components.url
        case .pair(let link):
            return link.link
        }
    }

    private static let scheme = "mocha"
    private static let agentHost = "agent"
    private static let pairHost = "pair"
    private static let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
}
