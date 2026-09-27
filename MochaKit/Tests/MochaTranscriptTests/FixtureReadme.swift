import Foundation
import MochaProtocol

struct FixtureReadmeRow {
    let fileName: String
    let expectedItems: [String]
    let finalMeta: [String: String?]
}

enum FixtureReadme {
    static func rows() throws -> [String: FixtureReadmeRow] {
        let text = try String(contentsOf: Fixtures.url("transcripts/README.md"), encoding: .utf8)
        var rows: [String: FixtureReadmeRow] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 5, let fileName = firstCode(in: cells[1]) else { continue }
            let items = cells[3].components(separatedBy: " → ").map { $0.trimmingCharacters(in: .whitespaces) }
            rows[fileName] = FixtureReadmeRow(fileName: fileName, expectedItems: items, finalMeta: metaPairs(in: cells[4]))
        }
        return rows
    }

    private static func firstCode(in cell: String) -> String? {
        guard let open = cell.firstIndex(of: "`") else { return nil }
        let rest = cell[cell.index(after: open)...]
        guard let close = rest.firstIndex(of: "`") else { return nil }
        return String(rest[..<close])
    }

    private static func metaPairs(in cell: String) -> [String: String?] {
        var pairs: [String: String?] = [:]
        for key in ["título", "modelo", "branch", "modo"] {
            guard let keyRange = cell.range(of: "\(key) `") else { continue }
            let rest = cell[keyRange.upperBound...]
            guard let close = rest.firstIndex(of: "`") else { continue }
            let value = String(rest[..<close])
            pairs[key] = value == "nil" ? String?.none : value
        }
        return pairs
    }

    static func mismatch(token: String, item: ChatItem) -> String? {
        let base: String
        let qualifier: String?
        if let open = token.firstIndex(of: "("), token.hasSuffix(")") {
            base = String(token[..<open])
            qualifier = String(token[token.index(after: open)..<token.index(before: token.endIndex)])
        } else {
            base = token
            qualifier = nil
        }
        guard base == item.kind.type else { return "esperado \(token), veio \(item.kind.type)" }
        switch item.kind {
        case .userPrompt(_, let imageCount):
            let expectedImages = qualifier.flatMap { $0.hasPrefix("img=") ? Int($0.dropFirst(4)) : nil } ?? 0
            return imageCount == expectedImages ? nil : "imagens: esperado \(expectedImages), veio \(imageCount)"
        case .thinking(let text):
            switch qualifier {
            case "vazio": return text == nil ? nil : "thinking deveria ser vazio"
            case "texto": return text != nil ? nil : "thinking deveria ter texto"
            default: return nil
            }
        case .toolCall(let call):
            guard let qualifier else { return nil }
            let parts = qualifier.split(separator: ":").map(String.init)
            guard parts.count == 2 else { return "qualificador inválido \(qualifier)" }
            if call.name != parts[0] { return "ferramenta: esperado \(parts[0]), veio \(call.name)" }
            if call.status.rawValue != parts[1] { return "status de \(call.name): esperado \(parts[1]), veio \(call.status.rawValue)" }
            return nil
        case .subagent(let call):
            guard let qualifier else { return nil }
            let parts = qualifier.split(separator: ":").map(String.init)
            guard parts.count == 2 else { return "qualificador inválido \(qualifier)" }
            if call.agentType != parts[0] { return "tipo: esperado \(parts[0]), veio \(call.agentType)" }
            if call.status.rawValue != parts[1] { return "status de \(call.description): esperado \(parts[1]), veio \(call.status.rawValue)" }
            return nil
        case .workflow(let call):
            guard let qualifier else { return nil }
            return call.status.rawValue == qualifier ? nil : "status do workflow: esperado \(qualifier), veio \(call.status.rawValue)"
        case .notice(let text):
            guard let qualifier, qualifier.hasPrefix("\""), qualifier.hasSuffix("\""), qualifier.count >= 2 else { return nil }
            let expected = String(qualifier.dropFirst().dropLast())
            return text == expected ? nil : "notice: esperado \(expected), veio \(text)"
        case .slashCommand(let name, let args, let output):
            guard let qualifier else { return nil }
            if let marker = qualifier.range(of: ", saída \"") {
                let expectedName = String(qualifier[..<marker.lowerBound])
                let expectedOutput = String(qualifier[marker.upperBound...].dropLast())
                if name != expectedName { return "comando: esperado \(expectedName), veio \(name)" }
                return output == expectedOutput ? nil : "saída de \(name): esperado \(expectedOutput), veio \(output ?? "nil")"
            }
            let hasOutput = qualifier.hasSuffix("+saída")
            let words = qualifier.replacingOccurrences(of: "+saída", with: "")
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1)
                .map(String.init)
            let expectedName = words.first ?? ""
            let expectedArgs = words.count > 1 ? words[1] : ""
            if name != expectedName { return "comando: esperado \(expectedName), veio \(name)" }
            if args != expectedArgs { return "args de \(name): esperado \(expectedArgs), veio \(args)" }
            if hasOutput != (output != nil) { return "saída de \(name): esperada \(hasOutput), veio \(output ?? "nil")" }
            return nil
        default:
            return nil
        }
    }
}
