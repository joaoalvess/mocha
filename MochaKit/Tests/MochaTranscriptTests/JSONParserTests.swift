import Foundation
import Testing
@testable import MochaTranscript

@Suite
struct JSONParserTests {
    private func parse(_ text: String) throws -> JSONValue {
        try JSONParser.parse(Array(text.utf8))
    }

    @Test func parsesNestedValuesKeepingKeyOrder() throws {
        let value = try parse(#"{"z":1,"a":[true,false,null],"m":{"k":"v","b":-2.5e3}}"#)
        let object = try #require(value.objectValue)
        #expect(object.members.map(\.key) == ["z", "a", "m"])
        #expect(value["z"]?.intValue == 1)
        #expect(value["a"] == .array([.bool(true), .bool(false), .null]))
        #expect(value["m"]?["k"]?.stringValue == "v")
        #expect(value["m"]?["b"] == .number("-2.5e3"))
    }

    @Test func decodesEscapesAndSurrogatePairs() throws {
        let value = try parse(#""aspas \" barra \\ \/ \n\t é 😀 \ud800x""#)
        #expect(value.stringValue == "aspas \" barra \\ / \n\t é 😀 \u{FFFD}x")
    }

    @Test func lastDuplicateKeyWins() throws {
        #expect(try parse(#"{"a":1,"a":2}"#)["a"]?.intValue == 2)
    }

    @Test(arguments: [
        #"{"a":1"#,
        #"{"a":"texto"#,
        "isto não é json",
        #"{"a":01}"#,
        #"{"a":1,}"#,
        #"[1 2]"#,
        "{\"a\":\"quebra\nde linha\"}",
        #"{"a":1} lixo"#,
        "",
    ])
    func rejectsInvalidJSON(_ text: String) {
        #expect(throws: JSONParseError.self) { try parse(text) }
    }

    @Test func serializesCompactlyLikeJavaScript() throws {
        let text = #"{"command":"echo \"oi\" > /tmp/x\n","n":3,"ok":true,"nested":{"list":[1,"é",null]},"ctl":"\u0001"}"#
        let value = try parse(text)
        #expect(value.serialized() == text)
    }

    @Test func rejectsDeepNesting() {
        let text = String(repeating: "[", count: 600) + String(repeating: "]", count: 600)
        #expect(throws: JSONParseError.self) { try parse(text) }
    }
}
