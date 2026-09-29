import Foundation
import MochaHerdr
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct ClaudeScreenTests {
    @Test(arguments: [
        ("  ⏸ manual mode on · ? for shortcuts · ← for agents", "default"),
        ("  ⏵⏵ accept edits on (shift+tab to cycle) · ← for agents", "acceptEdits"),
        ("  ⏸ plan mode on (shift+tab to cycle) · ← for agents", "plan"),
        ("  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents              ◐ medium · /effort", "auto"),
    ])
    func footersMapToPermissionModesByPrefix(footer: String, mode: String) {
        #expect(ClaudeScreen.mode(fromFooter: footer) == mode)
    }

    @Test func unknownFootersHaveNoMode() {
        #expect(ClaudeScreen.mode(fromFooter: "  Enter to set as default · s to use this session only · Esc to cancel") == nil)
        #expect(ClaudeScreen.mode(fromFooter: "") == nil)
    }

    @Test func pickersAndTheSwitchDialogMakeTheScreenBusy() {
        #expect(!ClaudeScreen.isBusy(FakeClaudeScreen().text))
        #expect(ClaudeScreen.isBusy(FakeClaudeScreen(overlay: .modelPicker(cursor: 3)).text))
        #expect(ClaudeScreen.isBusy(FakeClaudeScreen(overlay: .effortPicker(cursor: 2)).text))
        #expect(ClaudeScreen.isBusy(FakeClaudeScreen(overlay: .switchDialog).text))
        #expect(!ClaudeScreen.isBusy(FakeClaudeScreen(history: ["❯ /model", "  Switch model?"]).text))
    }

    @Test func modelPickerRowsAndCursorComeFromTheS8Layout() throws {
        let picker = try #require(ClaudeScreen.modelPicker(FakeClaudeScreen(overlay: .modelPicker(cursor: 3), history: ["1. um item antigo"]).text))

        #expect(picker.rows == ["Default", "Opus", "Fable", "Sonnet", "Haiku"])
        #expect(picker.cursor == 3)
        #expect(ClaudeScreen.row(for: .haiku, in: picker) == 4)
        #expect(ClaudeScreen.row(for: .opus, in: picker) == 1)
        #expect(ClaudeScreen.row(for: .fable, in: picker) == 2)
    }

    @Test func effortPickerFindsTheMarkedLevel() throws {
        let picker = try #require(ClaudeScreen.effortPicker(FakeClaudeScreen(overlay: .effortPicker(cursor: 2)).text))

        #expect(picker.levels == EffortLevel.allCases.map(\.rawValue))
        #expect(picker.cursor == 2)
        #expect(ClaudeScreen.moves(from: 2, to: 1, back: "left", forward: "right") == ["left"])
        #expect(ClaudeScreen.moves(from: 2, to: 4, back: "left", forward: "right") == ["right", "right"])
        #expect(ClaudeScreen.moves(from: 2, to: 2, back: "left", forward: "right") == [])
    }

    @Test func confirmationsAreReadFromTheSessionOnlyLines() {
        let text = """
            ❯ /model
              ⎿  Set model to Haiku 4.5 for this session only
            ❯ /effort
              ⎿  Set effort level to medium (this session only)
              ⎿  Set model to Sonnet 5.5 and saved as your default for new sessions
            """
        #expect(ClaudeScreen.modelConfirmations(text) == ["Haiku 4.5"])
        #expect(ClaudeScreen.effortConfirmations(text) == ["medium"])
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct HerdrBridgeControlsTests {
    static let pane = "w1A:p2"

    static let controlsConfiguration = HerdrBridgeConfiguration(
        reconnectInterval: .milliseconds(50),
        snapshotDebounce: .milliseconds(10),
        treeDebounce: .milliseconds(10),
        paneUpdateProbeDelay: .milliseconds(40),
        agentDetectedProbeDelays: [.milliseconds(40), .milliseconds(160)],
        reconciliationInterval: .milliseconds(60),
        controls: ClaudeControlTiming(pollInterval: .milliseconds(15), keyTimeout: .milliseconds(500), selectorTimeout: .milliseconds(400))
    )

    static func withControls(_ screen: FakeClaudeScreen, latency: Duration = .milliseconds(25), _ body: (HerdrBridgeHarness) async throws -> Void) async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: controlsConfiguration)
        await harness.server.setScreen(paneId: pane, screen)
        await harness.server.setScreenLatency(latency)
        await harness.server.clearRequests()
        try await body(harness)
        try await harness.finish()
    }

    static func sentKeys(_ harness: HerdrBridgeHarness) async -> [[String]] {
        await harness.server.requests(method: "agent.send_keys").compactMap { $0.stringArrayParam("keys") }
    }

    static func prompts(_ harness: HerdrBridgeHarness) async -> [String] {
        await harness.server.requests(method: "agent.prompt").compactMap { $0.stringParam("text") }
    }

    @Test func modeAlreadyActiveSendsNoKey() async throws {
        try await Self.withControls(FakeClaudeScreen(mode: "plan")) { harness in
            let mode = try await harness.bridge.setMode(Self.pane, mode: .plan)
            #expect(mode == "plan")
            #expect(await Self.sentKeys(harness).isEmpty)
            let reads = await harness.server.requests(method: "pane.read")
            #expect(reads.allSatisfy { $0.stringParam("pane_id") == Self.pane && $0.stringParam("source") == "visible" })
        }
    }

    @Test(arguments: [
        ("default", PermissionModeTarget.acceptEdits, 1),
        ("default", .plan, 2),
        ("default", .auto, 3),
        ("auto", .default, 1),
        ("plan", .acceptEdits, 3),
    ])
    func modeLoopSendsOneShiftTabPerStepAndWaitsForTheFooter(start: String, target: PermissionModeTarget, keys: Int) async throws {
        try await Self.withControls(FakeClaudeScreen(mode: start)) { harness in
            let mode = try await harness.bridge.setMode(Self.pane, mode: target)
            #expect(mode == target.rawValue)
            #expect(await Self.sentKeys(harness) == Array(repeating: ["shift+tab"], count: keys))
            #expect(await harness.server.screen(paneId: Self.pane).mode == target.rawValue)
        }
    }

    @Test func autoOutsideTheHaikuCycleIsModeUnavailableAndStopsAtTheStart() async throws {
        try await Self.withControls(FakeClaudeScreen(modes: FakeClaudeScreen.haikuCycle, mode: "acceptEdits")) { harness in
            await expectHerdrBridgeError(.modeUnavailable) { _ = try await harness.bridge.setMode(Self.pane, mode: .auto) }
            #expect(await Self.sentKeys(harness).count == 3)
            #expect(await harness.server.screen(paneId: Self.pane).mode == "acceptEdits")
        }
    }

    @Test func busyScreenFailsBeforeAnyKey() async throws {
        for overlay in [FakeClaudeScreen.Overlay.modelPicker(cursor: 3), .effortPicker(cursor: 2), .switchDialog] {
            try await Self.withControls(FakeClaudeScreen(overlay: overlay)) { harness in
                await expectHerdrBridgeError(.screenBusy) { _ = try await harness.bridge.setMode(Self.pane, mode: .plan) }
                await expectHerdrBridgeError(.screenBusy) { try await harness.bridge.setModel(Self.pane, model: .haiku) }
                await expectHerdrBridgeError(.screenBusy) { try await harness.bridge.setEffort(Self.pane, level: .low) }
                await expectHerdrBridgeError(.screenBusy) { try await harness.bridge.prompt(Self.pane, text: "oi") }
                #expect(await Self.sentKeys(harness).isEmpty)
                #expect(await Self.prompts(harness).isEmpty)
            }
        }
    }

    @Test func footerThatNeverChangesTimesOut() async throws {
        var screen = FakeClaudeScreen()
        screen.cyclesMode = false
        try await Self.withControls(screen) { harness in
            await expectHerdrBridgeError(.herdr(code: "timeout", message: "O rodapé do Claude não mudou depois do shift+tab.")) {
                _ = try await harness.bridge.setMode(Self.pane, mode: .plan)
            }
            #expect(await Self.sentKeys(harness) == [["shift+tab"]])
        }
    }

    @Test func blockedAgentIsRejectedWithoutReadingTheScreen() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: Self.controlsConfiguration)
        await harness.server.setAgentStatus(paneId: Self.pane, status: "blocked")
        let event = try HerdrBridgeFixtures.eventLine("event.pane.agent_status_changed.json") { data in
            data["pane_id"] = Self.pane
            data["agent_status"] = "blocked"
        }
        await harness.server.emit(event)
        #expect(await HerdrWait.until { await harness.bridge.agent(Self.pane)?.status == .blocked })
        await harness.server.clearRequests()
        await expectHerdrBridgeError(.agentBlocked) { _ = try await harness.bridge.setMode(Self.pane, mode: .plan) }
        await expectHerdrBridgeError(.agentBlocked) { try await harness.bridge.setModel(Self.pane, model: .haiku) }
        await expectHerdrBridgeError(.agentBlocked) { try await harness.bridge.setEffort(Self.pane, level: .low) }
        #expect(await harness.server.requests(method: "pane.read").isEmpty)
        try await harness.finish()
    }

    @Test(arguments: [
        (ModelAlias.haiku, [["down"], ["s"]], "Haiku"),
        (.opus, [["up", "up"], ["s"]], "Opus"),
        (.fable, [["up"], ["s"]], "Fable"),
        (.sonnet, [["s"]], "Sonnet"),
    ])
    func modelPickerWalksToTheTargetAndConfirmsForTheSessionOnly(model: ModelAlias, keys: [[String]], row: String) async throws {
        try await Self.withControls(FakeClaudeScreen(model: "Sonnet")) { harness in
            try await harness.bridge.setModel(Self.pane, model: model)
            #expect(await Self.prompts(harness) == ["/model"])
            #expect(await Self.sentKeys(harness) == keys)
            let screen = await harness.server.screen(paneId: Self.pane)
            #expect(screen.model == row)
            #expect(screen.overlay == .none)
        }
    }

    @Test func modelPickerThatNeverOpensIsASelectorErrorWithoutKeys() async throws {
        var screen = FakeClaudeScreen()
        screen.opensPickers = false
        try await Self.withControls(screen) { harness in
            await expectHerdrBridgeError(.herdr(code: "selector", message: "O seletor de modelo não abriu no terminal.")) {
                try await harness.bridge.setModel(Self.pane, model: .haiku)
            }
            #expect(await Self.sentKeys(harness).isEmpty)
        }
    }

    @Test func missingConfirmationClosesThePickerWithEscape() async throws {
        var screen = FakeClaudeScreen()
        screen.confirmsPickers = false
        try await Self.withControls(screen) { harness in
            await expectHerdrBridgeError(.herdr(code: "selector", message: "O terminal não confirmou a troca de modelo.")) {
                try await harness.bridge.setModel(Self.pane, model: .haiku)
            }
            #expect(await Self.sentKeys(harness) == [["down"], ["s"], ["Escape"]])
            #expect(await HerdrWait.until { await harness.server.screen(paneId: Self.pane).overlay == .none })
        }
    }

    @Test func stuckCursorClosesThePickerWithEscape() async throws {
        var screen = FakeClaudeScreen()
        screen.movesCursor = false
        try await Self.withControls(screen) { harness in
            await expectHerdrBridgeError(.herdr(code: "selector", message: "O cursor do seletor de effort não chegou ao alvo.")) {
                try await harness.bridge.setEffort(Self.pane, level: .low)
            }
            #expect(await Self.sentKeys(harness) == [["left", "left"], ["Escape"]])
        }
    }

    @Test(arguments: [
        (EffortLevel.medium, [["left"], ["s"]]),
        (.low, [["left", "left"], ["s"]]),
        (.max, [["right", "right"], ["s"]]),
        (.high, [["s"]]),
    ])
    func effortPickerWalksToTheTargetAndConfirmsForTheSessionOnly(level: EffortLevel, keys: [[String]]) async throws {
        try await Self.withControls(FakeClaudeScreen(effort: "high")) { harness in
            try await harness.bridge.setEffort(Self.pane, level: level)
            #expect(await Self.prompts(harness) == ["/effort"])
            #expect(await Self.sentKeys(harness) == keys)
            #expect(await harness.server.screen(paneId: Self.pane).effort == level.rawValue)
        }
    }

    @Test func currentModeReadsTheFooter() async throws {
        try await Self.withControls(FakeClaudeScreen(mode: "acceptEdits")) { harness in
            #expect(await harness.bridge.currentMode(Self.pane) == "acceptEdits")
            await harness.server.setScreen(paneId: Self.pane, FakeClaudeScreen(overlay: .effortPicker(cursor: 1)))
            #expect(await harness.bridge.currentMode(Self.pane) == nil)
        }
    }

    @Test func promptStillWorksWhenThePaneCannotBeRead() async throws {
        try await Self.withControls(FakeClaudeScreen()) { harness in
            await harness.server.override("pane.read", with: .error(code: "pane_not_found", message: "pane w1A:p2 not found"))
            try await harness.bridge.prompt(Self.pane, text: "oi")
            #expect(await Self.prompts(harness) == ["oi"])
            await harness.server.override("pane.read", with: nil)
        }
    }
}
