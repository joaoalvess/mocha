import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct DaemonConfigStoreTests {
    static let existing = """
        {
          "apns": {"bundleId": "com.example.mocha", "keyId": "ABCDEFGHIJ", "teamId": "KLMNOPQRST"},
          "future": {"nested": [1, 2.5, "três", true, null], "flag": false},
          "gatewayPort": 47421,
          "note": "mantenha"
        }
        """

    @Test func preparingPreservesUnknownKeysAndAddsTheHookSecret() async throws {
        try await withTemporaryHome { home in
            try home.write(Self.existing, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let url = home.paths.configFile
            let before = try Self.object(url)

            let preparation = try DaemonConfigStore(url: url).prepareForDaemon()

            let after = try Self.object(url)
            #expect(preparation.generatedHookSecret)
            let secret = try #require(after["hookSecret"] as? String)
            #expect(preparation.config.hookSecret == secret)
            #expect(Data(base64Encoded: Self.base64(fromURLSafe: secret))?.count == 32)
            #expect(after["hookPort"] as? Int == 47420)
            #expect(after["gatewayPort"] as? Int == 47421)
            for key in ["apns", "future", "note"] {
                #expect(NSDictionary(dictionary: after).value(forKey: key) as? NSObject == NSDictionary(dictionary: before).value(forKey: key) as? NSObject)
            }
        }
    }

    @Test func writeIsAtomicAndAlwaysZeroSixHundred() async throws {
        try await withTemporaryHome { home in
            try home.write(Self.existing, to: "Library/Application Support/Mocha/config.json", permissions: 0o644)
            let url = home.paths.configFile
            let originalInode = try #require(inode(url))

            _ = try DaemonConfigStore(url: url).prepareForDaemon()

            #expect(fileMode(url) == 0o600)
            #expect(inode(url) != originalInode)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path(percentEncoded: false))
            #expect(leftovers == ["config.json"])
        }
    }

    @Test func existingSecretIsKeptAndNothingIsRewritten() async throws {
        try await withTemporaryHome { home in
            let store = DaemonConfigStore(url: home.paths.configFile)
            let first = try store.prepareForDaemon()
            let written = try #require(inode(home.paths.configFile))

            let second = try store.prepareForDaemon()

            #expect(!second.generatedHookSecret)
            #expect(second.config == first.config)
            #expect(inode(home.paths.configFile) == written)
            #expect(fileMode(home.paths.supportDirectory) == 0o700)
        }
    }

    @Test func readingNeverGeneratesTheSecret() async throws {
        try await withTemporaryHome { home in
            try home.write(#"{"apns":{"keyId":"ABCDEFGHIJ"}}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let before = try Data(contentsOf: home.paths.configFile)

            let config = try DaemonConfigStore(url: home.paths.configFile).read()

            #expect(config == DaemonConfig())
            #expect(try Data(contentsOf: home.paths.configFile) == before)
        }
    }

    @Test func invalidJSONIsNotOverwritten() async throws {
        try await withTemporaryHome { home in
            try home.write("{ quebrado", to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let url = home.paths.configFile
            #expect(throws: DaemonConfigError.invalidJSON(path: url.path(percentEncoded: false))) {
                try DaemonConfigStore(url: url).prepareForDaemon()
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == "{ quebrado")
        }
    }

    @Test func customGatewayPortIsRead() async throws {
        try await withTemporaryHome { home in
            try home.write(#"{"gatewayPort": 50000, "hookPort": 50001}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let config = try DaemonConfigStore(url: home.paths.configFile).read()
            #expect(config.gatewayPort == 50000)
            #expect(config.hookPort == 50001)
        }
    }

    private static func object(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private static func base64(fromURLSafe text: String) -> String {
        let standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)
    }
}
