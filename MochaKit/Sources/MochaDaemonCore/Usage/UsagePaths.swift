import Foundation

extension DaemonPaths {
    public var usageCacheFile: URL {
        home.appending(path: ".local/state/herdr/plugins/herdr-agent-usage/claude-statusline.json", directoryHint: .notDirectory)
    }

    public var claudeAccountFile: URL {
        home.appending(path: ".claude.json", directoryHint: .notDirectory)
    }
}
