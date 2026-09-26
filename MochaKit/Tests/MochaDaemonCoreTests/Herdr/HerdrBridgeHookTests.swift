import Foundation
import MochaHerdr
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

struct BranchedGitInspector: GitInspecting {
    let branch: String
    let inspector: GitInspector

    func branch(at directory: String) async -> String? {
        branch
    }

    func isDirty(at directory: String) async -> Bool {
        await inspector.isDirty(at: directory)
    }

    func invalidateDirty(at directory: String) async {
        await inspector.invalidateDirty(at: directory)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HerdrBridgeHookTests {
    static let newSession = "99999999-9999-4999-8999-999999999999"

    static let quietConfiguration = HerdrBridgeConfiguration(
        reconnectInterval: .milliseconds(50),
        snapshotDebounce: .milliseconds(10),
        treeDebounce: .milliseconds(10),
        paneUpdateProbeDelay: .seconds(30),
        agentDetectedProbeDelays: [.seconds(30)],
        sessionStartProbeDelays: [.zero, .milliseconds(300), .milliseconds(900), .milliseconds(1800)],
        reconciliationInterval: .seconds(30)
    )

    static func probes(_ harness: HerdrBridgeHarness, pane: String) async -> Int {
        await harness.server.requests(method: "agent.get").count { $0.stringParam("target") == pane }
    }

    @Test func sessionStartAsksHerdrUntilTheNewSessionShowsUp() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: Self.quietConfiguration)
        #expect(await HerdrWait.until { await Self.probes(harness, pane: "w1A:p1") == 1 })

        await harness.bridge.refreshAgent("w1A:p1", expectingSession: Self.newSession)
        #expect(await HerdrWait.until { await Self.probes(harness, pane: "w1A:p1") == 2 })
        #expect(await harness.recorder.count { $0 == .sessionChanged("w1A:p1", sessionId: Self.newSession) } == 0)

        await harness.server.setAgentSession(paneId: "w1A:p1", sessionId: Self.newSession)
        #expect(await harness.recorder.waitFor { $0 == .sessionChanged("w1A:p1", sessionId: Self.newSession) } != nil)
        #expect(await harness.waitForTree { treeAgent("w1A:p1", in: $0)?.sessionId == Self.newSession })
        let probes = await Self.probes(harness, pane: "w1A:p1")
        try await Task.sleep(for: .milliseconds(1000))
        #expect(await Self.probes(harness, pane: "w1A:p1") == probes)
        #expect(probes <= 5)
        try await harness.finish()
    }

    @Test func sessionStartForAKnownSessionAsksHerdrNothing() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: Self.quietConfiguration)
        #expect(await HerdrWait.until { await Self.probes(harness, pane: "w1A:p1") == 1 })

        await harness.bridge.refreshAgent("w1A:p1", expectingSession: "53360f7b-12da-40ad-b37f-37b246ccfc35")
        await harness.bridge.refreshAgent("w9:p9", expectingSession: Self.newSession)
        try await Task.sleep(for: .milliseconds(400))

        #expect(await Self.probes(harness, pane: "w1A:p1") == 1)
        #expect(await Self.probes(harness, pane: "w9:p9") == 0)
        try await harness.finish()
    }

    @Test func stopInvalidatesTheDirtyCacheAndTheNextTreeShowsTheNewStatus() async throws {
        let runner = FakeGitCommandRunner(result: GitCommandResult(exitCode: 0, output: Data()))
        let inspector = BranchedGitInspector(branch: "main", inspector: GitInspector(runner: runner))
        let harness = try await HerdrBridgeHarness.make(inspector: inspector, configuration: Self.quietConfiguration)
        let directory = "/Users/dev/projects/demo-app"
        #expect(treeWorkspace("w1A", in: await harness.bridge.tree())?.isDirty == false)
        #expect(runner.calls == [GitInspector.statusArguments(directory: directory)])

        runner.setResult(GitCommandResult(exitCode: 0, output: Data(" M Sources/App.swift\n".utf8)))
        #expect(await inspector.isDirty(at: directory) == false)

        await harness.bridge.refreshDirtyState(ofAgent: "w1A:p2")

        #expect(await harness.waitForTree { treeWorkspace("w1A", in: $0)?.isDirty == true })
        #expect(runner.calls.count == 2)
        await harness.bridge.refreshDirtyState(ofAgent: "w9:p9")
        #expect(runner.calls.count == 2)
        try await harness.finish()
    }
}
