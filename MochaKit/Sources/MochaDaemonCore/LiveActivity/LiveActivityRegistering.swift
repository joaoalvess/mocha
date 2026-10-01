import MochaProtocol

public protocol LiveActivityRegistering: Sendable {
    func register(_ registration: LiveActivityRegistration, from deviceId: DeviceID) async throws
    func preferencesChanged(_ preferences: DevicePreferences, for deviceId: DeviceID) async
}
