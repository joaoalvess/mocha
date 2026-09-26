import Foundation
import MochaProtocol

struct LineOutline: Sendable, Equatable {
    struct Block: Sendable, Equatable {
        var type: String?
        var id: String?
        var toolUseId: String?
        var isError = false
    }

    struct ToolResult: Sendable, Equatable {
        let toolUseId: String
        let isError: Bool
    }

    var type: String?
    var version: String?
    var timestamp: String?
    var isSidechain = false
    var isMeta = false
    var isCompactSummary = false
    var isApiErrorMessage = false
    var hasMessage = false
    var model: String?
    var blocks: [Block]?

    static func of(_ bytes: UnsafeRawBufferPointer) -> LineOutline? {
        var parser = JSONParser(bytes: bytes)
        do {
            parser.skipWhitespace()
            guard parser.position < bytes.count, bytes[parser.position] == UInt8(ascii: "{") else { return nil }
            let outline = try parser.lineOutline()
            parser.skipWhitespace()
            guard parser.position == bytes.count, outline.type != nil else { return nil }
            return outline
        } catch {
            return nil
        }
    }

    var date: Date? {
        guard !isSidechain else { return nil }
        return timestamp.flatMap(ProtocolDate.date(from:))
    }

    var toolResults: [ToolResult]? {
        guard type == "user", !isSidechain, !isMeta, !isCompactSummary, let blocks else { return nil }
        let results = blocks.filter { $0.type == "tool_result" }
        guard !results.isEmpty else { return nil }
        return results.compactMap { block in
            block.toolUseId.map { ToolResult(toolUseId: $0, isError: block.isError) }
        }
    }

    var toolUseIds: [String]? {
        guard type == "assistant", !isSidechain, hasMessage, !isApiErrorMessage, model != "<synthetic>" else { return nil }
        return (blocks ?? []).filter { $0.type == "tool_use" }.map { $0.id ?? "" }
    }
}

extension JSONParser {
    fileprivate typealias MemberReader = (inout JSONParser, String) throws(JSONParseError) -> Void

    fileprivate mutating func lineOutline() throws(JSONParseError) -> LineOutline {
        var outline = LineOutline()
        try readObject(depth: 1) { parser, key throws(JSONParseError) in
            switch key {
            case "type": outline.type = try parser.optionalString()
            case "version": outline.version = try parser.optionalString()
            case "timestamp": outline.timestamp = try parser.optionalString()
            case "isSidechain": outline.isSidechain = try parser.isTrueLiteral()
            case "isMeta": outline.isMeta = try parser.isTrueLiteral()
            case "isCompactSummary": outline.isCompactSummary = try parser.isTrueLiteral()
            case "isApiErrorMessage": outline.isApiErrorMessage = try parser.isTrueLiteral()
            case "message": try parser.readMessage(into: &outline)
            default: try parser.skipValue(depth: 1)
            }
        }
        return outline
    }

    private mutating func readMessage(into outline: inout LineOutline) throws(JSONParseError) {
        outline.hasMessage = false
        outline.model = nil
        outline.blocks = nil
        skipWhitespace()
        guard position < bytes.count, bytes[position] == UInt8(ascii: "{") else {
            try skipValue(depth: 1)
            return
        }
        outline.hasMessage = true
        var model: String?
        var blocks: [LineOutline.Block]?
        try readObject(depth: 2) { parser, key throws(JSONParseError) in
            switch key {
            case "model": model = try parser.optionalString()
            case "content": blocks = try parser.readBlocks()
            default: try parser.skipValue(depth: 2)
            }
        }
        outline.model = model
        outline.blocks = blocks
    }

