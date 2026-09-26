import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct OrderedJSONTests {
    @Test func proposedSettingsRoundTripByteForByte() throws {
        let data = try Fixtures.data("hooks/settings.install-hooks.proposed.json")
        let json = try OrderedJSON.parse(data)

        #expect(json.prettyPrinted() + "\n" == String(decoding: data, as: UTF8.self))
        #expect(json["hooks"]?.members?.map(\.key) == ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "PermissionRequest"])
    }

    @Test func keepsMemberOrderNumbersAndDuplicateKeys() throws {
        let json = try OrderedJSON.parse(Data(#"{"z": 1.50, "a": -0e+3, "m": [true, false, null], "a": "último"}"#.utf8))

        #expect(json.members?.map(\.key) == ["z", "a", "m", "a"])
        #expect(json["a"] == .string("último"))
        #expect(json["z"] == .number("1.50"))
        #expect(json.prettyPrinted() == """
            {
              "z": 1.50,
              "a": -0e+3,
              "m": [
                true,
                false,
                null
              ],
              "a": "último"
            }
            """)
    }

    @Test func escapesLikeJSONStringify() throws {
        let json = try OrderedJSON.parse(Data(#"{"s": "aspas \" barra \\ / é 😀 \n\t\r\b\f \u0001 \u001f"}"#.utf8))

        #expect(json["s"] == .string("aspas \" barra \\ / é 😀 \n\t\r\u{08}\u{0C} \u{01} \u{1F}"))
        #expect(json.prettyPrinted() == #"""
            {
              "s": "aspas \" barra \\ / é 😀 \n\t\r\b\f \u0001 \u001f"
            }
            """#)
    }

    @Test func emptyContainersPrintCompact() throws {
        let json = try OrderedJSON.parse(Data(#"{"a": [], "o": {}, "n": [{}]}"#.utf8))

        #expect(json.prettyPrinted() == """
            {
              "a": [],
              "o": {},
              "n": [
                {}
              ]
            }
            """)
    }

    @Test(arguments: [
        "",
        "{",
        #"{"a" 1}"#,
        #"{"a": 1,}"#,
        "[1 2]",
        "01",
        "1.",
        "-",
        "1e",
        "tru",
        #""sem fim"#,
        "\"quebra\nde linha\"",
        #""\x""#,
        #""\u12""#,
        "{} {}",
        String(repeating: "[", count: 300) + String(repeating: "]", count: 300),
    ])
    func rejectsInvalidJSON(_ text: String) {
        #expect(throws: OrderedJSONError.self) {
            try OrderedJSON.parse(Data(text.utf8))
        }
    }

    @Test func settingReplacesInPlaceAppendsAndRemoves() {
        let json = OrderedJSON.object([
            OrderedJSON.Member("a", .number("1")),
            OrderedJSON.Member("b", .number("2")),
            OrderedJSON.Member("a", .number("3")),
        ])

        #expect(json.setting("a", to: .string("x")).members == [OrderedJSON.Member("a", .string("x")), OrderedJSON.Member("b", .number("2"))])
        #expect(json.setting("c", to: .null).members?.map(\.key) == ["a", "b", "a", "c"])
        #expect(json.setting("a", to: nil).members == [OrderedJSON.Member("b", .number("2"))])
        #expect(OrderedJSON.array([]).setting("a", to: .null) == .array([]))
    }
}
