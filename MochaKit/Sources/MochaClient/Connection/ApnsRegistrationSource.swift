import MochaProtocol
import Synchronization

public protocol ApnsRegistrationSource: Sendable {
    func currentRegistration() -> ApnsRegistration?
}

public struct NoApnsRegistration: ApnsRegistrationSource {
    public init() {}

    public func currentRegistration() -> ApnsRegistration? {
        nil
    }
}

public final class ApnsRegistrationBox: ApnsRegistrationSource {
    private let registration: Mutex<ApnsRegistration?>

    public init(_ registration: ApnsRegistration? = nil) {
        self.registration = Mutex(registration)
    }

    public func update(_ newRegistration: ApnsRegistration?) {
        registration.withLock { $0 = newRegistration }
    }

    public func currentRegistration() -> ApnsRegistration? {
        registration.withLock { $0 }
    }
}
