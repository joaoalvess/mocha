import Foundation
import Testing
@testable import MochaProtocol

@Suite struct PairingLinkTests {
    @Test(arguments: [
        "wss://mac-mini.tail1234.ts.net/v1",
        "wss://mac.tail.ts.net:8443/v1?probe=1&mode=a:b/c",
        "ws://127.0.0.1:47421/v1?x=1+2&y=a%20b&z=c=d",
    ])
    func roundTripsThroughTheLink(_ socket: String) throws {
        let original = PairingLink(url: try #require(URL(string: socket)), code: "q1W-e2R_t3Y")

        let link = original.link

        #expect(link.scheme == "mocha")
        #expect(link.host() == "pair")
        let query = try #require(link.query(percentEncoded: true))
        let fields = query.split(separator: "&")
        #expect(fields.count == 2)
        let urlField = try #require(fields.first { $0.hasPrefix("url=") }).dropFirst("url=".count)
        for reserved in [":", "/", "?", "&", "=", "+"] {
            #expect(!urlField.contains(reserved), "\(reserved) sem codificar em \(urlField)")
        }
        let decoded = try #require(PairingLink(link))
        #expect(decoded == original)
        #expect(decoded.url.absoluteString == socket)
    }

    @Test func parsesTheLinkPrintedByTheDaemon() throws {
        let link = try #require(
            URL(string: "mocha://pair?url=wss%3A%2F%2Fmac-mini.tail1234.ts.net%2Fv1&code=Zm9vYmFyYmF6_-0")
        )

        let pairing = try #require(PairingLink(link))

        #expect(pairing.url == URL(string: "wss://mac-mini.tail1234.ts.net/v1"))
        #expect(pairing.code == "Zm9vYmFyYmF6_-0")
    }

    @Test(arguments: [
        "mocha://pair?url=wss://mac.tail.ts.net/v1&code=abc",
        "mocha://pair?code=abc&url=ws%3A%2F%2F127.0.0.1%3A47421%2Fv1",
        "mocha://pair?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=YWJjZA==",
    ])
    func acceptsValidVariants(_ string: String) throws {
        #expect(PairingLink(try #require(URL(string: string))) != nil)
    }

    @Test(arguments: [
        "https://pair?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=abc",
        "mocha://agent?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=abc",
        "mocha://pairing?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=abc",
        "mocha://pair?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1",
        "mocha://pair?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=",
        "mocha://pair?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=abc%2Bdef",
        "mocha://pair?url=wss%3A%2F%2Fmac.tail.ts.net%2Fv1&code=abc===",
        "mocha://pair?code=abc",
        "mocha://pair?url=&code=abc",
        "mocha://pair?url=https%3A%2F%2Fmac.tail.ts.net%2Fv1&code=abc",
        "mocha://pair?url=mac.tail.ts.net%2Fv1&code=abc",
        "mocha://pair?url=wss%3A%2F%2F%2Fv1&code=abc",
        "mocha://pair?url=wss%3Av1&code=abc",
    ])
    func rejectsInvalidLinks(_ string: String) throws {
        #expect(PairingLink(try #require(URL(string: string))) == nil)
    }
}
