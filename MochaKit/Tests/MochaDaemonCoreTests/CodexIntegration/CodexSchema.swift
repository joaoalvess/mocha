import Foundation
@testable import MochaDaemonCore

struct CodexSchemaBundle: Sendable {
    static let fileName = "codex_app_server_protocol.schemas.json"

    let root: OrderedJSON

    init(directory: URL) throws {
        root = try OrderedJSON.parse(Data(contentsOf: directory.appending(path: Self.fileName)))
    }

    var surface: CodexSchemaSurface {
        CodexSchemaSurface(
            clientRequests: methods("ClientRequest"),
            clientNotifications: methods("ClientNotification"),
            serverRequests: methods("ServerRequest"),
            serverNotifications: methods("ServerNotification"),
            threadItemTypes: variants(resolve("#/definitions/v2/ThreadItem")?["oneOf"], key: "type")
        )
    }

    var serverMethods: Set<String> {
        Set(methods("ServerNotification") + methods("ServerRequest"))
    }

    func paramsSchema(of method: String) -> OrderedJSON? {
        ["ServerNotification", "ServerRequest", "ClientRequest"].lazy
            .compactMap { entry(in: $0, method: method)?["properties"]?["params"] }
            .first
    }

    func resultSchema(of method: String) -> OrderedJSON? {
        guard let params = entry(in: "ClientRequest", method: method)?["properties"]?["params"],
              let reference = Self.firstReference(in: params), reference.hasSuffix("Params") else { return nil }
        return resolve(String(reference.dropLast("Params".count)) + "Response")
    }

    func missingPaths(of value: OrderedJSON, in node: OrderedJSON, at path: String) -> [String] {
        switch value {
        case .object(let members):
            var candidates = shapes(of: node).filter(\.describesObject)
            guard !candidates.isEmpty else { return [] }
            if let type = value["type"]?.stringValue {
                let matching = candidates.filter { $0.discriminator?.contains(type) ?? true }
                guard !matching.isEmpty else { return ["\(path).type = \(type)"] }
                candidates = matching
            }
            return candidates.map { missingPaths(of: members, in: $0, at: path) }.min { $0.count < $1.count } ?? []
        case .array(let elements):
            guard let items = shapes(of: node).compactMap(\.items).first(where: { $0.members != nil }) else { return [] }
            return CodexPayloadShape.unique(elements.flatMap { missingPaths(of: $0, in: items, at: path + "[]") })
        default:
            return []
        }
    }

    private func missingPaths(of members: [OrderedJSON.Member], in shape: CodexSchemaShape, at path: String) -> [String] {
        guard shape.properties != nil || shape.additional != nil else { return [] }
        return members.flatMap { member -> [String] in
            let child = "\(path).\(member.key)"
            if let property = shape.properties?.last(where: { $0.key == member.key })?.value {
                return missingPaths(of: member.value, in: property, at: child)
            }
            switch shape.additional {
            case .some(.bool(true)):
                return []
            case .some(let schema) where schema.members != nil:
                return missingPaths(of: member.value, in: schema, at: child)
            default:
                return [child]
            }
        }
    }

    private func shapes(of node: OrderedJSON, depth: Int = 0) -> [CodexSchemaShape] {
        guard depth < 24 else { return [] }
        if let reference = node["$ref"]?.stringValue {
            return resolve(reference).map { shapes(of: $0, depth: depth + 1) } ?? []
        }
        let base = CodexSchemaShape(
            properties: node["properties"]?.members,
            additional: node["additionalProperties"],
            items: node["items"],
            types: Self.typeNames(node["type"]),
            discriminator: node["properties"]?["type"]?["enum"]?.arrayValue?.compactMap(\.stringValue)
        )
        guard let alternatives = (node["allOf"] ?? node["oneOf"] ?? node["anyOf"])?.arrayValue else { return [base] }
        return alternatives.flatMap { shapes(of: $0, depth: depth + 1) }.map { $0.adding(base) }
    }

    private func resolve(_ reference: String) -> OrderedJSON? {
        guard reference.hasPrefix("#/") else { return nil }
        return reference.dropFirst(2).split(separator: "/").reduce(Optional(root)) { $0?[String($1)] }
    }

    private func entry(in union: String, method: String) -> OrderedJSON? {
        resolve("#/definitions/\(union)")?["oneOf"]?.arrayValue?.first { Self.variant(of: $0, key: "method") == method }
    }

    private func methods(_ union: String) -> [String] {
        variants(resolve("#/definitions/\(union)")?["oneOf"], key: "method")
    }

    private func variants(_ alternatives: OrderedJSON?, key: String) -> [String] {
        (alternatives?.arrayValue ?? []).compactMap { Self.variant(of: $0, key: key) }.sorted()
    }

    private static func variant(of node: OrderedJSON, key: String) -> String? {
        node["properties"]?[key]?["enum"]?.arrayValue?.first?.stringValue
    }

    private static func firstReference(in node: OrderedJSON) -> String? {
        node["$ref"]?.stringValue ?? (node["anyOf"] ?? node["oneOf"])?.arrayValue?.lazy.compactMap { $0["$ref"]?.stringValue }.first
    }

    private static func typeNames(_ node: OrderedJSON?) -> [String] {
        node?.stringValue.map { [$0] } ?? node?.arrayValue?.compactMap(\.stringValue) ?? []
    }
}

struct CodexSchemaShape {
    var properties: [OrderedJSON.Member]?
    var additional: OrderedJSON?
    var items: OrderedJSON?
    var types: [String]
    var discriminator: [String]?

    var describesObject: Bool {
        properties != nil || additional != nil || types.contains("object")
    }

