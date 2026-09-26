import CryptoKit
import Foundation
import Testing
@testable import MochaDaemonCore

struct ApnsJWTTests {
    @Test func tokenHasHeaderAndClaimsExpectedByApns() throws {
        let key = try PushTestData.signingKey()
        let issuedAt = Date(timeIntervalSince1970: 1_790_000_000.9)
        let parts = try ApnsJWT.make(key: key, issuedAt: issuedAt).split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        let header = try JSONDecoder().decode(ApnsJWT.Header.self, from: try #require(Base64URL.decode(parts[0])))
        let claims = try JSONDecoder().decode(ApnsJWT.Claims.self, from: try #require(Base64URL.decode(parts[1])))
        #expect(header == ApnsJWT.Header(alg: "ES256", kid: PushTestData.keyId))
        #expect(claims == ApnsJWT.Claims(iss: PushTestData.teamId, iat: 1_790_000_000))
        let rawHeader = try PushTestData.jsonObject(try #require(Base64URL.decode(parts[0])))
        let rawClaims = try PushTestData.jsonObject(try #require(Base64URL.decode(parts[1])))
        #expect(Set(rawHeader.keys) == ["alg", "kid"])
        #expect(Set(rawClaims.keys) == ["iss", "iat"])
    }

    @Test func tokenIsBase64URLWithoutPadding() throws {
        let token = try ApnsJWT.make(key: try PushTestData.signingKey(), issuedAt: Date())
        #expect(token.contains("=") == false)
        #expect(token.contains("+") == false)
        #expect(token.contains("/") == false)
    }

    @Test func signatureIsRawRAndSVerifiableWithPublicKey() throws {
        let privateKey = P256.Signing.PrivateKey()
        let token = try ApnsJWT.make(key: try PushTestData.signingKey(privateKey), issuedAt: Date())
        let parts = token.split(separator: ".").map(String.init)
        let signatureBytes = try #require(Base64URL.decode(parts[2]))
        #expect(signatureBytes.count == 64)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureBytes)
        let signingInput = Data((parts[0] + "." + parts[1]).utf8)
        #expect(privateKey.publicKey.isValidSignature(signature, for: signingInput))
        #expect(P256.Signing.PrivateKey().publicKey.isValidSignature(signature, for: signingInput) == false)
        #expect(privateKey.publicKey.isValidSignature(signature, for: Data((parts[0] + ".x").utf8)) == false)
    }

    @Test func signingKeyRejectsInvalidInput() throws {
        let pem = P256.Signing.PrivateKey().pemRepresentation
        #expect(throws: ApnsError.invalidKeyId) { try ApnsSigningKey(keyId: "abc", teamId: PushTestData.teamId, pem: pem) }
        #expect(throws: ApnsError.invalidTeamId) { try ApnsSigningKey(keyId: PushTestData.keyId, teamId: "TEAM12345#", pem: pem) }
        #expect(throws: ApnsError.invalidPrivateKey) {
            try ApnsSigningKey(keyId: PushTestData.keyId, teamId: PushTestData.teamId, pem: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----")
        }
    }

    @Test func providerReusesTokenAndRenewsAfterFortyMinutes() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let provider = ApnsTokenProvider(key: try PushTestData.signingKey(), now: { clock.now })
        let first = try await provider.token()
        clock.advance(by: 39 * 60)
        #expect(try await provider.token() == first)
        clock.advance(by: 60)
        let renewed = try await provider.token()
        #expect(renewed != first)
        let claims = try JSONDecoder().decode(
            ApnsJWT.Claims.self,
            from: try #require(Base64URL.decode(String(renewed.split(separator: ".")[1])))
        )
        #expect(claims.iat == 1_790_000_000 + 40 * 60)
    }

    @Test func providerRenewsAfterInvalidation() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let provider = ApnsTokenProvider(key: try PushTestData.signingKey(), now: { clock.now })
        let first = try await provider.token()
        clock.advance(by: 1)
        await provider.invalidate()
        #expect(try await provider.token() != first)
    }
}
