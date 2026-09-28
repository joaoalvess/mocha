import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

struct WebServerHubTests {
    @Test func listWebServersRepliesWithTheScannerResultAndHostName() async throws {
        let servers = [
            WebServer(pid: 53243, process: "node", port: 5190, title: "Portal do cliente", directory: "/Users/joao/portal"),
            WebServer(pid: 5335, process: "node", port: 6173),
        ]
        try await withWebServerHub(FakeWebServerScanner(servers: servers)) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .listWebServers, id: "c-21")
            #expect(reply == .webServers(host: "Mac de Teste", servers: servers))
        }
    }

    @Test func listWebServersTagsEachServerWithItsWorkspace() async throws {
        let servers = [
            WebServer(pid: 1, process: "node", port: 5173, directory: "/Users/joao/mocha"),
            WebServer(pid: 2, process: "node", port: 5174, directory: "/Users/joao/mocha/.claude/worktrees/W4/apps/web"),
            WebServer(pid: 3, process: "ssh", port: 8181, directory: "/tmp"),
        ]
        try await withWebServerHub(FakeWebServerScanner(servers: servers)) { harness in
            harness.herdr.setWorkspaceRoots([
                WorkspaceRoot(workspaceId: "w1", path: "/Users/joao/mocha", isCheckout: true),
                WorkspaceRoot(workspaceId: "w2", path: "/Users/joao/mocha/.claude/worktrees/W4", isCheckout: true),
            ])
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .listWebServers, id: "c-3")
            guard case .webServers(_, let tagged) = reply else {
                Issue.record("resposta inesperada: \(reply)")
                return
            }
            #expect(tagged.map(\.workspaceId) == ["w1", "w2", nil])
        }
    }

    @Test func listWebServersWithoutScannerRepliesEmpty() async throws {
        try await withWebServerHub(nil) { harness in
            let (socket, _) = try await harness.pairedClient()
            let reply = try await socket.reply(to: .listWebServers, id: "c-2")
            #expect(reply == .webServers(host: "Mac de Teste", servers: []))
        }
    }

    private func withWebServerHub(_ scanner: (any WebServerScanning)?, _ body: (HubHarness) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-web-\(UUID().uuidString)", directoryHint: .isDirectory)
        let tree = Sample.defaultTree
        let herdr = FakeHerdrBridge(tree: tree, agents: Sample.herdrAgents(in: tree), available: true)
        let transcripts = FakeTranscriptProvider()
        let usage = FakeUsageProvider()
        let archive = FakeSessionArchive()
        let subagents = FakeSubagentProvider()
        let clock = ManualClock(origin: Sample.start)
        let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
        let pairing = Pairing(clock: clock)
        let hub = SessionHub(
            herdr: herdr,
            transcripts: transcripts,
            devices: devices,
            pairing: pairing,
            usage: usage,
            archive: archive,
            subagents: subagents,
            webServers: scanner,
            clock: clock,
            configuration: SessionHubConfiguration(hostName: "Mac de Teste", daemonVersion: "9.9.9")
        )
        await hub.start()
        let harness = HubHarness(
            herdr: herdr,
            transcripts: transcripts,
            usage: usage,
            archive: archive,
            subagents: subagents,
            clock: clock,
            devices: devices,
            pairing: pairing,
            hub: hub,
            directory: directory
        )
        do {
            try await body(harness)
        } catch {
            await hub.shutdown()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        await hub.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }
}
