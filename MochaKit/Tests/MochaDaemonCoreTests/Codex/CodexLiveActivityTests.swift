import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexLiveActivityTests {
    @Test func codexHighlightCarriesProviderAndUsesCodexInAlert() throws {
        var tracker = AgentActivityTracker()
        let agent = AgentSummary(id: "w1:p2", kind: "codex", status: .working, title: "Conversa", workspaceLabel: "projeto")
        let snapshot = try #require(tracker.snapshots(of: LiveActivityInput(agents: [agent]), at: Date(timeIntervalSince1970: 100), titleLimit: 60)[agent.id])
        #expect(snapshot.agent.provider == .codex)
        #expect(snapshot.startAlert.title == "Codex trabalhando · projeto")
        #expect(snapshot.alertContent(.turnDone).title == "Codex terminou · projeto")
        let object = try JSONSerialization.jsonObject(with: ApnsPayloadEncoding.encoder.encode(snapshot.agent)) as? [String: Any]
        #expect(object?["provider"] as? String == "codex")
    }

    @Test func claudeHighlightOmitsProviderForCompatibility() throws {
        var tracker = AgentActivityTracker()
        let agent = AgentSummary(id: "w1:p1", kind: "claude", status: .working, title: "Conversa", workspaceLabel: "projeto")
        let snapshot = try #require(tracker.snapshots(of: LiveActivityInput(agents: [agent]), at: Date(timeIntervalSince1970: 100), titleLimit: 60)[agent.id])
        #expect(snapshot.agent.provider == nil)
        let object = try JSONSerialization.jsonObject(with: ApnsPayloadEncoding.encoder.encode(snapshot.agent)) as? [String: Any]
        #expect(object?["provider"] == nil)
    }
}
