import Foundation

struct JSONParseError: Error, Sendable, Equatable {
    let position: Int
}

struct JSONParser {
    private static let maximumDepth = 512

    private let bytes: UnsafeRawBufferPointer
    private var position = 0

    private init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    static func parse(_ bytes: UnsafeRawBufferPointer) throws(JSONParseError) -> JSONValue {
        var parser = JSONParser(bytes: bytes)
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.position == bytes.count else { throw parser.failure() }
        return value
    }

    static func parse(_ bytes: [UInt8]) throws(JSONParseError) -> JSONValue {
        let result: Result<JSONValue, JSONParseError> = bytes.withUnsafeBytes { buffer in
            Result { () throws(JSONParseError) -> JSONValue in try parse(buffer) }
        }
        return try result.get()
    }

    private func failure() -> JSONParseError {
        JSONParseError(position: position)
    }

    private mutating func skipWhitespace() {
        while position < bytes.count {
            switch bytes[position] {
            case 0x20, 0x09, 0x0A, 0x0D: position += 1
            default: return
            }
        }
    }

    private mutating func parseValue(depth: Int) throws(JSONParseError) -> JSONValue {
        guard depth < Self.maximumDepth else { throw failure() }
        skipWhitespace()
        guard position < bytes.count else { throw failure() }
        switch bytes[position] {
        case UInt8(ascii: "{"): return .object(try parseObject(depth: depth + 1))
        case UInt8(ascii: "["): return .array(try parseArray(depth: depth + 1))
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"):
            try expectLiteral("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expectLiteral("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expectLiteral("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try parseNumber())
        default:
            throw failure()
        }
    }

    private mutating func expectLiteral(_ literal: StaticString) throws(JSONParseError) {
        let count = literal.utf8CodeUnitCount
        guard position + count <= bytes.count else { throw failure() }
        let pointer = literal.utf8Start
        for offset in 0..<count where bytes[position + offset] != pointer[offset] {
            throw failure()
        }
        position += count
    }

    private mutating func parseObject(depth: Int) throws(JSONParseError) -> JSONObject {
        position += 1
        var members: [JSONObject.Member] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
            position += 1
            return JSONObject(members: members)
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw failure() }
            let key = try parseString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw failure() }
            position += 1
            let value = try parseValue(depth: depth)
            members.append(JSONObject.Member(key: key, value: value))
            skipWhitespace()
            guard position < bytes.count else { throw failure() }
            switch bytes[position] {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "}"):
                position += 1
                return JSONObject(members: members)
            default:
                throw failure()
            }
        }
    }

    private mutating func parseArray(depth: Int) throws(JSONParseError) -> [JSONValue] {
        position += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
            position += 1
            return elements
        }
        while true {
            elements.append(try parseValue(depth: depth))
            skipWhitespace()
            guard position < bytes.count else { throw failure() }
            switch bytes[position] {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "]"):
                position += 1
                return elements
            default:
                throw failure()
            }
        }
    }

    private mutating func parseString() throws(JSONParseError) -> String {
        position += 1
        let start = position
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\"") {
                let value = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<position]), as: UTF8.self)
                position += 1
                return value
            }
            if byte == UInt8(ascii: "\\") {
                return try parseEscapedString(from: start)
            }
            guard byte >= 0x20 else { throw failure() }
            position += 1
        }
        throw failure()
    }

    private mutating func parseEscapedString(from start: Int) throws(JSONParseError) -> String {
        var buffer = [UInt8](UnsafeRawBufferPointer(rebasing: bytes[start..<position]))
        while position < bytes.count {
            let byte = bytes[position]
            switch byte {
            case UInt8(ascii: "\""):
                position += 1
                return String(decoding: buffer, as: UTF8.self)
            case UInt8(ascii: "\\"):
                position += 1
                guard position < bytes.count else { throw failure() }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""): buffer.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"): buffer.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"): buffer.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"): appendUTF8(of: try parseUnicodeEscape(), to: &buffer)
                default: throw failure()
                }
            default:
                guard byte >= 0x20 else { throw failure() }
                buffer.append(byte)
                position += 1
            }
        }
        throw failure()
    }

    private mutating func parseUnicodeEscape() throws(JSONParseError) -> Unicode.Scalar {
        let first = try parseHexQuad()
        switch first {
        case 0xD800...0xDBFF:
            let savedPosition = position
            if position + 1 < bytes.count,
               bytes[position] == UInt8(ascii: "\\"),
               bytes[position + 1] == UInt8(ascii: "u") {
                position += 2
                let second = try parseHexQuad()
                if (0xDC00...0xDFFF).contains(second) {
                    let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                    return Unicode.Scalar(combined) ?? "\u{FFFD}"
                }
                position = savedPosition
            }
            return "\u{FFFD}"
        case 0xDC00...0xDFFF:
            return "\u{FFFD}"
        default:
            return Unicode.Scalar(first) ?? "\u{FFFD}"
        }
    }

    private mutating func parseHexQuad() throws(JSONParseError) -> UInt32 {
        guard position + 4 <= bytes.count else { throw failure() }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[position]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw failure()
            }
            value = value << 4 | digit
            position += 1
        }
        return value
    }

    private func appendUTF8(of scalar: Unicode.Scalar, to buffer: inout [UInt8]) {
        UTF8.encode(scalar) { buffer.append($0) }
    }

    private mutating func parseNumber() throws(JSONParseError) -> String {
        let start = position
        if bytes[position] == UInt8(ascii: "-") { position += 1 }
        guard position < bytes.count else { throw failure() }
        if bytes[position] == UInt8(ascii: "0") {
            position += 1
        } else {
            guard consumeDigits() > 0 else { throw failure() }
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
            position += 1
            guard consumeDigits() > 0 else { throw failure() }
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
            position += 1
            if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") {
                position += 1
            }
            guard consumeDigits() > 0 else { throw failure() }
        }
        return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<position]), as: UTF8.self)
    }

    private mutating func consumeDigits() -> Int {
        let start = position
        while position < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position]) {
            position += 1
        }
        return position - start
    }
}
