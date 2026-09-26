import CryptoKit
import Foundation
import Synchronization
@testable import MochaDaemonCore

final class FakeApnsTransport: ApnsTransport {
    private let recorded = Mutex<[URLRequest]>([])
    private let responses = Mutex<[ApnsResponse]>([])

    init(responses: [ApnsResponse] = []) {
        self.responses.withLock { $0 = responses }
    }

    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    func send(_ request: URLRequest) async throws -> ApnsResponse {
        recorded.withLock { $0.append(request) }
        return responses.withLock { queue in
            queue.isEmpty ? ApnsResponse(status: 200, apnsId: "fake") : queue.removeFirst()
        }
    }
}

final class InMemoryApnsKeyStore: ApnsKeyStoring {
    private let items = Mutex<[String: String]>([:])

    func save(pem: String, keyId: String) throws {
        items.withLock { $0[keyId] = pem }
    }

    func load(keyId: String) throws -> String {
        guard let pem = items.withLock({ $0[keyId] }) else { throw ApnsError.keyNotFound(keyId: keyId) }
        return pem
    }
}

final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date) {
        current = Mutex(start)
    }

    var now: Date {
        current.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

enum PushTestData {
    static let keyId = "ABCDE12345"
    static let teamId = "TEAM123456"
    static let deviceToken = String(repeating: "ab", count: 32)

    static func signingKey(_ privateKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) throws -> ApnsSigningKey {
        try ApnsSigningKey(keyId: keyId, teamId: teamId, pem: privateKey.pemRepresentation)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "mocha-push-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return object
    }
}
