import Foundation
import MochaProtocol

extension SessionHub {
    enum ControlCommand: Sendable {
        case model(ModelAlias)
        case effort(EffortLevel)
        case mode(PermissionModeTarget)
    }

    func runControl(_ command: ControlCommand, agentId: AgentID, id: String, clientId: UUID) async {
        guard await herdr.isAvailable else {
            send(.herdrUnavailable, id: id, to: clientId)
            return
        }
        let resolved = await herdr.resolve(agentId)
        guard let agent = await herdr.agent(resolved) else {
            send(.agentNotFound, id: id, to: clientId)
            return
        }
        guard agent.kind == TreeComposer.claudeKind else {
            send(.notClaude, id: id, to: clientId)
            return
        }
        if case .effort = command, !AgentControls.hasEffort(model: composedAgent(resolved)?.model) {
            send(.effortUnavailable, id: id, to: clientId)
            return
        }
        guard controlsInFlight.insert(resolved).inserted else {
            send(.screenBusy, id: id, to: clientId)
            return
        }
        defer { controlsInFlight.remove(resolved) }
        do {
            try await perform(command, on: resolved)
        } catch let error as HerdrBridgeError {
            send(.herdr(error), id: id, to: clientId)
            return
        } catch {
            send(.herdrFailed, id: id, to: clientId)
            return
        }
        send(.ack(), id: id, to: clientId)
        await flushTree()
    }

    private func perform(_ command: ControlCommand, on agentId: AgentID) async throws {
        switch command {
        case .mode(let mode):
            let read = try await herdr.setMode(agentId, mode: mode)
            updateControls(of: agentId) { controls, meta in
                controls.permissionMode = AgentControls.Override(value: read, transcriptBaseline: meta?.permissionMode)
            }
        case .effort(let level):
            try await herdr.setEffort(agentId, level: level)
            updateControls(of: agentId) { controls, _ in
                controls.effort = level.rawValue
                controls.knowsEffort = true
            }
        case .model(let model):
            await modelSwitches?.begin(agentId)
            do {
                try await herdr.setModel(agentId, model: model)
            } catch {
                await modelSwitches?.end(agentId)
                throw error
            }
            await modelSwitches?.end(agentId)
            if let mode = await herdr.currentMode(agentId) {
                updateControls(of: agentId) { controls, meta in
                    controls.permissionMode = AgentControls.Override(value: mode, transcriptBaseline: meta?.permissionMode)
                }
            }
        }
    }

    func applyControls(from hook: ReceivedHook) {
        let context = hook.event.context
        guard context.subagentId == nil else { return }
        switch hook.event {
        case .stop:
            updateControls(of: hook.agentId, sessionId: context.sessionId) { controls, meta in
                controls.applyPermissionMode(context.permissionMode, baseline: meta?.permissionMode)
                controls.effort = context.effort
                controls.knowsEffort = true
            }
        case .userPromptSubmit:
            updateControls(of: hook.agentId, sessionId: context.sessionId) { controls, meta in
                controls.applyPermissionMode(context.permissionMode, baseline: meta?.permissionMode)
            }
        case .postModelSwitch(let change) where !change.isAutomatic:
            updateControls(of: hook.agentId, sessionId: context.sessionId) { controls, meta in
                controls.model = AgentControls.Override(value: change.toModel, transcriptBaseline: meta?.model)
                if !AgentControls.hasEffort(model: change.toModel) {
                    controls.effort = nil
                    controls.knowsEffort = true
                }
            }
        case .sessionStart, .notification, .permissionRequest, .preModelSwitch, .postModelSwitch:
            return
        }
        refreshChatMetas()
        scheduleTreeFlush()
    }

    func pruneAgentControls() {
        let agents = Dictionary(TreeComposer.agents(in: baseTree).map { ($0.id, $0.sessionId) }, uniquingKeysWith: { first, _ in first })
        agentControls = agentControls.filter { agentId, controls in
            agents[agentId].map { $0 == controls.sessionId } ?? false
        }
    }

    private func updateControls(of agentId: AgentID, _ change: (inout AgentControls, TranscriptMeta?) -> Void) {
        updateControls(of: agentId, sessionId: TreeComposer.agent(agentId, in: baseTree)?.sessionId, change)
    }

    private func updateControls(of agentId: AgentID, sessionId: String?, _ change: (inout AgentControls, TranscriptMeta?) -> Void) {
        var controls = agentControls[agentId].flatMap { $0.sessionId == sessionId ? $0 : nil } ?? AgentControls(sessionId: sessionId)
        change(&controls, sessionId.flatMap { metas[$0] })
        agentControls[agentId] = controls
    }
}

extension AgentControls {
    mutating func applyPermissionMode(_ mode: String?, baseline: String?) {
        guard let mode else { return }
        permissionMode = Override(value: mode, transcriptBaseline: baseline)
    }
}
