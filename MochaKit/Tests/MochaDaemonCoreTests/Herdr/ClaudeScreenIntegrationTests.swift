import Foundation
import MochaHerdr
import MochaProtocol
import Testing
@testable import MochaDaemonCore

enum ClaudeLabPane {
    static var id: String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MOCHA_INTEGRATION"] == "1" else { return nil }
        return environment["MOCHA_CLAUDE_LAB_PANE"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

@Suite(.tags(.integration), .enabled(if: ClaudeLabPane.id != nil), .serialized, .timeLimit(.minutes(1)))
struct ClaudeScreenIntegrationTests {
    let pane = ClaudeLabPane.id ?? ""
    let client = HerdrClient(configuration: HerdrClientConfiguration(socketPath: HerdrSocketPath.resolve()))

    @Test func footerShowsAKnownPermissionMode() async throws {
        let screen = try await read()
        #expect(ClaudeScreen.mode(fromFooter: ClaudeScreen.lastLine(screen)) != nil, "rodapé real:\n\(screen)")
        #expect(!ClaudeScreen.isBusy(screen), "tela real:\n\(screen)")
    }

    @Test func effortPickerCursorFollowsTheArrowKeys() async throws {
        let picker = try await open("/effort", ClaudeScreen.effortPicker)
        guard let parsed = picker.value else {
            try await close()
            Issue.record("seletor de effort real:\n\(picker.screen)")
            return
        }
        let forward = parsed.cursor < parsed.levels.count - 1
        try await client.agentSendKeys(target: pane, keys: [forward ? "right" : "left"])
        let target = parsed.cursor + (forward ? 1 : -1)
        let moved = try await poll { ClaudeScreen.effortPicker($0)?.cursor == target ? true : nil }
        try await close()
        #expect(parsed.levels == EffortLevel.allCases.map(\.rawValue), "seletor de effort real:\n\(picker.screen)")
        #expect(moved.value == true, "cursor esperado em \(target), seletor real:\n\(moved.screen)")
        #expect(ClaudeScreen.isBusy(picker.screen), "seletor de effort real:\n\(picker.screen)")
    }

    @Test func modelPickerListsEveryAlias() async throws {
        let picker = try await open("/model", ClaudeScreen.modelPicker)
        try await close()
        let parsed = try #require(picker.value, "seletor de modelo real:\n\(picker.screen)")
        for alias in ModelAlias.allCases {
            #expect(ClaudeScreen.row(for: alias, in: parsed) != nil, "\(alias.rawValue) no seletor real:\n\(picker.screen)")
        }
        #expect(ClaudeScreen.isBusy(picker.screen), "seletor de modelo real:\n\(picker.screen)")
    }

    private func read() async throws -> String {
        try await client.paneRead(paneId: pane, source: .visible).text
    }

    private func open<Value>(_ command: String, _ parse: (String) -> Value?) async throws -> (value: Value?, screen: String) {
        _ = try await client.agentPrompt(target: pane, text: command)
        return try await poll(parse)
    }

    private func poll<Value>(_ parse: (String) -> Value?) async throws -> (value: Value?, screen: String) {
        var screen = ""
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            screen = try await read()
            if let value = parse(screen) {
                return (value, screen)
            }
        }
        return (nil, screen)
    }

    private func close() async throws {
        try await client.agentSendKeys(target: pane, keys: [ClaudeScreen.escapeKey])
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            let screen = try await read()
            if ClaudeScreen.mode(fromFooter: ClaudeScreen.lastLine(screen)) != nil {
                _ = try await client.agentWait(target: pane, until: [.idle, .done], timeout: .seconds(5))
                return
            }
        }
        Issue.record("o seletor não fechou com Esc")
    }
}
