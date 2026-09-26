import Foundation

public enum HerdrSocketPath {
    public static func resolve(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if let override, !override.isEmpty {
            return override
        }
        if let path = environment["HERDR_SOCKET_PATH"], !path.isEmpty {
            return path
        }
        let herdrDirectory = homeDirectory.appending(path: ".config/herdr", directoryHint: .isDirectory)
        if let session = environment["HERDR_SESSION"], !session.isEmpty {
            return herdrDirectory
                .appending(path: "sessions", directoryHint: .isDirectory)
                .appending(path: session, directoryHint: .isDirectory)
                .appending(path: "herdr.sock")
                .path(percentEncoded: false)
        }
        return herdrDirectory.appending(path: "herdr.sock").path(percentEncoded: false)
    }
}
