import Foundation
import MochaProtocol

extension HubError {
    static let modelsOnlyForCodex = HubError(code: .invalidPayload, message: "Lista de modelos só para Codex")
    static let codexModelUnavailable = HubError(code: .invalidPayload, message: "Modelo indisponível no Codex")
    static let codexEffortUnavailable = HubError(code: .invalidPayload, message: "Effort indisponível neste modelo")
    static let codexModeUnavailable = HubError(code: .invalidPayload, message: "Modo indisponível no Codex")
    static let codexCommandUnavailable = HubError(code: .invalidPayload, message: "Comando indisponível no Codex")
    static let codexClearInProgress = HubError(code: .internal, message: "O /clear anterior ainda está em andamento.")
    static let codexClearTimedOut = HubError(code: .internal, message: "O Codex novo não abriu uma conversa a tempo.")
}

extension SessionHub {
    static let codexClearBindTimeout: Duration = .seconds(15)
    static let codexClearPollInterval: Duration = .milliseconds(50)

    enum ControlRequest: Sendable {
        case model(String)
        case effort(String)
        case mode(PermissionModeTarget)
    }

    enum ControlCommand: Sendable {
        case model(ModelAlias)
        case effort(EffortLevel)
        case mode(PermissionModeTarget)

        init?(_ request: ControlRequest) {
            switch request {
            case .model(let model):
                guard let alias = ModelAlias(rawValue: model) else { return nil }
                self = .model(alias)
            case .effort(let level):
                guard let effort = EffortLevel(rawValue: level) else { return nil }
                self = .effort(effort)
            case .mode(let mode):
                self = .mode(mode)
            }
        }
    }

    private struct CodexTarget {
        let codex: any CodexServing
        let threadId: String
    }

    private enum CodexClearError: Error {
        case timedOut
    }

