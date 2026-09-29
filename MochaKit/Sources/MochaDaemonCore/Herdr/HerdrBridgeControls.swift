import Foundation
import MochaHerdr
import MochaProtocol

extension HerdrBridge {
    public func setMode(_ id: AgentID, mode target: PermissionModeTarget) async throws -> String {
        try ensureNotBlocked(id)
        let screen = try await readScreen(id, lines: ClaudeScreen.busyScanLines)
        guard !ClaudeScreen.isBusy(screen), let start = ClaudeScreen.mode(fromFooter: ClaudeScreen.lastLine(screen)) else {
            throw HerdrBridgeError.screenBusy
        }
        var current = start
        for _ in 0..<configuration.controls.maxModeKeys where current != target.rawValue {
            try await sendKeys(id, [ClaudeScreen.modeKey])
            current = try await waitForModeChange(id, from: current)
            guard current != start else { throw HerdrBridgeError.modeUnavailable }
        }
        guard current == target.rawValue else { throw HerdrBridgeError.modeUnavailable }
        return current
    }

    public func currentMode(_ id: AgentID) async -> String? {
        guard let screen = try? await readScreen(id, lines: 1) else { return nil }
        return ClaudeScreen.mode(fromFooter: ClaudeScreen.lastLine(screen))
    }

    public func setModel(_ id: AgentID, model: ModelAlias) async throws {
        try ensureNotBlocked(id)
        try await ensureScreenFree(id, strict: true)
        try await command { client in
            _ = try await client.agentPrompt(target: id, text: "/model")
        }
        guard let opened = try await pollScreen(id, { text in
            ClaudeScreen.modelPicker(text).map { (picker: $0, confirmations: ClaudeScreen.modelConfirmations(text).count) }
        }) else {
            throw await selectorFailure(id, "O seletor de modelo não abriu no terminal.")
        }
        guard let row = ClaudeScreen.row(for: model, in: opened.picker) else {
            throw await selectorFailure(id, "O modelo \(model.rawValue) não está no seletor.")
        }
        let moves = ClaudeScreen.moves(from: opened.picker.cursor, to: row, back: "up", forward: "down")
        if !moves.isEmpty {
            try await sendKeys(id, moves)
            guard try await pollScreen(id, { ClaudeScreen.modelPicker($0)?.cursor == row ? true : nil }) != nil else {
                throw await selectorFailure(id, "O cursor do seletor de modelo não chegou ao alvo.")
            }
        }
        try await sendKeys(id, [ClaudeScreen.confirmKey])
        guard let confirmed = try await pollScreen(id, { text -> String? in
            let confirmations = ClaudeScreen.modelConfirmations(text)
            guard !text.contains(ClaudeScreen.modelPickerMarker), confirmations.count > opened.confirmations else { return nil }
            return confirmations.last
        }) else {
            throw await selectorFailure(id, "O terminal não confirmou a troca de modelo.")
        }
        guard confirmed.lowercased().hasPrefix(model.rawValue) else {
            throw HerdrBridgeError.herdr(code: ClaudeScreen.selectorErrorCode, message: "O terminal trocou para \(confirmed).")
        }
    }

    public func setEffort(_ id: AgentID, level: EffortLevel) async throws {
        try ensureNotBlocked(id)
        try await ensureScreenFree(id, strict: true)
        try await command { client in
            _ = try await client.agentPrompt(target: id, text: "/effort")
        }
        guard let opened = try await pollScreen(id, { text in
            ClaudeScreen.effortPicker(text).map { (picker: $0, confirmations: ClaudeScreen.effortConfirmations(text).count) }
        }) else {
            throw await selectorFailure(id, "O seletor de effort não abriu no terminal.")
        }
        guard let target = opened.picker.levels.firstIndex(of: level.rawValue) else {
            throw await selectorFailure(id, "O effort \(level.rawValue) não está no seletor.")
        }
        let moves = ClaudeScreen.moves(from: opened.picker.cursor, to: target, back: "left", forward: "right")
        if !moves.isEmpty {
            try await sendKeys(id, moves)
            guard try await pollScreen(id, { ClaudeScreen.effortPicker($0)?.cursor == target ? true : nil }) != nil else {
                throw await selectorFailure(id, "O cursor do seletor de effort não chegou ao alvo.")
            }
        }
        try await sendKeys(id, [ClaudeScreen.confirmKey])
        guard let confirmed = try await pollScreen(id, { text -> String? in
            let confirmations = ClaudeScreen.effortConfirmations(text)
            guard !text.contains(ClaudeScreen.effortPickerMarker), confirmations.count > opened.confirmations else { return nil }
            return confirmations.last
        }) else {
            throw await selectorFailure(id, "O terminal não confirmou a troca de effort.")
        }
        guard confirmed == level.rawValue else {
            throw HerdrBridgeError.herdr(code: ClaudeScreen.selectorErrorCode, message: "O terminal trocou o effort para \(confirmed).")
        }
    }

    func ensureScreenFree(_ id: AgentID, strict: Bool) async throws {
        let screen: String
        do {
            screen = try await readScreen(id, lines: ClaudeScreen.busyScanLines)
        } catch let error where !strict && !(error is CancellationError) {
            herdrLogger.debug("skipped the screen check of \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        if ClaudeScreen.isBusy(screen) {
            throw HerdrBridgeError.screenBusy
        }
    }

    private func ensureNotBlocked(_ id: AgentID) throws {
        if agent(id)?.status == .blocked {
            throw HerdrBridgeError.agentBlocked
        }
    }

    private func readScreen(_ id: AgentID, lines: Int?) async throws -> String {
        try await command { client in
            try await client.paneRead(paneId: id, source: .visible, lines: lines).text
        }
    }

    private func sendKeys(_ id: AgentID, _ keys: [String]) async throws {
        try await command { client in
            try await client.agentSendKeys(target: id, keys: keys)
        }
    }

    private func waitForModeChange(_ id: AgentID, from current: String) async throws -> String {
        let timing = configuration.controls
        let deadline = ContinuousClock.now + timing.keyTimeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: timing.pollInterval)
            if let screen = try await pollRead(id, lines: 1), let mode = ClaudeScreen.mode(fromFooter: ClaudeScreen.lastLine(screen)), mode != current {
                return mode
            }
        }
        throw HerdrBridgeError.herdr(code: "timeout", message: "O rodapé do Claude não mudou depois do shift+tab.")
    }

    private func pollScreen<Value: Sendable>(_ id: AgentID, _ extract: @Sendable (String) -> Value?) async throws -> Value? {
        let timing = configuration.controls
        let deadline = ContinuousClock.now + timing.selectorTimeout
        while true {
            if let screen = try await pollRead(id, lines: nil), let value = extract(screen) {
                return value
            }
            guard ContinuousClock.now < deadline else { return nil }
            try await Task.sleep(for: timing.pollInterval)
        }
    }

    private func pollRead(_ id: AgentID, lines: Int?) async throws -> String? {
        do {
            return try await readScreen(id, lines: lines)
        } catch HerdrBridgeError.herdr(let code, _) where Self.transientReadCodes.contains(code) {
            return nil
        }
    }

    private static let transientReadCodes: Set<String> = ["closed", "timeout"]

    private func selectorFailure(_ id: AgentID, _ message: String) async -> HerdrBridgeError {
        if let screen = try? await readScreen(id, lines: ClaudeScreen.busyScanLines), ClaudeScreen.isBusy(screen) {
            try? await sendKeys(id, [ClaudeScreen.escapeKey])
        }
        return .herdr(code: ClaudeScreen.selectorErrorCode, message: message)
    }
}
