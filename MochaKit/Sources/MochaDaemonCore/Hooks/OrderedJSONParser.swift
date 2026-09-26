import Foundation

struct OrderedJSONParser {
    static let maxDepth = 256

    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws -> OrderedJSON {
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw failure() }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> OrderedJSON {
        guard depth < Self.maxDepth else { throw failure() }
        skipWhitespace()
        guard let byte = peek() else { throw failure() }
        switch byte {
        case UInt8(ascii: "{"):
            return try parseObject(depth: depth)
        case UInt8(ascii: "["):
            return try parseArray(depth: depth)
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"):
            try expect("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expect("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expect("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try parseNumber())
        default:
            throw failure()
        }
    }

    private mutating func parseObject(depth: Int) throws -> OrderedJSON {
        index += 1
        var members: [OrderedJSON.Member] = []
        skipWhitespace()
        if peek() == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard peek() == UInt8(ascii: "\"") else { throw failure() }
            let key = try parseString()
            skipWhitespace()
            guard peek() == UInt8(ascii: ":") else { throw failure() }
            index += 1
            members.append(OrderedJSON.Member(key, try parseValue(depth: depth + 1)))
            skipWhitespace()
            switch peek() {
            case UInt8(ascii: ","):
                index += 1
            case UInt8(ascii: "}"):
                index += 1
                return .object(members)
            default:
                throw failure()
            }
        }
    }

    private mutating func parseArray(depth: Int) throws -> OrderedJSON {
        index += 1
        var elements: [OrderedJSON] = []
        skipWhitespace()
        if peek() == UInt8(ascii: "]") {
            index += 1
            return .array(elements)
        }
        while true {
            elements.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            switch peek() {
            case UInt8(ascii: ","):
                index += 1
            case UInt8(ascii: "]"):
                index += 1
                return .array(elements)
            default:
                throw failure()
            }
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var utf8: [UInt8] = []
        while let byte = peek() {
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                guard let text = String(validating: utf8, as: UTF8.self) else { throw failure() }
                return text
            case UInt8(ascii: "\\"):
                try parseEscape(into: &utf8)
            case 0x00..<0x20:
                throw failure()
            default:
                utf8.append(byte)
            }
        }
        throw failure()
    }

    private mutating func parseEscape(into utf8: inout [UInt8]) throws {
        guard let byte = peek() else { throw failure() }
        index += 1
        switch byte {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"):
            utf8.append(byte)
        case UInt8(ascii: "b"):
            utf8.append(0x08)
        case UInt8(ascii: "f"):
            utf8.append(0x0C)
        case UInt8(ascii: "n"):
            utf8.append(0x0A)
        case UInt8(ascii: "r"):
            utf8.append(0x0D)
        case UInt8(ascii: "t"):
            utf8.append(0x09)
        case UInt8(ascii: "u"):
            utf8.append(contentsOf: String(try parseEscapedScalar()).utf8)
        default:
            throw failure()
        }
    }

    private mutating func parseEscapedScalar() throws -> Character {
        let first = try parseHexQuad()
        if (0xD800..<0xDC00).contains(first),
           peek() == UInt8(ascii: "\\"),
           index + 1 < bytes.count,
           bytes[index + 1] == UInt8(ascii: "u")
        {
            let checkpoint = index
            index += 2
            let second = try parseHexQuad()
            if (0xDC00..<0xE000).contains(second) {
                let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                return Character(Unicode.Scalar(combined) ?? "\u{FFFD}")
            }
            index = checkpoint
        }
        return Character(Unicode.Scalar(first) ?? "\u{FFFD}")
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw failure() }
        var value: UInt32 = 0
        for byte in bytes[index..<(index + 4)] {
            guard let digit = Self.hexDigit(byte) else { throw failure() }
            value = value << 4 | digit
        }
        index += 4
        return value
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        if peek() == UInt8(ascii: "-") {
            index += 1
        }
        guard let first = peek() else { throw failure() }
        switch first {
        case UInt8(ascii: "0"):
            index += 1
        case UInt8(ascii: "1")...UInt8(ascii: "9"):
            skipDigits()
        default:
            throw failure()
        }
        if peek() == UInt8(ascii: ".") {
            index += 1
            guard skipDigits() > 0 else { throw failure() }
        }
        if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
            index += 1
            if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") {
                index += 1
            }
            guard skipDigits() > 0 else { throw failure() }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    @discardableResult
    private mutating func skipDigits() -> Int {
        let start = index
        while let byte = peek(), (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
            index += 1
        }
        return index - start
    }

    private mutating func expect(_ literal: String) throws {
        for expected in literal.utf8 {
            guard peek() == expected else { throw failure() }
            index += 1
        }
    }

    private mutating func skipWhitespace() {
        while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private func peek() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private func failure() -> OrderedJSONError {
        OrderedJSONError(offset: index)
    }

    private static func hexDigit(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }
}
