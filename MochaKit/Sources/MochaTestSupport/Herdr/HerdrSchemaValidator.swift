import Foundation

public struct HerdrSchemaValidator {
    public enum Section: String {
        case request
        case successResponse = "success_response"
        case errorResponse = "error_response"
        case event
        case subscriptionEvent = "subscription_event"
    }

    private let sections: [String: [String: Any]]

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let schemas = root["schemas"] as? [String: Any]
        else { throw CocoaError(.coderReadCorrupt) }
        var sections: [String: [String: Any]] = [:]
        for (name, value) in schemas {
            if let section = value as? [String: Any] {
                sections[name] = section
            }
        }
        self.sections = sections
    }

    public static func load() throws -> HerdrSchemaValidator {
        try HerdrSchemaValidator(data: HerdrFixtures.data("herdr-api.schema.json"))
    }

    public var requestMethods: Set<String> {
        Set(requestVariants.compactMap { variantConst($0, property: "method") })
    }

    public var subscriptionTypes: Set<String> {
        guard let subscription = definition("Subscription", section: Section.request.rawValue),
            let variants = subscription["oneOf"] as? [[String: Any]]
        else { return [] }
        return Set(variants.compactMap { variantConst($0, property: "type") })
    }

    public func requestViolations(_ line: Data, strict: Bool = true) -> [String] {
        guard let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return ["request is not a JSON object"]
        }
        var violations: [String] = []
        for key in request.keys where strict && !["id", "method", "params"].contains(key) {
            violations.append("unknown top-level field \(key)")
        }
        guard request["id"] is String else {
            return violations + ["id must be a string"]
        }
        guard let method = request["method"] as? String else {
            return violations + ["method missing"]
        }
        guard let params = request["params"] else {
            return violations + ["params missing in \(method)"]
        }
        guard let variant = requestVariants.first(where: { variantConst($0, property: "method") == method }),
            let properties = variant["properties"] as? [String: Any],
            let paramsSchema = properties["params"] as? [String: Any]
        else {
            return violations + ["unknown method \(method)"]
        }
        return violations + validate(params, against: paramsSchema, section: Section.request.rawValue, path: method, strict: strict)
    }

    public func violations(of json: Data, section: Section) -> [String] {
        guard let value = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]),
            let schema = sections[section.rawValue]
        else { return ["invalid JSON or unknown section"] }
        return validate(value, against: schema, section: section.rawValue, path: "$", strict: false)
    }

    private var requestVariants: [[String: Any]] {
        sections[Section.request.rawValue]?["oneOf"] as? [[String: Any]] ?? []
    }

    private func variantConst(_ variant: [String: Any], property: String) -> String? {
        ((variant["properties"] as? [String: Any])?[property] as? [String: Any])?["const"] as? String
    }

    private func definition(_ name: String, section: String) -> [String: Any]? {
        (sections[section]?["$defs"] as? [String: Any])?[name] as? [String: Any]
    }

    private func resolve(_ reference: String) -> (schema: [String: Any], section: String)? {
        let parts = reference.split(separator: "/").map(String.init)
        guard parts.count == 5, parts[0] == "#", parts[1] == "schemas", parts[3] == "$defs",
            let schema = definition(parts[4], section: parts[2])
        else { return nil }
        return (schema, parts[2])
    }

    private func validate(_ value: Any, against schema: [String: Any], section: String, path: String, strict: Bool) -> [String] {
        if let reference = schema["$ref"] as? String {
            guard let resolved = resolve(reference) else { return ["\(path): unresolved \(reference)"] }
            return validate(value, against: resolved.schema, section: resolved.section, path: path, strict: strict)
        }
        var violations: [String] = []
        if let variants = schema["oneOf"] as? [[String: Any]] ?? schema["anyOf"] as? [[String: Any]] {
            let results = variants.map { validate(value, against: $0, section: section, path: path, strict: strict) }
            if !results.contains(where: \.isEmpty) {
                let closest = results.min { $0.count < $1.count } ?? []
                violations.append("\(path): no variant matched (closest: \(closest.joined(separator: "; ")))")
            }
        }
        if let constant = schema["const"], !Self.equal(constant, value) {
            violations.append("\(path): expected const \(constant)")
        }
        if let options = schema["enum"] as? [Any], !options.contains(where: { Self.equal($0, value) }) {
            violations.append("\(path): value not in enum")
        }
        if let type = schema["type"] {
            let allowed = (type as? [String]) ?? [type as? String].compactMap { $0 }
            if !allowed.contains(where: { Self.matches(value, type: $0) }) {
                violations.append("\(path): expected \(allowed.joined(separator: "|"))")
                return violations
            }
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for required in schema["required"] as? [String] ?? [] where object[required] == nil {
                violations.append("\(path): missing \(required)")
            }
            for (key, propertyValue) in object {
                if let propertySchema = properties[key] as? [String: Any] {
                    violations += validate(propertyValue, against: propertySchema, section: section, path: "\(path).\(key)", strict: strict)
                } else if let additional = schema["additionalProperties"] as? [String: Any] {
                    violations += validate(propertyValue, against: additional, section: section, path: "\(path).\(key)", strict: strict)
                } else if (schema["additionalProperties"] as? Bool) == false
                    || (strict && schema["oneOf"] == nil && schema["anyOf"] == nil)
                {
                    violations.append("\(path): unknown field \(key)")
                }
            }
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            for (index, element) in array.enumerated() {
                violations += validate(element, against: items, section: section, path: "\(path)[\(index)]", strict: strict)
            }
        }
        return violations
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "object": value is [String: Any]
        case "array": value is [Any]
        case "string": value is String
        case "boolean": isBoolean(value)
        case "integer": (value as? NSNumber).map { !isBoolean($0) && $0.doubleValue.rounded() == $0.doubleValue } ?? false
        case "number": (value as? NSNumber).map { !isBoolean($0) } ?? false
        case "null": value is NSNull
        default: true
        }
    }

    private static func equal(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case (let left as String, let right as String): left == right
        case (let left as NSNumber, let right as NSNumber): isBoolean(left) == isBoolean(right) && left == right
        case (is NSNull, is NSNull): true
        default: false
        }
    }
}
