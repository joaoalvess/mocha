import Foundation

public enum OrderedJSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([OrderedJSON])
    case object([Member])

    public struct Member: Sendable, Equatable {
        public var key: String
        public var value: OrderedJSON

        public init(_ key: String, _ value: OrderedJSON) {
            self.key = key
            self.value = value
        }
    }

    public static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = OrderedJSONParser(bytes: Array(data))
        return try parser.parseDocument()
    }

    public subscript(key: String) -> OrderedJSON? {
        members?.last { $0.key == key }?.value
    }

    public var members: [Member]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public var arrayValue: [OrderedJSON]? {
        if case .array(let elements) = self { return elements }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public func setting(_ key: String, to value: OrderedJSON?) -> OrderedJSON {
        guard var members else { return self }
        let firstIndex = members.firstIndex { $0.key == key }
        members.removeAll { $0.key == key }
        guard let value else { return .object(members) }
        members.insert(Member(key, value), at: min(firstIndex ?? members.count, members.count))
        return .object(members)
    }

    public func prettyPrinted() -> String {
        var output = ""
        write(into: &output, depth: 0)
        return output
    }

    public func compactSerialized() -> String {
        var output = ""
        writeCompact(into: &output)
        return output
    }

    private func writeCompact(into output: inout String) {
        switch self {
        case .null, .bool, .number, .string:
            write(into: &output, depth: 0)
        case .array(let elements):
            output += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { output += "," }
                element.writeCompact(into: &output)
            }
            output += "]"
        case .object(let members):
            output += "{"
            for (index, member) in members.enumerated() {
                if index > 0 { output += "," }
                Self.writeString(member.key, into: &output)
                output += ":"
                member.value.writeCompact(into: &output)
            }
            output += "}"
        }
    }

    private func write(into output: inout String, depth: Int) {
        switch self {
        case .null:
            output += "null"
        case .bool(let value):
            output += value ? "true" : "false"
        case .number(let lexeme):
            output += lexeme
        case .string(let value):
            Self.writeString(value, into: &output)
        case .array(let elements):
            guard !elements.isEmpty else {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, element) in elements.enumerated() {
                output += Self.indent(depth + 1)
                element.write(into: &output, depth: depth + 1)
                output += index == elements.count - 1 ? "\n" : ",\n"
            }
            output += Self.indent(depth) + "]"
        case .object(let members):
            guard !members.isEmpty else {
                output += "{}"
                return
            }
            output += "{\n"
            for (index, member) in members.enumerated() {
                output += Self.indent(depth + 1)
                Self.writeString(member.key, into: &output)
                output += ": "
                member.value.write(into: &output, depth: depth + 1)
                output += index == members.count - 1 ? "\n" : ",\n"
            }
            output += Self.indent(depth) + "}"
        }
    }

    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: depth)
    }

    private static func writeString(_ value: String, into output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{00}"..."\u{1F}":
                let hex = String(scalar.value, radix: 16)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

public struct OrderedJSONError: Error, Sendable, Equatable {
    public let offset: Int
}
