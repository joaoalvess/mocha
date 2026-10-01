import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

@Suite(.timeLimit(.minutes(1)))
struct DemoControlsTests {
    private let agentId: AgentID = "w1:p1"

    @Test func demoAgentStartsWithEffortAndMode() throws {
        let harness = try DemoHarness()
        let agent = try #require(harness.dataset.workspaces.agent(withId: agentId))
        #expect(agent.effort == "xhigh")
        #expect(agent.permissionMode == "acceptEdits")
    }

    @Test func setModelUpdatesChatMetaAndTree() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(agentId)

        let ack = try await harness.request(.setModel(agentId: agentId, model: "sonnet"))

        #expect(ack.message == .ack())
        let meta = try await nextMeta(harness)
        #expect(meta.model == "claude-sonnet-5")
        #expect(meta.effort == "xhigh")
        let agent = try await nextTreeAgent(harness)
        #expect(agent.model == "claude-sonnet-5")
    }

    @Test func haikuDropsEffortAndRejectsAutoAndEffort() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(agentId)

        _ = try await harness.request(.setModel(agentId: agentId, model: "haiku"))
        let meta = try await nextMeta(harness)
        #expect(meta.effort == nil)
        #expect(meta.model?.contains("haiku") == true)

        let mode = try await harness.error(for: .setMode(agentId: agentId, mode: .auto))
        #expect(mode.code == .modeUnavailable)
        let effort = try await harness.error(for: .setEffort(agentId: agentId, level: "low"))
        #expect(effort.code == .invalidPayload)
    }

    @Test func setEffortAndModeUpdateMeta() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        _ = try await harness.page(agentId)

        _ = try await harness.request(.setEffort(agentId: agentId, level: "low"))
        #expect(try await nextMeta(harness).effort == "low")
        #expect(try await nextTreeAgent(harness).effort == "low")

        _ = try await harness.request(.setMode(agentId: agentId, mode: .plan))
        #expect(try await nextMeta(harness).permissionMode == "plan")
        #expect(try await nextTreeAgent(harness).permissionMode == "plan")
    }

    @Test func controlsRejectCodexWithoutControl() async throws {
        let harness = try DemoHarness()
        try await harness.connect()
        let codex = try #require(harness.dataset.workspaces.allAgents.first { $0.kind == "codex" && $0.controlAvailable == false })

        let failure = try await harness.error(for: .setMode(agentId: codex.id, mode: .plan))

        #expect(failure.code == .codexUnavailable)
    }

    private func nextMeta(_ harness: DemoHarness) async throws -> ChatMeta {
        let envelope = try await harness.messages.next { envelope in
            if case .chatMeta = envelope.message { true } else { false }
        }
        guard case .chatMeta(_, let meta) = envelope.message else { throw UnexpectedMessage(envelope: envelope) }
        return meta
    }

    private func nextTreeAgent(_ harness: DemoHarness) async throws -> AgentSummary {
        let envelope = try await harness.messages.next { $0.message.changedWorkspaces != nil }
        let agent = envelope.message.changedWorkspaces?.agent(withId: agentId)
        return try #require(agent)
    }
}