    func adding(_ base: CodexSchemaShape) -> CodexSchemaShape {
        CodexSchemaShape(
            properties: base.properties == nil && properties == nil ? nil : (base.properties ?? []) + (properties ?? []),
            additional: additional ?? base.additional,
            items: items ?? base.items,
            types: types.isEmpty ? base.types : types,
            discriminator: discriminator ?? base.discriminator
        )
    }
}

struct CodexSchemaSurface: Sendable, Equatable {
    var clientRequests: [String]
    var clientNotifications: [String]
    var serverRequests: [String]
    var serverNotifications: [String]
    var threadItemTypes: [String]

    var categories: [(name: String, values: [String])] {
        [
            ("clientRequests", clientRequests),
            ("clientNotifications", clientNotifications),
            ("serverRequests", serverRequests),
            ("serverNotifications", serverNotifications),
            ("threadItemTypes", threadItemTypes),
        ]
    }

    init(clientRequests: [String], clientNotifications: [String], serverRequests: [String], serverNotifications: [String], threadItemTypes: [String]) {
        self.clientRequests = clientRequests
        self.clientNotifications = clientNotifications
        self.serverRequests = serverRequests
        self.serverNotifications = serverNotifications
        self.threadItemTypes = threadItemTypes
    }

    init(json: OrderedJSON) {
        let values = { (key: String) in json[key]?.arrayValue?.compactMap(\.stringValue) ?? [] }
        self.init(
            clientRequests: values("clientRequests"),
            clientNotifications: values("clientNotifications"),
            serverRequests: values("serverRequests"),
            serverNotifications: values("serverNotifications"),
            threadItemTypes: values("threadItemTypes")
        )
    }

    var json: OrderedJSON {
        .object(categories.map { .init($0.name, .array($0.values.map(OrderedJSON.string))) })
    }
}

struct CodexSchemaSnapshot: Sendable {
    var codexVersion: String
    var stable: CodexSchemaSurface
    var experimental: CodexSchemaSurface

    init(codexVersion: String, stable: CodexSchemaSurface, experimental: CodexSchemaSurface) {
        self.codexVersion = codexVersion
        self.stable = stable
        self.experimental = experimental
    }

    init(contentsOf url: URL) throws {
        let json = try OrderedJSON.parse(Data(contentsOf: url))
        self.init(
            codexVersion: json["codexVersion"]?.stringValue ?? "?",
            stable: CodexSchemaSurface(json: json["stable"] ?? .null),
            experimental: CodexSchemaSurface(json: json["experimental"] ?? .null)
        )
    }

    func write(to url: URL) throws {
        let json = OrderedJSON.object([
            .init("codexVersion", .string(codexVersion)),
            .init("stable", stable.json),
            .init("experimental", experimental.json),
        ])
        try Data((json.prettyPrinted() + "\n").utf8).write(to: url, options: .atomic)
    }
}

enum CodexPayloadShape {
    static func missingKeys(of expected: OrderedJSON, in actual: OrderedJSON, at path: String) -> [String] {
        switch expected {
        case .object(let members):
            guard let actualMembers = actual.members else { return actual == .null ? [] : [path] }
            return members.flatMap { member -> [String] in
                let child = "\(path).\(member.key)"
                guard let value = actualMembers.last(where: { $0.key == member.key })?.value else { return [child] }
                return missingKeys(of: member.value, in: value, at: child)
            }
        case .array(let elements):
            let actualObjects = actual.arrayValue?.filter { $0.members != nil } ?? []
            guard !actualObjects.isEmpty else { return [] }
            return unique(elements.filter { $0.members != nil }.flatMap { element in
                actualObjects.map { missingKeys(of: element, in: $0, at: path + "[]") }.min { $0.count < $1.count } ?? []
            })
        default:
            return []
        }
    }

    static func isComparable(_ sample: OrderedJSON, with fixture: OrderedJSON) -> Bool {
        discriminators(of: fixture).allSatisfy { value(at: $0.path, in: sample)?.stringValue == $0.value }
    }

    static func unique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    private static func discriminators(of json: OrderedJSON, at path: [String] = []) -> [(path: [String], value: String)] {
        guard let members = json.members else { return [] }
        return members.flatMap { member -> [(path: [String], value: String)] in
            if member.key == "type", let value = member.value.stringValue { return [(path + ["type"], value)] }
            return discriminators(of: member.value, at: path + [member.key])
        }
    }

    private static func value(at path: [String], in json: OrderedJSON) -> OrderedJSON? {
        path.reduce(Optional(json)) { $0?[$1] }
    }
}

struct CodexFixture: Sendable {
    let name: String
    let method: String
    let isResponse: Bool
    let payload: OrderedJSON

    var label: String { isResponse ? "result" : "params" }

    static func all() throws -> [CodexFixture] {
        let directory = Fixtures.url("codex/events")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".json") }
            .sorted()
        let events = try names.map { name -> CodexFixture in
            let message = try OrderedJSON.parse(Fixtures.data("codex/events/\(name)"))
            if let method = message["method"]?.stringValue {
                return CodexFixture(name: name, method: method, isResponse: false, payload: message["params"] ?? .object([]))
            }
            let method = name.replacingOccurrences(of: ".response.json", with: "").replacingOccurrences(of: "-", with: "/")
            return CodexFixture(name: name, method: method, isResponse: true, payload: message["result"] ?? .null)
        }
        let rateLimits = try CodexFixture(
            name: "rate-limits.json",
            method: "account/rateLimits/read",
            isResponse: true,
            payload: OrderedJSON.parse(Fixtures.data("codex/rate-limits.json"))
        )
        return events + [rateLimits]
    }
}
