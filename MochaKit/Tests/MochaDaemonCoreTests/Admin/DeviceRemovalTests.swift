import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct DeviceRemovalTests {
    static func withStore(_ body: (DeviceStore, DeviceRecord) async throws -> Void) async throws {
        try await withTemporaryHome { home in
            let store = DeviceStore(fileURL: home.paths.devicesFile)
            let record = try await store.register(name: "iPhone", token: "token-de-teste", at: Date(timeIntervalSince1970: 1_790_000_000))
            try await body(store, record)
        }
    }

    @Test func runningDaemonRemovesTheDevice() async throws {
        try await Self.withStore { store, record in
            let local = FakeLocalControl(removal: .success(true))
            let outcome = try await DeviceRemoval(local: local, store: store).remove(record.id)
            #expect(outcome == .removedByDaemon)
            #expect(local.removedIds == [record.id])
            #expect(try await store.devices().map(\.id) == [record.id])
        }
    }

    @Test func runningDaemonThatDoesNotKnowTheDevice() async throws {
        try await Self.withStore { store, record in
            let local = FakeLocalControl(removal: .success(false))
            let outcome = try await DeviceRemoval(local: local, store: store).remove("outro")
            #expect(outcome == .notFound(byDaemon: true))
            #expect(try await store.devices().map(\.id) == [record.id])
        }
    }

    @Test func withoutTheDaemonTheFileIsEditedDirectly() async throws {
        try await Self.withStore { store, record in
            let removal = DeviceRemoval(local: FakeLocalControl(), store: store)
            let outcome = try await removal.remove(record.id)
            #expect(outcome == .removedFromFile)
            #expect(try await store.devices().isEmpty)
            #expect(try await removal.remove(record.id) == .notFound(byDaemon: false))
        }
    }

    @Test func otherLocalErrorsAreNotSwallowed() async throws {
        try await Self.withStore { store, record in
            let local = FakeLocalControl(removal: .failure(.timedOut))
            await #expect(throws: LocalControlError.timedOut) {
                try await DeviceRemoval(local: local, store: store).remove(record.id)
            }
            let remaining = try await store.devices()
            #expect(remaining.map(\.id) == [record.id])
        }
    }
}
