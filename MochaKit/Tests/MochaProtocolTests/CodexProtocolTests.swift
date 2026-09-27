import Foundation
import Testing
@testable import MochaProtocol

@Suite struct CodexProtocolTests {
    @Test func codexTabAndThreadUseProviderQualifiedWireValues() throws {
        let tab = try JSONDecoder().decode(
            ClientEnvelope.self,
            from: ProtocolFixtures.data("client.newAgentTab.codex.json")
        )
        #expect(tab.message == .newAgentTab(workspaceId: "w17", kind: .codex))

        let chat = try JSONDecoder().decode(
            ClientEnvelope.self,
            from: ProtocolFixtures.data("client.openChat.codex.json")
        )
        guard case .openChat(let target, _, _) = chat.message else {
            Issue.record("Expected openChat")
            return
        }
        #expect(target == .codexThread("d9a36f15-7b82-4e61-927f-b38c82055144"))
    }

    @Test func legacyClaudeDataDefaultsToClaude() throws {
        let tab = try JSONDecoder().decode(
            ClientEnvelope.self,
            from: ProtocolFixtures.data("client.newAgentTab.json")
        )
        #expect(tab.message == .newAgentTab(workspaceId: "w17", kind: .claude))

        let archived = try JSONDecoder().decode(
            ServerEnvelope.self,
            from: ProtocolFixtures.data("server.archived.json")
        )
        guard case .archived(let sessions) = archived.message else {
            Issue.record("Expected archived sessions")
            return
        }
        #expect(sessions.allSatisfy { $0.provider == .claude })
    }

    @Test func codexUsageKeepsServerWindowDuration() throws {
        let envelope = try JSONDecoder().decode(
            ServerEnvelope.self,
            from: ProtocolFixtures.data("server.usage.codex.json")
        )
        guard case .usage(let usage) = envelope.message else {
            Issue.record("Expected usage")
            return
        }
        #expect(usage.provider == .codex)
        #expect(usage.windows.map(\.windowDurationMins) == [300])
        #expect(usage.windows.map(\.usedPercent) == [34])
    }

    @Test func agentControlCapabilityIsExplicit() throws {
        let agent = AgentSummary(
            id: "w1:p1",
            kind: "codex",
            status: .idle,
            title: "Codex",
            workspaceLabel: "Mocha",
            controlAvailable: false
        )
        let encoded = try JSONEncoder().encode(agent)
        #expect(try JSONDecoder().decode(AgentSummary.self, from: encoded).controlAvailable == false)
    }

    @Test func codexArchiveRetainsProviderAcrossRoundTrip() throws {
        let envelope = try JSONDecoder().decode(
            ServerEnvelope.self,
            from: ProtocolFixtures.data("server.archived.codex.json")
        )
        guard case .archived(let sessions) = envelope.message else {
            Issue.record("Expected archived sessions")
            return
        }
        #expect(sessions.count == 1)
        #expect(sessions.first?.provider == .codex)
        let encoded = try JSONEncoder().encode(envelope)
        #expect(try JSONDecoder().decode(ServerEnvelope.self, from: encoded) == envelope)

        let archiveRequest = try JSONDecoder().decode(
            ClientEnvelope.self,
            from: ProtocolFixtures.data("client.archive.codex.json")
        )
        #expect(archiveRequest.message == .archive(
            sessionId: "d9a36f15-7b82-4e61-927f-b38c82055144",
            provider: .codex
        ))
    }
}
