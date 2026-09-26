import MochaProtocol

public enum DeviceRemovalOutcome: Sendable, Equatable {
    case removedByDaemon
    case removedFromFile
    case notFound(byDaemon: Bool)
}

public struct DeviceRemoval: Sendable {
    let local: any LocalControlling
    let store: DeviceStore

    public init(local: any LocalControlling, store: DeviceStore) {
        self.local = local
        self.store = store
    }

    public func remove(_ id: DeviceID) async throws -> DeviceRemovalOutcome {
        do {
            return try await local.removeDevice(id) ? .removedByDaemon : .notFound(byDaemon: true)
        } catch LocalControlError.notRunning {
            return try await store.remove(id) ? .removedFromFile : .notFound(byDaemon: false)
        }
    }
}