    func runControl(_ request: ControlRequest, agentId: AgentID, id: String, clientId: UUID) async {
        guard await herdr.isAvailable else {
            send(.herdrUnavailable, id: id, to: clientId)
            return
        }
        let resolved = await herdr.resolve(agentId)
        guard let agent = await herdr.agent(resolved) else {
            send(.agentNotFound, id: id, to: clientId)
            return
        }
        if agent.kind == TreeComposer.codexKind {
            await runCodexControl(request, agentId: resolved, id: id, clientId: clientId)
            return
        }
        guard agent.kind == TreeComposer.claudeKind else {
            send(.notClaude, id: id, to: clientId)
            return
        }
        guard let command = ControlCommand(request) else {
            send(.invalidMessage, id: id, to: clientId)
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

    func listModels(_ agentId: AgentID, id: String, clientId: UUID) async {
        guard await herdr.isAvailable else {
            send(.herdrUnavailable, id: id, to: clientId)
            return
        }
        let resolved = await herdr.resolve(agentId)
        guard let agent = await herdr.agent(resolved) else {
            send(.agentNotFound, id: id, to: clientId)
            return
        }
        guard agent.kind == TreeComposer.codexKind else {
            send(.modelsOnlyForCodex, id: id, to: clientId)
            return
        }
        guard let target = codexTarget(resolved) else {
            send(.codexUnavailable, id: id, to: clientId)
            return
        }
        do {
            send(.models(agentId: resolved, options: try await target.codex.models()), id: id, to: clientId)
        } catch {
            send(codexError(error), id: id, to: clientId)
        }
    }

    func runCodexSlash(_ command: String, agent: HerdrAgent, id: String, clientId: UUID) async {
        guard let target = codexTarget(agent.paneId) else {
            send(.codexUnavailable, id: id, to: clientId)
            return
        }
        switch command.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "/compact":
            do {
                try await target.codex.compact(target.threadId)
                send(.ack(), id: id, to: clientId)
            } catch {
                send(codexError(error), id: id, to: clientId)
            }
        case "/clear":
            await clearCodex(agent, target: target, id: id, clientId: clientId)
        default:
            send(.codexCommandUnavailable, id: id, to: clientId)
        }
    }

    private func runCodexControl(_ request: ControlRequest, agentId: AgentID, id: String, clientId: UUID) async {
        guard let target = codexTarget(agentId) else {
            send(.codexUnavailable, id: id, to: clientId)
            return
        }
        let codex = target.codex
        do {
            let settings = await codex.threadSettings(for: target.threadId) ?? CodexThreadSettings()
            let change: CodexSettingsChange
            switch request {
            case .model(let model):
                guard try await codex.models().contains(where: { $0.id == model }) else {
                    send(.codexModelUnavailable, id: id, to: clientId)
                    return
                }
                change = .model(model)
            case .effort(let level):
                let option = try await codex.models().first { $0.id == settings.model }
                guard option?.efforts.contains(where: { $0.level == level }) == true else {
                    send(.codexEffortUnavailable, id: id, to: clientId)
                    return
                }
                change = .effort(level)
            case .mode(let mode):
                guard mode == .plan || mode == .default else {
                    send(.codexModeUnavailable, id: id, to: clientId)
                    return
                }
                guard let model = settings.model else {
                    send(.codexUnavailable, id: id, to: clientId)
                    return
                }
                change = .mode(mode.rawValue, model: model, effort: try await currentEffort(settings, codex: codex))
            }
            try await codex.applySettings(change, to: target.threadId)
            send(.ack(), id: id, to: clientId)
        } catch {
            send(codexError(error), id: id, to: clientId)
        }
    }

    private func clearCodex(_ agent: HerdrAgent, target: CodexTarget, id: String, clientId: UUID) async {
        let oldId = agent.paneId
        guard controlsInFlight.insert(oldId).inserted else {
            send(.codexClearInProgress, id: id, to: clientId)
            return
        }
        let codex = target.codex
        let settings = await codex.threadSettings(for: target.threadId) ?? CodexThreadSettings()
        let effort = try? await currentEffort(settings, codex: codex)
        let arguments = CodexControls.launchArguments(model: settings.model, effort: effort)
        let remote = "unix://\(codex.socketPath)"
        let herdr = herdr
        let since = Date().addingTimeInterval(-2)
        Task { [weak self] in
            let reply: Result<(paneId: AgentID, threadId: String), HubError>
            do {
                let split = try await herdr.splitPane(oldId)
                let cwd = split.cwd ?? agent.cwd ?? agent.foregroundCwd
                try await herdr.startCodexAgent(in: split.paneId, directory: cwd, remote: remote, extraArguments: arguments)
                let deadline = ContinuousClock.now + Self.codexClearBindTimeout
                guard let self, await self.codexAgentAppears(split.paneId, before: deadline), let cwd else { throw CodexClearError.timedOut }
                await codex.expectPane(split.paneId, cwd: cwd, since: since)
                guard let threadId = await codex.waitForThread(of: split.paneId, timeout: ContinuousClock.now.duration(to: deadline)) else {
                    throw CodexClearError.timedOut
                }
                if let mode = settings.mode, let model = await Self.modeModel(settings, threadId: threadId, codex: codex) {
                    try await codex.applySettings(.mode(mode, model: model, effort: effort), to: threadId)
                }
                try await herdr.closePane(oldId)
                reply = .success((split.paneId, threadId))
            } catch let error as HerdrBridgeError {
                reply = .failure(.herdr(error))
            } catch CodexClearError.timedOut {
                reply = .failure(.codexClearTimedOut)
            } catch {
                reply = .failure(await self?.codexError(error) ?? .codexFailed)
            }
            await self?.finishCodexClear(reply, from: oldId, id: id, clientId: clientId)
        }
    }

    private static func modeModel(_ settings: CodexThreadSettings, threadId: String, codex: any CodexServing) async -> String? {
        if let model = settings.model { return model }
        return await codex.threadSettings(for: threadId)?.model
    }

    private func codexAgentAppears(_ paneId: AgentID, before deadline: ContinuousClock.Instant) async -> Bool {
        while TreeComposer.agent(paneId, in: baseTree)?.kind != TreeComposer.codexKind {
            guard ContinuousClock.now < deadline, (try? await Task.sleep(for: Self.codexClearPollInterval)) != nil else { return false }
        }
        return true
    }

    private func finishCodexClear(_ reply: Result<(paneId: AgentID, threadId: String), HubError>, from oldId: AgentID, id: String, clientId: UUID) {
        controlsInFlight.remove(oldId)
        switch reply {
        case .success(let created):
            handOver(from: oldId, to: created.paneId, threadId: created.threadId)
            send(.ack(agentId: created.paneId), id: id, to: clientId)
        case .failure(let error):
            send(error, id: id, to: clientId)
        }
    }

    private func handOver(from oldId: AgentID, to newId: AgentID, threadId: String) {
        if let controls = agentControls.removeValue(forKey: oldId) {
            agentControls[newId] = controls
        }
        for clientId in Array(clients.keys) {
            if clients[clientId]?.foreground?.agentId == oldId {
                clients[clientId]?.foreground?.agentId = newId
            }
            guard var chat = clients[clientId]?.chats.removeValue(forKey: .agent(oldId)) else { continue }
            chat.target = .agent(newId)
            chat.codexThreadId = threadId
            chat.codexItems = [:]
            clients[clientId]?.chats[.agent(newId)]?.cancel()
            clients[clientId]?.chats[.agent(newId)] = chat
        }
        publishOpenChats()
        publishLiveActivityInput()
        refreshChatMetas()
        scheduleTreeFlush()
    }

    private func codexTarget(_ agentId: AgentID) -> CodexTarget? {
        guard let codex, codexConnected, let threadId = codexPanes[agentId]?.threadId else { return nil }
        return CodexTarget(codex: codex, threadId: threadId)
    }

    private func currentEffort(_ settings: CodexThreadSettings, codex: any CodexServing) async throws -> String? {
        if let effort = settings.effort { return effort }
        return try await codex.models().first { $0.id == settings.model }?.defaultEffort
    }

    private func codexError(_ error: any Error) -> HubError {
        if case CodexServiceError.unavailable = error {
            return .codexUnavailable
        }
        gatewayLogger.error("codex control failed: \(String(describing: error), privacy: .public)")
        return .codexFailed
    }
}

extension AgentControls {
    mutating func applyPermissionMode(_ mode: String?, baseline: String?) {
        guard let mode else { return }
        permissionMode = Override(value: mode, transcriptBaseline: baseline)
    }
}
