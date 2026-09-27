import Foundation

public struct WorkflowScriptPhase: Sendable, Hashable {
    public var title: String
    public var detail: String?

    public init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

public struct WorkflowScriptMeta: Sendable, Hashable {
    public var name: String?
    public var phases: [WorkflowScriptPhase]

    public init(name: String?, phases: [WorkflowScriptPhase]) {
        self.name = name
        self.phases = phases
    }

    public static func parse(_ script: String) -> WorkflowScriptMeta? {
        var scanner = ScriptScanner(Array(script.utf8))
        guard scanner.seekMetaObject() else { return nil }
        return scanner.metaObject()
    }
}

private struct ScriptScanner {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    private static let declaration = Array("export const meta".utf8)

    mutating func seekMetaObject() -> Bool {
        var start = 0
        while let found = find(Self.declaration, from: start) {
            position = found + Self.declaration.count
            start = found + 1
            guard position >= bytes.count || !isIdentifierByte(bytes[position]) else { continue }
            skipTrivia()
            guard consume(UInt8(ascii: "=")) else { continue }
            skipTrivia()
            if peek == UInt8(ascii: "{") { return true }
        }
        return false
    }

    mutating func metaObject() -> WorkflowScriptMeta? {
        var name: String?
        var phases: [WorkflowScriptPhase] = []
        let parsed = forEachProperty { scanner, key in
            switch key {
            case "name":
                guard let value = scanner.stringLiteral() else { return false }
                name = value
                return true
            case "phases":
                guard let value = scanner.phaseArray() else { return false }
                phases = value
                return true
            default:
                return scanner.skipValue()
            }
        }
        guard parsed else { return nil }
        return WorkflowScriptMeta(name: name, phases: phases)
    }

    private mutating func phaseArray() -> [WorkflowScriptPhase]? {
        guard consume(UInt8(ascii: "[")) else { return nil }
        var phases: [WorkflowScriptPhase] = []
        while true {
            skipTrivia()
            if consume(UInt8(ascii: "]")) { return phases }
            guard let phase = phaseObject() else { return nil }
            phases.append(phase)
            skipTrivia()
            if consume(UInt8(ascii: ",")) { continue }
            guard consume(UInt8(ascii: "]")) else { return nil }
            return phases
        }
    }

    private mutating func phaseObject() -> WorkflowScriptPhase? {
        guard peek == UInt8(ascii: "{") else { return nil }
        var title: String?
        var detail: String?
        let parsed = forEachProperty { scanner, key in
            switch key {
            case "title":
                guard let value = scanner.stringLiteral() else { return false }
                title = value
                return true
            case "detail":
                guard let value = scanner.stringLiteral() else { return false }
                detail = value
                return true
            default:
                return scanner.skipValue()
            }
        }
        guard parsed, let title else { return nil }
        return WorkflowScriptPhase(title: title, detail: detail)
    }

    private mutating func forEachProperty(_ body: (inout ScriptScanner, String) -> Bool) -> Bool {
        guard consume(UInt8(ascii: "{")) else { return false }
        while true {
            skipTrivia()
            if consume(UInt8(ascii: "}")) { return true }
            guard let key = propertyKey() else { return false }
            skipTrivia()
            guard consume(UInt8(ascii: ":")) else { return false }
            skipTrivia()
            guard body(&self, key) else { return false }
            skipTrivia()
            if consume(UInt8(ascii: ",")) { continue }
            return consume(UInt8(ascii: "}"))
        }
    }

    private mutating func propertyKey() -> String? {
        guard let byte = peek else { return nil }
        if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
            return stringLiteral()
        }
        let start = position
        while let next = peek, isIdentifierByte(next) {
            position += 1
        }
        guard position > start else { return nil }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    private mutating func stringLiteral() -> String? {
        guard let quote = peek,
              quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") || quote == UInt8(ascii: "`") else {
            return nil
        }
        position += 1
        var output: [UInt8] = []
        while let byte = peek {
            position += 1
            if byte == quote {
                return String(decoding: output, as: UTF8.self)
            }
            if quote == UInt8(ascii: "`"), byte == UInt8(ascii: "$"), peek == UInt8(ascii: "{") {
                return nil
            }
            if quote != UInt8(ascii: "`"), byte == 0x0A {
                return nil
            }
            guard byte == UInt8(ascii: "\\") else {
                output.append(byte)
                continue
            }
            guard let escaped = peek else { return nil }
            position += 1
            switch escaped {
            case UInt8(ascii: "n"): output.append(0x0A)
            case UInt8(ascii: "t"): output.append(0x09)
            case UInt8(ascii: "r"): output.append(0x0D)
            case 0x0A: break
            default: output.append(escaped)
            }
        }
        return nil
    }

    private mutating func skipValue() -> Bool {
        var depth = 0
        while let byte = peek {
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                guard stringLiteral() != nil else { return false }
                continue
            case UInt8(ascii: "`"):
                guard skipTemplate() else { return false }
                continue
            case UInt8(ascii: "/") where next == UInt8(ascii: "/") || next == UInt8(ascii: "*"):
                skipTrivia()
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["), UInt8(ascii: "("):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"), UInt8(ascii: ")"):
                if depth == 0 { return true }
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 0 { return true }
            default:
                break
            }
            position += 1
        }
        return false
    }

    private mutating func skipTemplate() -> Bool {
        position += 1
        while let byte = peek {
            position += 1
            switch byte {
            case UInt8(ascii: "\\"):
                position += 1
            case UInt8(ascii: "`"):
                return true
            case UInt8(ascii: "$") where peek == UInt8(ascii: "{"):
                position += 1
                guard skipValue(), consume(UInt8(ascii: "}")) else { return false }
            default:
                break
            }
        }
        return false
    }

    private mutating func skipTrivia() {
        while let byte = peek {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                position += 1
            } else if byte == UInt8(ascii: "/"), next == UInt8(ascii: "/") {
                while let current = peek, current != 0x0A {
                    position += 1
                }
            } else if byte == UInt8(ascii: "/"), next == UInt8(ascii: "*") {
                position += 2
                while position < bytes.count, !(bytes[position] == UInt8(ascii: "*") && next == UInt8(ascii: "/")) {
                    position += 1
                }
                position = min(bytes.count, position + 2)
            } else {
                return
            }
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        position += 1
        return true
    }

    private var peek: UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    private var next: UInt8? {
        position + 1 < bytes.count ? bytes[position + 1] : nil
    }

    private func isIdentifierByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || byte == UInt8(ascii: "_")
            || byte == UInt8(ascii: "$")
    }

    private func find(_ needle: [UInt8], from start: Int) -> Int? {
        guard needle.count <= bytes.count else { return nil }
        var index = start
        while index + needle.count <= bytes.count {
            if bytes[index] == needle[0], Array(bytes[index..<(index + needle.count)]) == needle {
                return index
            }
            index += 1
        }
        return nil
    }
}
