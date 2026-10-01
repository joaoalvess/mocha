import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct CodexStaleServersTests {
    static let socketPath = "/Users/dev/Library/Application Support/Mocha/codex.sock"

    @Test func findsOnlyServersListeningOnTheMochaSocket() {
        let output = """
          84380 /opt/homebrew/bin/codex app-server --listen unix:///Users/dev/Library/Application Support/Mocha/codex.sock
           8928 /Users/dev/.codex/packages/app-server-daemon/bin/codex app-server --listen unix:// --managed-daemon
          59536 codex --remote unix:///Users/dev/Library/Application Support/Mocha/codex.sock
            412 /usr/local/bin/codex app-server --listen unix:///Users/dev/Library/Application Support/Mocha/codex.sock
          77000 rg app-server --listen unix:///Users/dev/Library/Application Support/Mocha/codex.sock.bak
        """
        #expect(CodexStaleServers.pids(inProcessList: output, socketPath: Self.socketPath) == [84380, 412])
    }

    @Test func emptyListFindsNothing() {
        #expect(CodexStaleServers.pids(inProcessList: "", socketPath: Self.socketPath).isEmpty)
    }
}
