import Foundation
import MochaHerdr
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

enum HerdrBridgeFixtures {
    static func snapshot(_ name: String) throws -> HerdrSessionSnapshot {
        struct Envelope: Decodable {
            struct Result: Decodable {
                let snapshot: HerdrSessionSnapshot
            }

            let result: Result
        }
        return try JSONDecoder().decode(Envelope.self, from: HerdrFixtures.data(name)).result.snapshot
    }

    static func state(_ name: String) throws -> HerdrState {
        HerdrState(snapshot: try snapshot(name))
    }

    static func eventLine(_ fixture: String, _ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: HerdrFixtures.data(fixture)) as? [String: Any])
        var data = try #require(object["data"] as? [String: Any])
        mutate(&data)
        object["data"] = data
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func eventLine(_ json: String) -> Data {
        Data(json.utf8)
    }
}

struct HerdrBridgeHarness {
    static let allowedMethods: Set<String> = [
        "events.subscribe", "ping", "session.snapshot", "agent.list", "agent.get", "agent.prompt", "agent.send_keys",
        "tab.create", "agent.start", "agent.wait", "pane.read", "pane.close", "pane.split",
    ]

    static let fastConfiguration = HerdrBridgeConfiguration(
        reconnectInterval: .milliseconds(50),
        snapshotDebounce: .milliseconds(10),
        treeDebounce: .milliseconds(10),
        paneUpdateProbeDelay: .milliseconds(40),
        agentDetectedProbeDelays: [.milliseconds(40), .milliseconds(160)],
        reconciliationInterval: .milliseconds(60)
    )

    let server: FakeHerdrServer
    let bridge: HerdrBridge
    let git: FakeGitInspector
    let recorder: HerdrBridgeEventRecorder

    static func make(
        snapshot: String = "session.snapshot.two-agents-one-tab.response.json",
        git: FakeGitInspector = FakeGitInspector(),
        inspector: (any GitInspecting)? = nil,
        configuration: HerdrBridgeConfiguration = fastConfiguration,
        start: Bool = true
    ) async throws -> HerdrBridgeHarness {
        let server = FakeHerdrServer()
        try await server.loadSnapshot(fixture: snapshot)
        try await server.start()
        let client = HerdrClient(
            configuration: HerdrClientConfiguration(socketPath: server.socketPath, requestTimeout: .seconds(2), promptTimeout: .seconds(2))
        )
        let bridge = HerdrBridge(client: client, git: inspector ?? git, configuration: configuration)
        let harness = HerdrBridgeHarness(server: server, bridge: bridge, git: git, recorder: HerdrBridgeEventRecorder(bridge.events()))
        if start {
            try await harness.start()
        }
        return harness
    }

    func start() async throws {
        await bridge.start()
        try #require(await HerdrWait.until { await bridge.isAvailable })
        let agentPanes = try await expectedAgentPanes()
        try #require(await HerdrWait.until { await server.paneSubscriptionIds == agentPanes })
    }

    func expectedAgentPanes() async throws -> [String] {
        let snapshot = try await client().sessionSnapshot()
        return snapshot.panes.filter { $0.agent != nil }.map(\.paneId).sorted()
    }

    func client() -> HerdrClient {
        HerdrClient(configuration: HerdrClientConfiguration(socketPath: server.socketPath))
    }

    func waitForTree(_ condition: @escaping @Sendable ([WorkspaceNode]) -> Bool) async -> Bool {
        let bridge = self.bridge
        return await HerdrWait.until { condition(await bridge.tree()) }
    }

    func requestCount(_ method: String) async -> Int {
        await server.requests(method: method).count
    }

    func finish() async throws {
        let schema = try HerdrSchemaValidator.load()
        for request in await server.requests {
            #expect(schema.requestViolations(request.line) == [], "\(request.method)")
            #expect(Self.allowedMethods.contains(request.method), "\(request.method)")
            if ["agent.get", "agent.prompt", "agent.send_keys", "agent.wait"].contains(request.method) {
                #expect(request.stringParam("target")?.isEmpty == false)
            }
        }
        #expect(await server.writesAfterAck == 0)
        await bridge.stop()
        #expect(await HerdrWait.until { await server.isIdle })
        await recorder.cancel()
        await server.stop()
    }
}

func treeAgent(_ id: AgentID, in tree: [WorkspaceNode]) -> AgentSummary? {
    for workspace in tree {
        for tab in workspace.tabs {
            if let agent = tab.agents.first(where: { $0.id == id }) {
                return agent
            }
        }
        if let nested = treeAgent(id, in: workspace.children) {
            return nested
        }
    }
    return nil
}

func treeWorkspace(_ id: WorkspaceID, in tree: [WorkspaceNode]) -> WorkspaceNode? {
    for node in tree {
        if node.id == id {
            return node
        }
        if let nested = treeWorkspace(id, in: node.children) {
            return nested
        }
    }
    return nil
}

func herdrStatusEvents(for id: AgentID, in events: [HerdrBridgeEvent]) -> [AgentStatus] {
    events.compactMap { event in
        if case .agentStatus(id, let status, _) = event { status } else { nil }
    }
}

func expectHerdrBridgeError(_ expected: HerdrBridgeError, _ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("expected \(expected)")
    } catch let error as HerdrBridgeError {
        #expect(error == expected)
    } catch {
        Issue.record("unexpected error \(error)")
    }
}
