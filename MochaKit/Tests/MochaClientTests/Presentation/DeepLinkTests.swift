import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct DeepLinkTests {
    @Test func parsesPercentEncodedAgentLink() throws {
        let url = try #require(URL(string: "mocha://agent/w5%3Ap1"))
        #expect(DeepLink(url) == .agent("w5:p1"))
    }

    @Test func parsesPlainAgentLink() throws {
        let url = try #require(URL(string: "MOCHA://Agent/w1:p1"))
        #expect(DeepLink(url) == .agent("w1:p1"))
    }

    @Test func agentLinkRoundTrips() throws {
        let link = DeepLink.agent("w2:p1")
        let url = try #require(link.url)
        #expect(url.absoluteString == "mocha://agent/w2%3Ap1")
        #expect(DeepLink(url) == link)
    }

    @Test func parsesPairingLink() throws {
        let url = try #require(URL(string: "mocha://pair?url=wss%3A%2F%2Fmac.tail1234.ts.net%2Fv1&code=abc_DEF-123"))
        let expected = PairingLink(url: try #require(URL(string: "wss://mac.tail1234.ts.net/v1")), code: "abc_DEF-123")
        #expect(DeepLink(url) == .pair(expected))
    }

    @Test(arguments: [
        "mocha://agent",
        "mocha://agent/",
        "mocha://pair?code=abc",
        "mocha://settings",
        "https://agent/w1:p1",
    ])
    func rejectsInvalidLinks(text: String) throws {
        let url = try #require(URL(string: text))
        #expect(DeepLink(url) == nil)
    }
}