    private mutating func readBlocks() throws(JSONParseError) -> [LineOutline.Block]? {
        skipWhitespace()
        guard position < bytes.count, bytes[position] == UInt8(ascii: "[") else {
            try skipValue(depth: 2)
            return nil
        }
        var blocks: [LineOutline.Block] = []
        position += 1
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
            position += 1
            return blocks
        }
        while true {
            skipWhitespace()
            if position < bytes.count, bytes[position] == UInt8(ascii: "{") {
                var block = LineOutline.Block()
                try readObject(depth: 4) { parser, key throws(JSONParseError) in
                    switch key {
                    case "type": block.type = try parser.optionalString()
                    case "id": block.id = try parser.optionalString()
                    case "tool_use_id": block.toolUseId = try parser.optionalString()
                    case "is_error": block.isError = try parser.isTrueLiteral()
                    default: try parser.skipValue(depth: 4)
                    }
                }
                blocks.append(block)
            } else {
                try skipValue(depth: 3)
                blocks.append(LineOutline.Block())
            }
            skipWhitespace()
            guard position < bytes.count else { throw failure() }
            switch bytes[position] {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "]"):
                position += 1
                return blocks
            default:
                throw failure()
            }
        }
    }

    private mutating func readObject(depth: Int, _ readMember: MemberReader) throws(JSONParseError) {
        guard depth < Self.maximumDepth else { throw failure() }
        position += 1
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
            position += 1
            return
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw failure() }
            let key = try parseString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw failure() }
            position += 1
            skipWhitespace()
            guard position < bytes.count else { throw failure() }
            try readMember(&self, key)
            skipWhitespace()
            guard position < bytes.count else { throw failure() }
            switch bytes[position] {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "}"):
                position += 1
                return
            default:
                throw failure()
            }
        }
    }

    private mutating func optionalString() throws(JSONParseError) -> String? {
        guard bytes[position] == UInt8(ascii: "\"") else {
            try skipValue(depth: 1)
            return nil
        }
        return try parseString()
    }

    private mutating func isTrueLiteral() throws(JSONParseError) -> Bool {
        guard bytes[position] == UInt8(ascii: "t") else {
            try skipValue(depth: 1)
            return false
        }
        try expectLiteral("true")
        return true
    }

    mutating func skipValue(depth: Int) throws(JSONParseError) {
        guard depth < Self.maximumDepth else { throw failure() }
        skipWhitespace()
        guard position < bytes.count else { throw failure() }
        switch bytes[position] {
        case UInt8(ascii: "{"):
            try skipContainer(closing: UInt8(ascii: "}"), depth: depth + 1, keyed: true)
        case UInt8(ascii: "["):
            try skipContainer(closing: UInt8(ascii: "]"), depth: depth + 1, keyed: false)
        case UInt8(ascii: "\""):
            try skipString()
        case UInt8(ascii: "t"):
            try expectLiteral("true")
        case UInt8(ascii: "f"):
            try expectLiteral("false")
        case UInt8(ascii: "n"):
            try expectLiteral("null")
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            _ = try parseNumber()
        default:
            throw failure()
        }
    }

    private mutating func skipContainer(closing: UInt8, depth: Int, keyed: Bool) throws(JSONParseError) {
        guard depth < Self.maximumDepth else { throw failure() }
        position += 1
        skipWhitespace()
        if position < bytes.count, bytes[position] == closing {
            position += 1
            return
        }
        while true {
            if keyed {
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw failure() }
                try skipString()
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw failure() }
                position += 1
            }
            try skipValue(depth: depth)
            skipWhitespace()
            guard position < bytes.count else { throw failure() }
            switch bytes[position] {
            case UInt8(ascii: ","):
                position += 1
            case closing:
                position += 1
                return
            default:
                throw failure()
            }
        }
    }

    private mutating func skipString() throws(JSONParseError) {
        position += 1
        while position < bytes.count {
            let byte = bytes[position]
            switch byte {
            case UInt8(ascii: "\""):
                position += 1
                return
            case UInt8(ascii: "\\"):
                position += 1
                guard position < bytes.count else { throw failure() }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"),
                     UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                    continue
                case UInt8(ascii: "u"):
                    _ = try parseHexQuad()
                default:
                    throw failure()
                }
            default:
                guard byte >= 0x20 else { throw failure() }
                position += 1
            }
        }
        throw failure()
    }
}
