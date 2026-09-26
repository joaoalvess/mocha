import CoreFoundation
import Foundation

enum JSONValue: Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    struct UnsupportedValue: Error {
        let typeName: String
    }

    init(data: Data) throws {
        try self.init(any: JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    init(any value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(try array.map(JSONValue.init(any:)))
        case let object as [String: Any]:
            self = .object(try object.mapValues(JSONValue.init(any:)))
        default:
            throw UnsupportedValue(typeName: String(describing: type(of: value)))
        }
    }

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): String(value)
        case .number(let value): String(value)
        case .string(let value): "\"\(value)\""
        case .array(let values): "[" + values.map(\.description).joined(separator: ",") + "]"
        case .object(let object):
            "{" + object.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value.description)" }.joined(separator: ",") + "}"
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }
}
