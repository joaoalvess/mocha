import CryptoKit
import Foundation

public enum ApnsJWT {
    struct Header: Codable, Equatable {
        let alg: String
        let kid: String
    }

    struct Claims: Codable, Equatable {
        let iss: String
        let iat: Int
    }

    public static func make(key: ApnsSigningKey, issuedAt: Date) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let header = try encoder.encode(Header(alg: "ES256", kid: key.keyId))
        let claims = try encoder.encode(Claims(iss: key.teamId, iat: Int(issuedAt.timeIntervalSince1970)))
        let signingInput = Base64URL.encode(header) + "." + Base64URL.encode(claims)
        let signature = try key.privateKey.signature(for: Data(signingInput.utf8))
        return signingInput + "." + Base64URL.encode(signature.rawRepresentation)
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
