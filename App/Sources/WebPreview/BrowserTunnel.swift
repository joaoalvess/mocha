import Foundation
import MochaClient
import MochaProtocol

struct BrowserTunnel: Sendable {
    let prepare: @Sendable () async throws -> Void
    let openChannel: TunnelChannelOpener
    let suspend: @Sendable () async -> Void

    static func demo(title: String) -> BrowserTunnel {
        BrowserTunnel(
            prepare: {},
            openChannel: { port in StaticPageTunnelChannel(title: title, port: port) },
            suspend: {}
        )
    }

    static func ssh(_ session: SSHSession, endpoint: SSHEndpoint) -> BrowserTunnel {
        BrowserTunnel(
            prepare: { _ = try await session.connect(to: endpoint) },
            openChannel: { port in try await session.openTunnelChannel(to: endpoint, remotePort: port) },
            suspend: { await session.disconnect() }
        )
    }
}
