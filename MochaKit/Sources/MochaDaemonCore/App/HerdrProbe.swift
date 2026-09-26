import Foundation
import MochaHerdr

public enum HerdrPing: Sendable, Equatable {
    case missingSocket(String)
    case failed(String)
    case reachable(HerdrServerInfo)
}

public enum HerdrAgentCount: Sendable, Equatable {
    case missingSocket(String)
    case failed(String)
    case counted(total: Int, claude: Int)
}

public struct HerdrProbe: Sendable {
    public let socketPath: String
    private let client: HerdrClient

    public init(socketPath: String) {
        self.socketPath = socketPath
        self.client = HerdrClient(configuration: HerdrClientConfiguration(socketPath: socketPath))
    }

    public func ping() async -> HerdrPing {
        guard socketExists else { return .missingSocket(socketPath) }
        do {
            let pong = try await client.ping()
            return .reachable(HerdrServerInfo(version: pong.version, protocolVersion: pong.protocolVersion))
        } catch {
            return .failed(Self.describe(error))
        }
    }

    public func agents() async -> HerdrAgentCount {
        guard socketExists else { return .missingSocket(socketPath) }
        do {
            let panes = try await client.agentList().filter { $0.agent != nil }
            return .counted(total: panes.count, claude: panes.filter { $0.agent == TreeComposer.claudeKind }.count)
        } catch {
            return .failed(Self.describe(error))
        }
    }

    private var socketExists: Bool {
        var info = stat()
        return lstat(socketPath, &info) == 0 && info.st_mode & S_IFMT == S_IFSOCK
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case HerdrClientError.connectionFailed(let detail):
            return "sem conexão com o socket (\(detail))"
        case HerdrClientError.timeout(let method):
            return "\(method) sem resposta"
        case HerdrClientError.closedWithoutResponse(let method):
            return "\(method) fechou sem resposta"
        case HerdrClientError.invalidResponse(let method, let detail):
            return "resposta inválida de \(method): \(detail)"
        case HerdrClientError.server(let error):
            return "\(error.code.rawValue): \(error.message)"
        default:
            return String(describing: error)
        }
    }
}
