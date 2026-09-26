import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct ClaudeSettingsInspectorTests {
    static let moshiSettings = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "/opt/homebrew/bin/moshi-hook stop"}]}],
            "PreToolUse": [
              {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/lint.sh"}]},
              {"hooks": [{"type": "command", "command": "/opt/homebrew/bin/moshi-hook pre-tool-use"}]}
            ],
            "Notification": [{"hooks": [{"type": "http", "url": "http://127.0.0.1:47420/hooks/Notification"}, {"type": "command", "command": "moshi-hook notify"}]}],
            "SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/herdr-agent-state.sh session"}]}]
          }
        }
        """

    @Test func proposedInstallHooksSettingsShowTheMochaEntriesAndNoMoshi() {
        let inspection = ClaudeSettingsInspector(url: Fixtures.url("hooks/settings.install-hooks.proposed.json")).inspect()

        #expect(inspection == .hooks(ClaudeHooksSummary(
            mochaEvents: ["Notification", "PermissionRequest", "SessionStart", "Stop", "UserPromptSubmit"],
            moshiEvents: []
        )))
        let hooks = DoctorChecks.hooks(inspection)
        #expect(hooks.status == .warning)
        #expect(hooks.summary.hasPrefix("chegam na 1a-final"))
        #expect(DoctorChecks.moshiHook(inspection) == DoctorItem("moshi-hook", .ok, "ausente"))
    }

    @Test func moshiHookIsDetectedWithoutTouchingTheFile() async throws {
        try await withTemporaryHome { home in
            try home.write(Self.moshiSettings, to: ".claude/settings.json", permissions: 0o600)
            let url = home.paths.claudeSettingsFile
            let before = try Data(contentsOf: url)
            let originalInode = inode(url)

            let inspection = ClaudeSettingsInspector(url: url).inspect()

            #expect(inspection == .hooks(ClaudeHooksSummary(mochaEvents: ["Notification"], moshiEvents: ["Notification", "PreToolUse", "Stop"])))
            let moshi = DoctorChecks.moshiHook(inspection)
            #expect(moshi.status == .warning)
            #expect(moshi.summary == "instalado em Notification, PreToolUse, Stop")
            #expect(moshi.details == ["antes da 1b: moshi-hook uninstall e depois brew services stop moshi-hook"])
            #expect(try Data(contentsOf: url) == before)
            #expect(fileMode(url) == 0o600)
            #expect(inode(url) == originalInode)
        }
    }

    @Test func missingAndUnreadableSettings() async throws {
        try await withTemporaryHome { home in
            let url = home.paths.claudeSettingsFile
            #expect(ClaudeSettingsInspector(url: url).inspect() == .missing)
            #expect(DoctorChecks.moshiHook(.missing).status == .ok)
            #expect(DoctorChecks.hooks(.missing) == DoctorItem("Hooks", .warning, "chegam na 1a-final (mochad install-hooks)"))

            try home.write("{ não é json", to: ".claude/settings.json")
            #expect(ClaudeSettingsInspector(url: url).inspect() == .unreadable)
            #expect(DoctorChecks.moshiHook(.unreadable).status == .warning)
        }
    }
}
