import Foundation
import Testing
@testable import MochaDaemonCore

enum SettingsSamples {
    static let settingsPath = ".claude/settings.json"
    static let configPath = "Library/Application Support/Mocha/config.json"

    static let herdrOnly = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "^(startup|resume|clear|compact|fork)$",
                "hooks": [
                  {
                    "type": "command",
                    "command": "bash '/Users/dev/.claude/hooks/herdr-agent-state.sh' session",
                    "timeout": 10
                  }
                ]
              }
            ]
          }
        }

        """

    static let thirdParty = """
        {
          "$schema": "https://json.schemastore.org/claude-code-settings.json",
          "model": "opus",
          "env": {
            "CLAUDE_CODE_NO_FLICKER": "1"
          },
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "bash ~/.claude/hooks/lint.sh"
                  }
                ]
              },
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/opt/homebrew/bin/moshi-hook pre-tool-use"
                  }
                ]
              }
            ],
            "SessionStart": [
              {
                "matcher": "^(startup|resume|clear|compact|fork)$",
                "hooks": [
                  {
                    "type": "command",
                    "command": "bash '/Users/dev/.claude/hooks/herdr-agent-state.sh' session",
                    "timeout": 10
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/opt/homebrew/bin/moshi-hook stop"
                  }
                ]
              }
            ],
            "PermissionRequest": [
              {
                "hooks": [
                  {
                    "type": "http",
                    "url": "http://127.0.0.1:8765/moshi/permission",
                    "timeout": 600
                  }
                ]
              }
            ]
          },
          "statusLine": {
            "type": "command",
            "command": "~/.claude/statusline.sh"
          }
        }

        """

    static func proposed(port: UInt16 = 47420, secret: String = "test-secret") throws -> String {
        String(decoding: try Fixtures.data("hooks/settings.install-hooks.proposed.json"), as: UTF8.self)
            .replacingOccurrences(of: "127.0.0.1:47420", with: "127.0.0.1:\(port)")
            .replacingOccurrences(of: "test-secret", with: secret)
    }

    static func config(secret: String = "test-secret", port: UInt16? = nil) -> String {
        port.map { #"{"hookPort": \#($0), "hookSecret": "\#(secret)"}"# } ?? #"{"hookSecret": "\#(secret)"}"#
    }
}

@Suite
struct ClaudeHooksInstallerTests {
    static func settings(_ home: TemporaryHome) throws -> String {
        String(decoding: try Data(contentsOf: home.paths.claudeSettingsFile), as: UTF8.self)
    }

    static func json(_ text: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Data(text.utf8))
    }

    @Test func mergeOverOnlyTheHerdrHookIsTheProposedBlock() async throws {
        try await withTemporaryHome { home in
            try home.write(SettingsSamples.config(), to: SettingsSamples.configPath, permissions: 0o600)
            try home.write(SettingsSamples.herdrOnly, to: SettingsSamples.settingsPath)
            let installer = ClaudeHooksInstaller(paths: home.paths)

            let report = try installer.install()

            #expect(try Self.settings(home) == SettingsSamples.proposed())
            #expect(report.changed)
            #expect(report.events == ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "PermissionRequest"])
            #expect(report.backup == installer.backupFile)
            #expect(report.generatedHookSecret == false)
            #expect(report.moshiEvents.isEmpty)
            #expect(String(decoding: try Data(contentsOf: installer.backupFile), as: UTF8.self) == SettingsSamples.herdrOnly)
            #expect(installer.backupFile.lastPathComponent == "settings.json.mocha-bak")
            #expect(ClaudeSettingsInspector(url: home.paths.claudeSettingsFile).inspect() == .hooks(ClaudeHooksSummary(
                mochaEvents: ["Notification", "PermissionRequest", "SessionStart", "Stop", "UserPromptSubmit"]
            )))
        }
    }

    @Test func portAndSecretComeFromTheConfig() async throws {
        try await withTemporaryHome { home in
            try home.write(SettingsSamples.config(secret: "Zx_9-kQ", port: 47490), to: SettingsSamples.configPath, permissions: 0o600)
            try home.write(SettingsSamples.herdrOnly, to: SettingsSamples.settingsPath)

            _ = try ClaudeHooksInstaller(paths: home.paths).install()

            #expect(try Self.settings(home) == SettingsSamples.proposed(port: 47490, secret: "Zx_9-kQ"))
        }
    }

    @Test func secondInstallChangesNothingAndKeepsTheFirstBackup() async throws {
        try await withTemporaryHome { home in
            try home.write(SettingsSamples.config(), to: SettingsSamples.configPath, permissions: 0o600)
            try home.write(SettingsSamples.thirdParty, to: SettingsSamples.settingsPath)
            let installer = ClaudeHooksInstaller(paths: home.paths)
            _ = try installer.install()
            let first = try Self.settings(home)
            let firstInode = inode(home.paths.claudeSettingsFile)

            let second = try installer.install()

            #expect(second.changed == false)
            #expect(second.backup == nil)
            #expect(try Self.settings(home) == first)
            #expect(inode(home.paths.claudeSettingsFile) == firstInode)
            #expect(String(decoding: try Data(contentsOf: installer.backupFile), as: UTF8.self) == SettingsSamples.thirdParty)
        }
    }

    @Test func installKeepsThirdPartyHooksAndUninstallRestoresTheOriginal() async throws {
        try await withTemporaryHome { home in
            try home.write(SettingsSamples.config(), to: SettingsSamples.configPath, permissions: 0o600)
            try home.write(SettingsSamples.thirdParty, to: SettingsSamples.settingsPath)
            let installer = ClaudeHooksInstaller(paths: home.paths)

            let installed = try installer.install()
            let settings = try Self.json(Self.settings(home))

            #expect(installed.moshiEvents == ["PreToolUse", "Stop"])
            #expect(settings.members?.map(\.key) == ["$schema", "model", "env", "hooks", "statusLine"])
            #expect(settings["hooks"]?.members?.map(\.key) == ["PreToolUse", "SessionStart", "Stop", "PermissionRequest", "UserPromptSubmit", "Notification"])
            #expect(settings["hooks"]?["PreToolUse"] == (try Self.json(SettingsSamples.thirdParty))["hooks"]?["PreToolUse"])
            let stop = try #require(settings["hooks"]?["Stop"]?.arrayValue)
            #expect(stop.count == 2)
            #expect(stop[0]["hooks"]?.arrayValue?[0]["command"] == .string("/opt/homebrew/bin/moshi-hook stop"))
            #expect(stop[1] == ClaudeHookEntries.group(for: .stop, port: 47420, secret: "test-secret"))
            let permission = try #require(settings["hooks"]?["PermissionRequest"]?.arrayValue)
            #expect(permission.map { $0["hooks"]?.arrayValue?[0]["url"]?.stringValue } == [
                "http://127.0.0.1:8765/moshi/permission",
                "http://127.0.0.1:47420/hooks/PermissionRequest",
            ])

            let removed = try installer.uninstall()

            #expect(removed.changed)
            #expect(removed.backup == nil)
            #expect(removed.events == ["SessionStart", "Stop", "PermissionRequest", "UserPromptSubmit", "Notification"])
            #expect(try Self.settings(home) == SettingsSamples.thirdParty)
        }
    }

    @Test func staleMochaEntriesAreReplacedInPlace() throws {
        let stale = ClaudeHookEntries.hook(for: .stop, port: 47420, secret: "velho")
        let moshi = OrderedJSON.object([OrderedJSON.Member("hooks", .array([.object([
            OrderedJSON.Member("type", .string("command")),
            OrderedJSON.Member("command", .string("moshi-hook stop")),
        ])]))])
        let lint = OrderedJSON.object([OrderedJSON.Member("type", .string("command")), OrderedJSON.Member("command", .string("lint.sh"))])
        let settings = OrderedJSON.object([OrderedJSON.Member("hooks", .object([
            OrderedJSON.Member("Stop", .array([
                moshi,
                .object([OrderedJSON.Member("hooks", .array([stale]))]),
                .object([OrderedJSON.Member("matcher", .string("x")), OrderedJSON.Member("hooks", .array([lint, stale]))]),
            ])),
            OrderedJSON.Member("PreToolUse", .array([.object([OrderedJSON.Member("hooks", .array([
                .object([OrderedJSON.Member("type", .string("http")), OrderedJSON.Member("url", .string("http://127.0.0.1:47420/hooks/PreToolUse"))]),
            ]))])])),
        ]))])

        let installed = try ClaudeHooksMerge.install(into: settings, port: 47420, secret: "novo").settings

        #expect(installed["hooks"]?.members?.map(\.key) == ["Stop", "SessionStart", "UserPromptSubmit", "Notification", "PermissionRequest"])
        #expect(installed["hooks"]?["Stop"] == .array([
            moshi,
            ClaudeHookEntries.group(for: .stop, port: 47420, secret: "novo"),
            .object([OrderedJSON.Member("matcher", .string("x")), OrderedJSON.Member("hooks", .array([lint]))]),
        ]))
    }

    @Test func uninstallRecognizesTheDefaultAndTheConfiguredPort() throws {
        let settings = try ClaudeHooksMerge.install(into: .object([]), port: 47420, secret: "s").settings
        let moved = try ClaudeHooksMerge.install(into: .object([]), port: 47490, secret: "s").settings

        #expect(try ClaudeHooksMerge.uninstall(from: settings, port: 47490).settings == .object([]))
        #expect(try ClaudeHooksMerge.uninstall(from: moved, port: 47490).settings == .object([]))
        #expect(try ClaudeHooksMerge.uninstall(from: moved, port: 47420).settings == moved)
    }

    @Test func uninstallWithoutMochaEntriesDoesNotWrite() async throws {
        try await withTemporaryHome { home in
            try home.write(SettingsSamples.thirdParty, to: SettingsSamples.settingsPath)
            let installer = ClaudeHooksInstaller(paths: home.paths)
            let originalInode = inode(home.paths.claudeSettingsFile)

            let report = try installer.uninstall()

            #expect(report.changed == false)
            #expect(report.events.isEmpty)
            #expect(report.moshiEvents == ["PreToolUse", "Stop"])
            #expect(inode(home.paths.claudeSettingsFile) == originalInode)
            #expect(FileManager.default.fileExists(atPath: installer.backupFile.path(percentEncoded: false)) == false)
        }
    }

    @Test func missingSettingsAreCreatedPrivateWithAGeneratedSecret() async throws {
        try await withTemporaryHome { home in
            let installer = ClaudeHooksInstaller(paths: home.paths)

            let report = try installer.install()

            let config = try DaemonConfigStore(url: home.paths.configFile).read()
            let secret = try #require(config.hookSecret)
            #expect(report.generatedHookSecret)
            #expect(report.backup == nil)
            #expect(fileMode(home.paths.claudeSettingsFile) == 0o600)
            #expect(fileMode(home.paths.configFile) == 0o600)
            let expected = try ClaudeHooksMerge.install(into: .object([]), port: 47420, secret: secret).settings
            #expect(try Self.settings(home) == expected.prettyPrinted() + "\n")

            let removed = try installer.uninstall()

            #expect(removed.changed)
            #expect(try Self.settings(home) == "{}\n")
        }
    }

    @Test func permissionsTrailingNewlineAndSymlinkArePreserved() async throws {
        try await withTemporaryHome { home in
            try home.write(SettingsSamples.config(), to: SettingsSamples.configPath, permissions: 0o600)
            try home.write(#"{"model": "opus"}"#, to: "dotfiles/claude-settings.json", permissions: 0o640)
            try FileManager.default.createDirectory(at: home.url.appending(path: ".claude"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: home.paths.claudeSettingsFile,
                withDestinationURL: home.url.appending(path: "dotfiles/claude-settings.json")
            )

            _ = try ClaudeHooksInstaller(paths: home.paths).install()

            let link = try FileManager.default.destinationOfSymbolicLink(atPath: home.paths.claudeSettingsFile.path(percentEncoded: false))
            #expect(link.hasSuffix("dotfiles/claude-settings.json"))
            let target = home.url.appending(path: "dotfiles/claude-settings.json")
            #expect(fileMode(target) == 0o640)
            let text = String(decoding: try Data(contentsOf: target), as: UTF8.self)
            #expect(text.hasSuffix("}"))
            #expect(try Self.json(text)["model"] == .string("opus"))
            #expect(try Self.json(text)["hooks"]?.members?.count == 5)
        }
    }

    @Test func invalidSettingsAreLeftUntouched() async throws {
        let cases: [(String, ClaudeHooksInstallerError)] = [
            ("{ não é json", .invalidSettings(path: "")),
            ("[1, 2]", .invalidSettings(path: "")),
            (#"{"hooks": []}"#, .unexpectedShape(path: "", key: "hooks")),
            (#"{"hooks": {"Stop": {"type": "command"}}}"#, .unexpectedShape(path: "", key: "hooks.Stop")),
        ]
        for (text, error) in cases {
            try await withTemporaryHome { home in
                try home.write(SettingsSamples.config(), to: SettingsSamples.configPath, permissions: 0o600)
                try home.write(text, to: SettingsSamples.settingsPath)
                let installer = ClaudeHooksInstaller(paths: home.paths)
                let path = home.paths.claudeSettingsFile.path(percentEncoded: false)
                let expected: ClaudeHooksInstallerError = switch error {
                case .invalidSettings: .invalidSettings(path: path)
                case .unexpectedShape(_, let key): .unexpectedShape(path: path, key: key)
                case .unsafeHookSecret: .unsafeHookSecret
                }

                #expect(throws: expected) {
                    try installer.install()
                }
                #expect(try Self.settings(home) == text)
                #expect(FileManager.default.fileExists(atPath: installer.backupFile.path(percentEncoded: false)) == false)
            }
        }
    }

    @Test func secretThatWouldBreakTheCommandIsRefused() async throws {
        try await withTemporaryHome { home in
            try home.write(#"{"hookSecret": "abc' ; rm -rf ~ ; '"}"#, to: SettingsSamples.configPath, permissions: 0o600)
            try home.write(SettingsSamples.herdrOnly, to: SettingsSamples.settingsPath)

            #expect(throws: ClaudeHooksInstallerError.unsafeHookSecret) {
                try ClaudeHooksInstaller(paths: home.paths).install()
            }
            #expect(try Self.settings(home) == SettingsSamples.herdrOnly)
        }
    }
}
