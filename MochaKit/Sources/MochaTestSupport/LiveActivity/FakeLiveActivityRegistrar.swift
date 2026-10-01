import MochaDaemonCore
import MochaProtocol
import Synchronization

public final class FakeLiveActivityRegistrar: LiveActivityRegistering {
    public struct Registered: Sendable, Equatable {
        public let registration: LiveActivityRegistration
        public let deviceId: DeviceID

        public init(registration: LiveActivityRegistration, deviceId: DeviceID) {
            self.registration = registration
            self.deviceId = deviceId
        }
    }

    private struct State {
        var registered: [Registered] = []
        var preferences: [DeviceID: DevicePreferences] = [:]
        var failure: (any Error)?
    }

    private let state = Mutex(State())

    public init() {}

    public var registered: [Registered] {
        state.withLock { $0.registered }
    }

    public var preferences: [DeviceID: DevicePreferences] {
        state.withLock { $0.preferences }
    }

    public func fail(with error: (any Error)?) {
        state.withLock { $0.failure = error }
    }

    public func register(_ registration: LiveActivityRegistration, from deviceId: DeviceID) async throws {
        try state.withLock { state in
            if let failure = state.failure {
                throw failure
            }
            state.registered.append(Registered(registration: registration, deviceId: deviceId))
        }
    }

    public func preferencesChanged(_ preferences: DevicePreferences, for deviceId: DeviceID) async {
        state.withLock { $0.preferences[deviceId] = preferences }
    }
}
