import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

struct PairingTests {
    private let url = Sample.pairingURL

    @Test func codeIsValidOnlyOnce() async {
        let pairing = Pairing(clock: ManualClock())
        let code = await pairing.issueCode(url: url)
        #expect(await pairing.redeem(code.code))
        #expect(await pairing.redeem(code.code) == false)
    }

    @Test func codeExpiresAfterTenMinutes() async {
        let clock = ManualClock()
        let pairing = Pairing(clock: clock)
        let first = await pairing.issueCode(url: url)
        let second = await pairing.issueCode(url: url)
        #expect(first.expiresAt == clock.now().addingTimeInterval(600))
        clock.advance(by: .seconds(599))
        #expect(await pairing.redeem(first.code))
        clock.advance(by: .seconds(1))
        #expect(await pairing.redeem(second.code) == false)
    }

    @Test func unknownCodeIsRefused() async {
        let pairing = Pairing(clock: ManualClock())
        _ = await pairing.issueCode(url: url)
        #expect(await pairing.redeem("") == false)
        #expect(await pairing.redeem("nunca-emitido") == false)
    }

    @Test func codesAreRandomBase64URLWithoutPadding() async {
        let pairing = Pairing(clock: ManualClock())
        var codes: Set<String> = []
        for _ in 0..<20 {
            let code = await pairing.issueCode(url: url).code
            #expect(code.count == 43)
            #expect(code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            codes.insert(code)
        }
        #expect(codes.count == 20)
    }

    @Test func linkRoundTripsThroughPairingLink() async throws {
        let code = await Pairing(clock: ManualClock()).issueCode(url: url)
        let link = code.link.link
        #expect(link.scheme == "mocha")
        #expect(link.host() == "pair")
        let parsed = try #require(PairingLink(link))
        #expect(parsed.url == url)
        #expect(parsed.code == code.code)
    }

    @Test func pairingCodeEncodesCodeUrlAndExpiry() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_790_000_600)
        let code = PairingCode(code: "abc_DEF-123", url: url, expiresAt: expiresAt)
        let data = try JSONEncoder().encode(code)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == [
            "code": "abc_DEF-123",
            "url": "wss://mac.example.ts.net/v1",
            "expiresAt": ProtocolDate.string(from: expiresAt),
        ])
    }

    @Test func secureTokenHashAndComparison() {
        #expect(SecureToken.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SecureToken.constantTimeEquals("abc", "abc"))
        #expect(SecureToken.constantTimeEquals("abc", "abd") == false)
        #expect(SecureToken.constantTimeEquals("abc", "abcd") == false)
        #expect(SecureToken.generate() != SecureToken.generate())
    }
}
