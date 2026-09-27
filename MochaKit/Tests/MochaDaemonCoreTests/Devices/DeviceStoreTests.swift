import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

struct DeviceStoreTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func withStore(_ body: (DeviceStore, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "mocha-devices-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Mocha", directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "devices.json")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try await body(DeviceStore(fileURL: fileURL), fileURL)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test func missingFileMeansNoDevices() async throws {
        try await withStore { store, fileURL async throws in
            #expect(try await store.devices().isEmpty)
            #expect(try await store.device(matchingToken: "qualquer") == nil)
            #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) == false)
        }
    }

    @Test func registerWritesOnlyTheHashWithOwnerOnlyPermissions() async throws {
        try await withStore { store, fileURL in
            let token = SecureToken.generate()
            let record = try await store.register(name: "iPhone do João", token: token, at: start)
            #expect(record.tokenSha256 == SecureToken.sha256Hex(token))
            #expect(record.createdAt == start)
            #expect(record.lastSeenAt == start)
            #expect(record.preferences == DevicePreferences())

            #expect(try permissions(of: fileURL) == 0o600)
            #expect(try permissions(of: fileURL.deletingLastPathComponent()) == 0o700)
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!contents.contains(token))
            #expect(contents.contains(SecureToken.sha256Hex(token)))
            #expect(contents.contains(ProtocolDate.string(from: start)))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path(percentEncoded: false))
            #expect(leftovers == ["devices.json"])
        }
    }

    @Test func tokenFindsItsDevice() async throws {
        try await withStore { store, _ in
            let firstToken = SecureToken.generate()
            let secondToken = SecureToken.generate()
            let first = try await store.register(name: "iPhone", token: firstToken, at: start)
            let second = try await store.register(name: "iPad", token: secondToken, at: start)
            #expect(try await store.device(matchingToken: firstToken)?.id == first.id)
            #expect(try await store.device(matchingToken: secondToken)?.id == second.id)
            #expect(try await store.device(matchingToken: SecureToken.generate()) == nil)
            #expect(try await store.device(matchingToken: SecureToken.sha256Hex(firstToken)) == nil)
        }
    }

    @Test func markSeenAndRemoveRewriteTheFile() async throws {
        try await withStore { store, fileURL in
            let record = try await store.register(name: "iPhone", token: SecureToken.generate(), at: start)
            let later = start.addingTimeInterval(3600)
            try await store.markSeen(record.id, at: later)
            #expect(try await store.devices().first?.lastSeenAt == later)
            #expect(try await store.devices().first?.createdAt == start)
            #expect(try await store.remove(record.id))
            #expect(try await store.remove(record.id) == false)
            #expect(try await store.devices().isEmpty)
            #expect(try permissions(of: fileURL) == 0o600)
        }
    }

    @Test func everyWriteRereadsTheFile() async throws {
        try await withStore { store, fileURL in
            _ = try await store.register(name: "iPhone", token: SecureToken.generate(), at: start)
            let other = DeviceStore(fileURL: fileURL)
            let external = try await other.register(name: "iPad", token: SecureToken.generate(), at: start)
            let third = try await store.register(name: "Mac", token: SecureToken.generate(), at: start)
            #expect(try await store.devices().map(\.name) == ["iPhone", "iPad", "Mac"])
            #expect(try await other.remove(external.id))
            try await store.markSeen(third.id, at: start.addingTimeInterval(60))
            #expect(try await store.devices().map(\.name) == ["iPhone", "Mac"])
        }
    }

    @Test func apnsRegistrationIsStoredKeptAndMovedBetweenDevices() async throws {
        try await withStore { store, fileURL in
            let sandbox = ApnsRegistration(token: String(repeating: "ab", count: 32), env: .sandbox)
            let first = try await store.register(name: "iPhone", token: "t1", at: start, apns: sandbox)
            #expect(first.apns == sandbox)
            try await store.markSeen(first.id, at: start.addingTimeInterval(60))
            #expect(try await store.devices().first?.apns == sandbox)

            let production = ApnsRegistration(token: String(repeating: "cd", count: 32), env: .production)
            try await store.markSeen(first.id, at: start.addingTimeInterval(120), apns: production)
            #expect(try await store.devices().first?.apns == production)

            let second = try await store.register(name: "iPhone novo", token: "t2", at: start, apns: ApnsRegistration(token: production.token.uppercased(), env: .production))
            let records = try await store.devices()
            #expect(records.first { $0.id == first.id }?.apns == nil)
            #expect(records.first { $0.id == second.id }?.apns?.env == .production)
            #expect(try permissions(of: fileURL) == 0o600)
        }
    }

    @Test func preferencesAndTokenRemovalRewriteOnlyTheirDevice() async throws {
        try await withStore { store, _ in
            let registration = ApnsRegistration(token: String(repeating: "ab", count: 32), env: .sandbox)
            let phone = try await store.register(name: "iPhone", token: "t1", at: start, apns: registration)
            let pad = try await store.register(name: "iPad", token: "t2", at: start)

            #expect(try await store.setPreferences(DevicePreferences(turnDoneAlerts: false), for: phone.id))
            #expect(try await store.setPreferences(DevicePreferences(turnDoneAlerts: false), for: "sumiu") == false)
            #expect(try await store.removeApnsToken(String(repeating: "cd", count: 32), from: phone.id) == false)
            #expect(try await store.removeApnsToken(registration.token, from: pad.id) == false)
            #expect(try await store.devices().first { $0.id == phone.id }?.apns == registration)
            #expect(try await store.removeApnsToken(registration.token.uppercased(), from: phone.id))

            let records = try await store.devices()
            #expect(records.first { $0.id == phone.id }?.preferences == DevicePreferences(turnDoneAlerts: false))
            #expect(records.first { $0.id == phone.id }?.apns == nil)
            #expect(records.first { $0.id == pad.id }?.preferences == DevicePreferences())
        }
    }

    @Test func liveActivityTokensBelongToOneDevice() async throws {
        try await withStore { store, _ in
            let pushToStart = String(repeating: "a1", count: 40)
            let update = String(repeating: "b2", count: 40)
            let apns = ApnsRegistration(token: String(repeating: "ab", count: 32), env: .sandbox)
            let phone = try await store.register(name: "iPhone", token: "t1", at: start, apns: apns)
            let pad = try await store.register(name: "iPad", token: "t2", at: start)
            let watch = try await store.register(name: "Outro", token: "t3", at: start)
            let starter = LiveActivityRegistration(pushToStartToken: pushToStart, env: .sandbox)
            let parser = LiveActivityRegistration(activityId: "act-1", updateToken: update, agentId: "w1:p1", env: .sandbox)
            let lexer = LiveActivityRegistration(activityId: "act-2", updateToken: String(repeating: "d4", count: 40), agentId: "w2:p1", env: .sandbox)
            let other = LiveActivityRegistration(pushToStartToken: String(repeating: "c3", count: 40), env: .production)
            func record(_ id: DeviceID) async throws -> DeviceRecord {
                try #require(try await store.devices().first { $0.id == id })
            }

            #expect(try await store.setLiveActivities(pushToStart: starter, agentActivities: [parser, lexer], for: phone.id))
            #expect(try await store.setLiveActivities(pushToStart: other, agentActivities: [], for: watch.id))
            #expect(try await store.setLiveActivities(pushToStart: starter, agentActivities: [], for: "sumiu") == false)
            #expect(try await record(phone.id).liveActivity == starter)
            #expect(try await record(phone.id).agentActivities == [parser, lexer])
            #expect(try await record(phone.id).hasLiveActivity(for: "w1:p1"))
            #expect(try await record(phone.id).hasLiveActivity(for: "w9:p9") == false)

            let claimed = LiveActivityRegistration(activityId: "act-1", updateToken: update.uppercased(), agentId: "w1:p1", env: .sandbox)
            #expect(try await store.setLiveActivities(pushToStart: nil, agentActivities: [claimed], for: pad.id))
            #expect(try await record(phone.id).liveActivity == starter)
            #expect(try await record(phone.id).agentActivities == [lexer])
            #expect(try await record(phone.id).hasLiveActivity(for: "w1:p1") == false)
            #expect(try await record(phone.id).apns == apns)
            #expect(try await record(pad.id).agentActivities == [claimed])
            #expect(try await record(watch.id).liveActivity == other)

            let moved = LiveActivityRegistration(pushToStartToken: pushToStart.uppercased(), env: .sandbox)
            #expect(try await store.setLiveActivities(pushToStart: moved, agentActivities: [claimed], for: pad.id))
            #expect(try await record(phone.id).liveActivity == nil)
            #expect(try await record(phone.id).agentActivities == [lexer])
            #expect(try await record(pad.id).liveActivity == moved)

            #expect(try await store.setLiveActivities(pushToStart: nil, agentActivities: [], for: pad.id))
            #expect(try await record(pad.id).liveActivity == nil)
            #expect(try await record(pad.id).agentActivities.isEmpty)
            #expect(try await record(watch.id).liveActivity == other)
            #expect(try await store.devices().map(\.name) == ["iPhone", "iPad", "Outro"])
        }
    }

    @Test func recordsKeepPreferencesAndOptionalRegistrations() async throws {
        try await withStore { store, fileURL in
            let record = try await store.register(name: "iPhone", token: SecureToken.generate(), at: start)
            let data = try Data(contentsOf: fileURL)
            let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            let object = try #require(objects.first)
            #expect(Set(object.keys) == ["id", "name", "tokenSha256", "createdAt", "lastSeenAt", "preferences"])
            #expect(object["id"] as? String == record.id)
        }
    }
}
