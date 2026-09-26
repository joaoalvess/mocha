import Foundation

enum ToolResultPreview {
    static func preview(of content: JSONValue?) -> String? {
        guard let content else { return nil }
        let text: String
        switch content {
        case .string(let value):
            text = value
        case .array(let blocks):
            text = blocks.compactMap(blockText).joined(separator: "\n")
        default:
            return nil
        }
        return text.truncated(toCharacters: TextLimits.resultPreview)
    }

    static func answersPreview(of toolUseResult: JSONValue?) -> String? {
        guard let answers = toolUseResult?["answers"]?.objectValue else { return nil }
        let askedQuestions = toolUseResult?["questions"]?.arrayValue?.compactMap { $0["question"]?.stringValue } ?? []
        let orderedQuestions = askedQuestions + answers.members.map(\.key).filter { !askedQuestions.contains($0) }
        var seen = Set<String>()
        let lines = orderedQuestions.compactMap { question -> String? in
            guard seen.insert(question).inserted, let answer = answerText(answers[question]) else { return nil }
            return "\(question) → \(answer)"
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n").truncated(toCharacters: TextLimits.resultPreview)
    }

    private static func answerText(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text):
            return text
        case .array(let elements):
            let labels = elements.compactMap(\.stringValue)
            return labels.isEmpty ? nil : labels.joined(separator: ", ")
        default:
            return nil
        }
    }

    private static func blockText(_ block: JSONValue) -> String? {
        switch block["type"]?.stringValue {
        case "text": block["text"]?.stringValue
        case "image": "[imagem]"
        case "tool_reference": block["tool_name"]?.stringValue
        case "document": "[documento]"
        default: nil
        }
    }
}
