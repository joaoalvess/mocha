import CryptoKit
import Foundation
import Testing
@testable import MochaDaemonCore

struct ApnsKeyImporterTests {
    @Test func importStoresKeyAndWritesConfigWithPrivatePermissions() throws {
        let directory = try PushTestData.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyFile = directory.appending(path: "AuthKey_TEST.p8")
        let pem = P256.Signing.PrivateKey().pemRepresentation
        try Data(pem.utf8).write(to: keyFile)
        let configURL = directory.appending(path: "Mocha/config.json")
        let store = InMemoryApnsKeyStore()
        let importer = ApnsKeyImporter(keyStore: store, configStore: ApnsConfigStore(url: configURL))

        let config = try importer.importKey(fileURL: keyFile, keyId: PushTestData.keyId, teamId: PushTestData.teamId)

        #expect(config == ApnsConfig(teamId: PushTestData.teamId, keyId: PushTestData.keyId, bundleId: "com.example.mocha"))
        #expect(try store.load(keyId: PushTestData.keyId) == pem)
        let attributes = try FileManager.default.attributesOfItem(atPath: configURL.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let configText = try String(contentsOf: configURL, encoding: .utf8)
        #expect(configText.contains("PRIVATE KEY") == false)
        let loaded = try importer.loadSigningKey()
        #expect(loaded.config == config)
        #expect(loaded.key.keyId == PushTestData.keyId)
    }

    @Test func importPreservesOtherConfigKeys() throws {
        let directory = try PushTestData.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "config.json")
        try Data(#"{"gatewayPort":47421,"hookPort":47420,"hookSecret":"segredo"}"#.utf8).write(to: configURL)
        let keyFile = directory.appending(path: "key.p8")
        try Data(P256.Signing.PrivateKey().pemRepresentation.utf8).write(to: keyFile)
        let importer = ApnsKeyImporter(keyStore: InMemoryApnsKeyStore(), configStore: ApnsConfigStore(url: configURL))

        _ = try importer.importKey(fileURL: keyFile, keyId: PushTestData.keyId, teamId: PushTestData.teamId, bundleId: "com.example.other")

        let object = try PushTestData.jsonObject(try Data(contentsOf: configURL))
        #expect(object["hookPort"] as? Int == 47420)
        #expect(object["gatewayPort"] as? Int == 47421)
        #expect(object["hookSecret"] as? String == "segredo")
        let apns = try #require(object["apns"] as? [String: String])
        #expect(apns == ["teamId": PushTestData.teamId, "keyId": PushTestData.keyId, "bundleId": "com.example.other"])
    }

    @Test func importRejectsInvalidInputWithoutTouchingStores() throws {
        let directory = try PushTestData.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "config.json")
        let keyFile = directory.appending(path: "key.p8")
        try Data("não é uma chave".utf8).write(to: keyFile)
        let store = InMemoryApnsKeyStore()
        let importer = ApnsKeyImporter(keyStore: store, configStore: ApnsConfigStore(url: configURL))

        #expect(throws: ApnsError.invalidPrivateKey) {
            try importer.importKey(fileURL: keyFile, keyId: PushTestData.keyId, teamId: PushTestData.teamId)
        }
        #expect(throws: ApnsError.invalidKeyId) {
            try importer.importKey(fileURL: keyFile, keyId: "5p55", teamId: PushTestData.teamId)
        }
        #expect(throws: ApnsError.invalidBundleId) {
            try importer.importKey(fileURL: keyFile, keyId: PushTestData.keyId, teamId: PushTestData.teamId, bundleId: "semponto")
        }
        #expect(FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) == false)
        #expect(throws: ApnsError.keyNotFound(keyId: PushTestData.keyId)) { try store.load(keyId: PushTestData.keyId) }
    }

    @Test func loadWithoutConfigReportsNotConfigured() throws {
        let directory = try PushTestData.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = ApnsKeyImporter(
            keyStore: InMemoryApnsKeyStore(),
            configStore: ApnsConfigStore(url: directory.appending(path: "config.json"))
        )
        #expect(throws: ApnsError.notConfigured) { try importer.loadSigningKey() }
    }
}
