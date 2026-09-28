import Foundation
import MochaClient
import MochaProtocol

extension AppSession {
    func browserTunnel(for server: WebServer, isDemo: Bool) async throws -> BrowserTunnel {
        if isDemo {
            return .demo(title: server.displayTitle)
        }
        let credential = try? await KeychainTokenStore().load()
        let endpoint: SSHEndpoint
        do {
            endpoint = try SSHEndpoint.resolve(gatewayURL: credential?.url, hostInfo: host)
        } catch {
            throw SSHSessionError.endpoint(error)
        }
        return .ssh(ssh, endpoint: endpoint)
    }
}
