import Foundation
import Security

public protocol ApnsKeyStoring: Sendable {
    func save(pem: String, keyId: String) throws
    func load(keyId: String) throws -> String
}

public struct KeychainApnsKeyStore: ApnsKeyStoring {
    public static let service = "com.joaoalves.mocha.apns"

    public init() {}

    public func save(pem: String, keyId: String) throws {
        let data = Data(pem.utf8)
        var attributes = baseQuery(keyId: keyId)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = "Mocha APNs \(keyId)"
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(
                baseQuery(keyId: keyId) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        }
        guard status == errSecSuccess else { throw ApnsError.keychain(status: status) }
    }

    public func load(keyId: String) throws -> String {
        var query = baseQuery(keyId: keyId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw ApnsError.keyNotFound(keyId: keyId)
        }
        guard status == errSecSuccess, let data = result as? Data, let pem = String(data: data, encoding: .utf8) else {
            throw ApnsError.keychain(status: status)
        }
        return pem
    }

    private func baseQuery(keyId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: keyId,
        ]
    }
}
