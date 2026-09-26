import Foundation

enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var objectValue: JSONObject? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        guard case .number(let lexeme) = self else { return nil }
        if let value = Int(lexeme) { return value }
        guard let value = Double(lexeme), value.isFinite, abs(value) < Double(Int.max) else { return nil }
        return Int(value)
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    var isTrue: Bool {
        boolValue == true
    }
}

struct JSONObject: Sendable, Equatable {
    struct Member: Sendable, Equatable {
        let key: String
        let value: JSONValue
    }

    let members: [Member]

    subscript(key: String) -> JSONValue? {
        members.last { $0.key == key }?.value
    }
}

extension JSONValue {
    func serialized() -> String {
        var output = ""
        write(into: &output)
        return output
    }

    private func write(into output: inout String) {
        switch self {
        case .null:
            output.append("null")
        case .bool(let value):
            output.append(value ? "true" : "false")
        case .number(let lexeme):
            output.append(lexeme)
        case .string(let value):
            Self.writeString(value, into: &output)
        case .array(let elements):
            output.append("[")
            for (index, element) in elements.enumerated() {
                if index > 0 { output.append(",") }
                element.write(into: &output)
            }
            output.append("]")
        case .object(let object):
            output.append("{")
            for (index, member) in object.members.enumerated() {
                if index > 0 { output.append(",") }
                Self.writeString(member.key, into: &output)
                output.append(":")
                member.value.write(into: &output)
            }
            output.append("}")
        }
    }

    private static let hexDigits = Array("0123456789abcdef")

    private static func writeString(_ value: String, into output: inout String) {
        output.append("\"")
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output.append("\\\"")
            case "\\": output.append("\\\\")
            case "\n": output.append("\\n")
            case "\r": output.append("\\r")
            case "\t": output.append("\\t")
            case "\u{08}": output.append("\\b")
            case "\u{0C}": output.append("\\f")
            default:
                if scalar.value < 0x20 {
                    output.append("\\u00")
                    output.append(hexDigits[Int(scalar.value >> 4)])
                    output.append(hexDigits[Int(scalar.value & 0xF)])
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output.append("\"")
    }
}
