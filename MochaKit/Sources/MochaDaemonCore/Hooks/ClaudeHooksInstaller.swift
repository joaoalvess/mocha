import Foundation

public enum ClaudeHooksInstallerError: Error, Sendable, Equatable {
    case invalidSettings(path: String)
    case unexpectedShape(path: String, key: String)
    case unsafeHookSecret
}

public struct ClaudeHooksReport: Sendable, Equatable {
    public var settingsFile: URL
    public var changed: Bool
    public var events: [String]
    public var backup: URL?
    public var generatedHookSecret: Bool
    public var moshiEvents: [String]
}

public struct ClaudeHooksInstaller: Sendable {
    public static let backupSuffix = ".mocha-bak"

    public let settingsFile: URL
    public let configFile: URL

    public init(settingsFile: URL, configFile: URL) {
        self.settingsFile = settingsFile
        self.configFile = configFile
    }

    public init(paths: DaemonPaths) {
        self.init(settingsFile: paths.claudeSettingsFile, configFile: paths.configFile)
    }

    public var backupFile: URL {
        settingsFile.deletingLastPathComponent()
            .appending(path: settingsFile.lastPathComponent + Self.backupSuffix, directoryHint: .notDirectory)
    }

    public func install() throws -> ClaudeHooksReport {
        let preparation = try DaemonConfigStore(url: configFile).prepareForDaemon()
        guard let secret = preparation.config.hookSecret, ClaudeHookEntries.isSafeSecret(secret) else {
            throw ClaudeHooksInstallerError.unsafeHookSecret
        }
        let port = preparation.config.hookPort
        var report = try update { try ClaudeHooksMerge.install(into: $0, port: port, secret: secret) }
        report.generatedHookSecret = preparation.generatedHookSecret
        return report
    }

    public func uninstall() throws -> ClaudeHooksReport {
        let port = try DaemonConfigStore(url: configFile).read().hookPort
        return try update { try ClaudeHooksMerge.uninstall(from: $0, port: port) }
    }

    private func update(_ transform: (OrderedJSON) throws -> ClaudeHooksMerge.Outcome) throws -> ClaudeHooksReport {
        let path = settingsFile.fileSystemPath
        let original = try readOriginal()
        let current: OrderedJSON
        do {
            current = try Self.document(from: original)
        } catch {
            throw ClaudeHooksInstallerError.invalidSettings(path: path)
        }
        let outcome: ClaudeHooksMerge.Outcome
        do {
            outcome = try transform(current)
        } catch ClaudeHooksMergeError.unexpectedShape(let key) {
            throw ClaudeHooksInstallerError.unexpectedShape(path: path, key: key)
        } catch {
            throw ClaudeHooksInstallerError.invalidSettings(path: path)
        }
        var report = ClaudeHooksReport(
            settingsFile: settingsFile,
            changed: false,
            events: outcome.touchedEvents,
            backup: nil,
            generatedHookSecret: false,
            moshiEvents: []
        )
        if outcome.settings != current {
            report.backup = try write(outcome.settings, replacing: original)
            report.changed = true
        } else if original != nil {
            try Self.restrict(settingsFile.resolvingSymlinksInPath())
            try restrictBackup()
        }
        if case .hooks(let summary) = ClaudeSettingsInspector(url: settingsFile).inspect() {
            report.moshiEvents = summary.moshiEvents
        }
        return report
    }

    private func readOriginal() throws -> Data? {
        guard FileManager.default.fileExists(atPath: settingsFile.fileSystemPath) else { return nil }
        return try Data(contentsOf: settingsFile)
    }

    private func write(_ settings: OrderedJSON, replacing original: Data?) throws -> URL? {
        let target = settingsFile.resolvingSymlinksInPath()
        var backup: URL?
        if let original, !FileManager.default.fileExists(atPath: backupFile.fileSystemPath) {
            try AtomicFile.write(original, to: backupFile, permissions: Self.permissions)
            backup = backupFile
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = settings.prettyPrinted()
        if original.map(Self.endsWithNewline) ?? true {
            text += "\n"
        }
        try AtomicFile.write(Data(text.utf8), to: target, permissions: Self.permissions)
        try restrictBackup()
        return backup
    }

    private static func document(from data: Data?) throws -> OrderedJSON {
        guard let data, data.contains(where: { !Self.isWhitespace($0) }) else { return .object([]) }
        return try OrderedJSON.parse(data)
    }

    private static func endsWithNewline(_ data: Data) -> Bool {
        data.last == UInt8(ascii: "\n")
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static let permissions: mode_t = 0o600

    private func restrictBackup() throws {
        guard FileManager.default.fileExists(atPath: backupFile.fileSystemPath) else { return }
        try Self.restrict(backupFile)
    }

    private static func restrict(_ url: URL) throws {
        guard chmod(url.fileSystemPath, permissions) == 0 else {
            throw AtomicFileError.writeFailed(path: url.fileSystemPath, errno: errno)
        }
    }
}
