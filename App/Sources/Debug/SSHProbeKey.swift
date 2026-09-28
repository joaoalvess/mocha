#if DEBUG
import CryptoKit
import Foundation
import NIOSSH
import Security

enum SSHProbeKeyError: Error, LocalizedError {
    case secureEnclaveUnavailable
    case missingFaceIDUsageDescription
    case accessControl
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            "Secure Enclave indisponível neste aparelho."
        case .missingFaceIDUsageDescription:
            "Falta NSFaceIDUsageDescription no Info.plist."
        case .accessControl:
            "Não foi possível criar o controle de acesso da chave."
        case .keychain(let status):
            "Erro do Keychain: \(status)."
        }
    }
}

enum SSHProbeSigningKey: Sendable {
    case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    static let comment = "mocha-ssh-probe"

    var sshPrivateKey: NIOSSHPrivateKey {
        switch self {
        case .secureEnclave(let key):
            NIOSSHPrivateKey(secureEnclaveP256Key: key)
        case .software(let key):
            NIOSSHPrivateKey(p256Key: key)
        }
    }

    var authorizedKeysLine: String {
        String(openSSHPublicKey: sshPrivateKey.publicKey) + " " + Self.comment
    }

    var kindLabel: String {
        switch self {
        case .secureEnclave:
            "Secure Enclave"
        case .software:
            "Software (só simulador)"
        }
    }
}

enum SSHProbeKeyStore {
    static let service = "com.joaoalves.mocha.ssh-probe"
    static let faceIDUsageKey = "NSFaceIDUsageDescription"

    static func loadOrCreate() throws -> SSHProbeSigningKey {
        #if targetEnvironment(simulator)
        return .software(try loadOrCreateSoftwareKey())
        #else
        return .secureEnclave(try loadOrCreateSecureEnclaveKey())
        #endif
    }

    static func delete() {
        for account in [Account.secureEnclave, Account.software] {
            SecItemDelete(query(account: account) as CFDictionary)
        }
    }

    private enum Account: String {
        case secureEnclave = "secure-enclave-p256"
        case software = "software-p256"
    }

    private static func loadOrCreateSecureEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw SSHProbeKeyError.secureEnclaveUnavailable }
        guard Bundle.main.object(forInfoDictionaryKey: faceIDUsageKey) != nil else {
            throw SSHProbeKeyError.missingFaceIDUsageDescription
        }
        if let blob = try readBlob(account: .secureEnclave) {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
        }
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        ) else {
            throw SSHProbeKeyError.accessControl
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
        try writeBlob(key.dataRepresentation, account: .secureEnclave)
        return key
    }

    private static func loadOrCreateSoftwareKey() throws -> P256.Signing.PrivateKey {
        if let blob = try readBlob(account: .software) {
            return try P256.Signing.PrivateKey(rawRepresentation: blob)
        }
        let key = P256.Signing.PrivateKey()
        try writeBlob(key.rawRepresentation, account: .software)
        return key
    }

    private static func query(account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private static func readBlob(account: Account) throws -> Data? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SSHProbeKeyError.keychain(status)
        }
    }

    private static func writeBlob(_ blob: Data, account: Account) throws {
        var attributes = query(account: account)
        attributes[kSecValueData as String] = blob
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SSHProbeKeyError.keychain(status) }
    }
}
#endif
