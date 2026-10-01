import MochaDaemonCore
import Synchronization

public final class FakeConsoleLock: ConsoleLockReading {
    private let state: Mutex<ConsoleLock>

    public init(_ lock: ConsoleLock = .unlocked) {
        state = Mutex(lock)
    }

    public func set(_ lock: ConsoleLock) {
        state.withLock { $0 = lock }
    }

    public func consoleLock() -> ConsoleLock {
        state.withLock { $0 }
    }
}
