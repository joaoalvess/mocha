import Foundation
import Testing
@testable import MochaDaemonCore

enum HooksIntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCHA_INTEGRATION"] == "1"
    }
}

@Suite(.tags(.integration), .enabled(if: HooksIntegrationGate.isEnabled))
struct ClaudeHooksRealSettingsTests {
    @Test func mergeOverACopyOfTheRealSettingsKeepsThirdPartyHooksAndUninstallRemovesOnlyMocha() async throws {
        let real = DaemonPaths().claudeSettingsFile
        guard FileManager.default.fileExists(atPath: real.path(percentEncoded: false)) else {
            Issue.record("sem ~/.claude/settings.json para copiar")
            return
        }
        let original = try Data(contentsOf: real)
        try await withTemporaryHome { home in
            try FileManager.default.createDirectory(at: home.paths.claudeSettingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: home.paths.claudeSettingsFile)
            try home.write(SettingsSamples.config(secret: SecureToken.generate()), to: SettingsSamples.configPath, permissions: 0o600)
            let installer = ClaudeHooksInstaller(paths: home.paths)
            let copy = home.paths.claudeSettingsFile
            let before = try OrderedJSON.parse(original)
            let withoutMochaBefore = try ClaudeHooksMerge.uninstall(from: before, port: DaemonConfig.defaultHookPort)
            let hadMochaEntries = !withoutMochaBefore.touchedEvents.isEmpty

            let installed = try installer.install()
            let afterInstall = try Data(contentsOf: copy)

            let installedEverywhere = ClaudeSettingsInspector(url: copy).inspect() == .hooks(ClaudeHooksSummary(
                mochaEvents: HookEventName.allCases.map(\.rawValue).sorted(),
                moshiEvents: installed.moshiEvents
            ))
            #expect(installedEverywhere)
            let thirdPartyPreserved = try ClaudeHooksMerge.uninstall(from: OrderedJSON.parse(afterInstall), port: DaemonConfig.defaultHookPort).settings
                == withoutMochaBefore.settings
            #expect(thirdPartyPreserved)
            let backupIsTheOriginal = try Data(contentsOf: installer.backupFile) == original
            #expect(backupIsTheOriginal)

            let second = try installer.install()
            let idempotent = try second.changed == false && Data(contentsOf: copy) == afterInstall
            #expect(idempotent)

            let removed = try installer.uninstall()
            let afterUninstall = try Data(contentsOf: copy)

            #expect(removed.changed)
            let onlyMochaRemoved = try OrderedJSON.parse(afterUninstall) == withoutMochaBefore.settings
            #expect(onlyMochaRemoved)
            let canonical = Data((before.prettyPrinted() + (original.last == UInt8(ascii: "\n") ? "\n" : "")).utf8) == original
            if canonical && !hadMochaEntries {
                let restoredByteForByte = afterUninstall == original
                #expect(restoredByteForByte)
            }
            let realUntouched = try Data(contentsOf: real) == original
            #expect(realUntouched)
            print("settings.json real: formato canônico \(canonical), entradas do Mocha antes \(hadMochaEntries), moshi-hook em \(installed.moshiEvents.count) eventos")
        }
    }
}
