import Foundation
#if os(macOS)
import IOKit
#endif

public enum ConsoleLock: String, Sendable, Equatable {
    case locked
    case unlocked
    case unknown

    public var isAtMac: Bool {
        self == .unlocked
    }
}

public protocol ConsoleLockReading: Sendable {
    func consoleLock() -> ConsoleLock
}

public struct IORegistryConsoleLockReader: ConsoleLockReading {
    public init() {}

    public func consoleLock() -> ConsoleLock {
        #if os(macOS)
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return .unknown }
        defer { IOObjectRelease(root) }
        guard let property = IORegistryEntryCreateCFProperty(root, "IOConsoleLocked" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let isLocked = property as? Bool
        else { return .unknown }
        return isLocked ? .locked : .unlocked
        #else
        return .unknown
        #endif
    }
}
