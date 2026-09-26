import Foundation
import Testing
@testable import MochaProtocol

@Suite struct ProtocolDateTests {
    @Test(arguments: [
        "2026-09-25T15:44:34.551Z",
        "2026-09-25T15:44:41.000Z",
        "2026-12-31T23:59:59.999Z",
        "1970-01-01T00:00:00.001Z",
        "2026-02-28T09:05:07.040Z",
    ])
    func stringsSurviveParseAndFormat(_ string: String) throws {
        let date = try #require(ProtocolDate.date(from: string))
        #expect(ProtocolDate.string(from: date) == string)
    }

    @Test func formatRoundsToTheNearestMillisecond() {
        #expect(ProtocolDate.string(from: Date(timeIntervalSince1970: 1.2346)) == "1970-01-01T00:00:01.235Z")
        #expect(ProtocolDate.string(from: Date(timeIntervalSince1970: 59.9996)) == "1970-01-01T00:01:00.000Z")
    }

    @Test func parsesDatesWithoutFractionalSeconds() throws {
        let date = try #require(ProtocolDate.date(from: "2026-09-25T15:44:34Z"))
        #expect(ProtocolDate.string(from: date) == "2026-09-25T15:44:34.000Z")
    }

    @Test func rejectsInvalidDates() {
        #expect(ProtocolDate.date(from: "ontem") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ChatItem.self,
                from: Data(#"{"id":"a","at":"25/09/2026","type":"notice","text":"x"}"#.utf8)
            )
        }
    }
}
