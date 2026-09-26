import Foundation

public struct DaemonPaths: Sendable, Equatable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var supportDirectory: URL {
        home.appending(path: "Library/Application Support/Mocha", directoryHint: .isDirectory)
    }

    public var configFile: URL {
        supportDirectory.appending(path: "config.json", directoryHint: .notDirectory)
    }

    public var devicesFile: URL {
        supportDirectory.appending(path: "devices.json", directoryHint: .notDirectory)
    }

    public var sessionsFile: URL {
        supportDirectory.appending(path: "sessions.json", directoryHint: .notDirectory)
    }

    public var controlSocket: URL {
        supportDirectory.appending(path: "mochad.sock", directoryHint: .notDirectory)
    }

    public var uploadsDirectory: URL {
        supportDirectory.appending(path: "uploads", directoryHint: .isDirectory)
    }

    public var logsDirectory: URL {
        home.appending(path: "Library/Logs/Mocha", directoryHint: .isDirectory)
    }

    public var logFile: URL {
        logsDirectory.appending(path: "mochad.log", directoryHint: .notDirectory)
    }

    public var launchAgentFile: URL {
        home.appending(path: "Library/LaunchAgents/\(LaunchAgent.label).plist", directoryHint: .notDirectory)
    }

    public var installedBinary: URL {
        home.appending(path: ".local/bin/mochad", directoryHint: .notDirectory)
    }

    public var claudeSettingsFile: URL {
        home.appending(path: ".claude/settings.json", directoryHint: .notDirectory)
    }

    public func display(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        let homePath = home.path(percentEncoded: false)
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        guard path.hasPrefix(prefix) else { return path }
        return "~/" + path.dropFirst(prefix.count)
    }

    func createSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}
