import Foundation
import MochaProtocol

enum CodexSettingsChange: Sendable, Equatable {
    case model(String)
    case effort(String)
    case mode(String, model: String, effort: String?)
}

enum CodexControls {
    static let modelPagesLimit = 20
    static let threadPollInterval: Duration = .milliseconds(50)

    static func modelOption(_ raw: OrderedJSON) -> ModelOption? {
        guard let id = CodexProjection.nonEmpty(raw["id"]?.stringValue), raw["hidden"]?.boolValue != true else { return nil }
        let efforts = (raw["supportedReasoningEfforts"]?.arrayValue ?? []).compactMap { option -> EffortOption? in
            guard let level = CodexProjection.nonEmpty(option["reasoningEffort"]?.stringValue) else { return nil }
            return EffortOption(level: level, description: CodexProjection.nonEmpty(option["description"]?.stringValue))
        }
        return ModelOption(
            id: id,
            displayName: CodexProjection.nonEmpty(raw["displayName"]?.stringValue) ?? id,
            isDefault: raw["isDefault"]?.boolValue ?? false,
            defaultEffort: CodexProjection.nonEmpty(raw["defaultReasoningEffort"]?.stringValue),
            efforts: efforts
        )
    }

    static func threadSettingsParams(_ change: CodexSettingsChange, threadId: String) -> OrderedJSON {
        var members: [OrderedJSON.Member] = [.init("threadId", .string(threadId))]
        switch change {
        case .model(let model):
            members.append(.init("model", .string(model)))
        case .effort(let effort):
            members.append(.init("effort", .string(effort)))
        case .mode(let mode, let model, let effort):
            members.append(.init("collaborationMode", .object([
                .init("mode", .string(mode)),
                .init("settings", .object([
                    .init("model", .string(model)),
                    .init("reasoning_effort", effort.map(OrderedJSON.string) ?? .null),
                    .init("developer_instructions", .null),
                ])),
            ])))
        }
        return .object(members)
    }

    static func turnSetting(_ change: CodexSettingsChange) -> OrderedJSON.Member? {
        switch change {
        case .model(let model):
            .init("model", .string(model))
        case .effort(let effort):
            .init("effort", .string(effort))
        case .mode:
            nil
        }
    }

    static func launchArguments(model: String?, effort: String?) -> [String] {
        var arguments: [String] = []
        if let model { arguments += ["-m", model] }
        if let effort { arguments += ["-c", "model_reasoning_effort=\"\(effort)\""] }
        return arguments
    }
}

extension CodexService {
    func models() async throws -> [ModelOption] {
        var options: [ModelOption] = []
        var cursor: String?
        for _ in 0..<CodexControls.modelPagesLimit {
            var params: [OrderedJSON.Member] = []
            if let cursor { params.append(.init("cursor", .string(cursor))) }
            let result = try await request("model/list", params: .object(params))
            options += (result["data"]?.arrayValue ?? []).compactMap(CodexControls.modelOption)
            cursor = result["nextCursor"]?.stringValue
            if cursor == nil { break }
        }
        return options
    }

    func applySettings(_ change: CodexSettingsChange, to threadId: String) async throws {
        _ = try await request("thread/settings/update", params: CodexControls.threadSettingsParams(change, threadId: threadId))
        guard let setting = CodexControls.turnSetting(change), let turnId = await activeTurnId(for: threadId) else { return }
        do {
            _ = try await request("turn/settings/update", params: .object([
                .init("threadId", .string(threadId)), .init("turnId", .string(turnId)), setting,
            ]))
        } catch {
            codexLogger.info("turn settings of \(threadId, privacy: .public) not applied: \(String(describing: error), privacy: .public)")
        }
    }

    func compact(_ threadId: String) async throws {
        _ = try await request("thread/compact/start", params: .object([.init("threadId", .string(threadId))]))
    }

    func waitForThread(of paneId: AgentID, timeout: Duration) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let threadId = threadId(for: paneId) { return threadId }
            guard ContinuousClock.now < deadline, (try? await Task.sleep(for: CodexControls.threadPollInterval)) != nil else { return nil }
        }
    }
}
