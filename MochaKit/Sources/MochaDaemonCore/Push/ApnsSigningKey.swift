import CryptoKit
import Foundation

public struct ApnsSigningKey: Sendable {
    public let keyId: String
    public let teamId: String
    let privateKey: P256.Signing.PrivateKey

    public init(keyId: String, teamId: String, pem: String) throws {
        guard ApnsIdentifier.isValid(keyId) else { throw ApnsError.invalidKeyId }
        guard ApnsIdentifier.isValid(teamId) else { throw ApnsError.invalidTeamId }
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw ApnsError.invalidPrivateKey
        }
        self.keyId = keyId
        self.teamId = teamId
    }

    public static func validatePEM(_ pem: String) throws {
        do {
            _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw ApnsError.invalidPrivateKey
        }
    }
}

public enum ApnsIdentifier {
    public static func isValid(_ value: String) -> Bool {
        value.count == 10 && value.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }

    public static func isValidBundleId(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
