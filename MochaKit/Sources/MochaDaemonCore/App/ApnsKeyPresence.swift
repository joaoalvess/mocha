import Foundation
import Security

public enum KeychainItemPresence: Sendable, Equatable {
    case present
    case missing
    case failed(OSStatus)
}

public protocol ApnsKeyPresenceChecking: Sendable {
    func presence(keyId: String) -> KeychainItemPresence
}

public struct KeychainApnsKeyPresence: ApnsKeyPresenceChecking {
    public init() {}

    public func presence(keyId: String) -> KeychainItemPresence {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainApnsKeyStore.service,
            kSecAttrAccount as String: keyId,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess:
            return .present
        case errSecItemNotFound:
            return .missing
        case let status:
            return .failed(status)
        }
    }
}
