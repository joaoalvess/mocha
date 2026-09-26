import Foundation
import MochaProtocol

extension AgentSummary {
    mutating func refreshHomeFields(from items: [ChatItem]) {
        let lastPrompt = items.last { if case .userPrompt = $0.kind { true } else { false } }
        let lastFooter = items.last { if case .turnFooter = $0.kind { true } else { false } }
        if let archivedAt, let promptAt = lastPrompt?.at, promptAt > archivedAt {
            self.archivedAt = nil
        }
        lastActivityAt = items.last?.at ?? lastActivityAt
        preview = items.lazy.reversed().compactMap(\.messagePreview).first
        activity = items.toolActivity
        sessionStartedAt = items.first?.at
        turnStartedAt = lastPrompt?.at
        turnEndedAt = lastFooter?.at
    }
}

extension ChatItem {
    var messagePreview: MessagePreview? {
        switch kind {
        case .userPrompt(let text, let imageCount):
            let plain = DemoPlainText.preview(fromMarkdown: text)
            return MessagePreview(author: .user, text: plain.isEmpty && imageCount > 0 ? DemoPlainText.imageOnly : plain)
        case .assistantText(let markdown):
            return MessagePreview(author: .assistant, text: DemoPlainText.preview(fromMarkdown: markdown))
        default:
            return nil
        }
    }

    var toolCallValue: ToolCall? {
        guard case .toolCall(let toolCall) = kind else { return nil }
        return toolCall
    }
}

extension [ChatItem] {
    var toolActivity: ToolActivity? {
        let toolCalls = lazy.reversed().compactMap(\.toolCallValue)
        guard let toolCall = toolCalls.first(where: { $0.status == .running }) ?? toolCalls.first else { return nil }
        return ToolActivity(toolName: toolCall.name, summary: toolCall.summary, status: toolCall.status)
    }
}

enum DemoPlainText {
    static let maximumLength = 200
    static let imageOnly = "[imagem]"

    static func preview(fromMarkdown markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("```") else { return nil }
            return trimmed.replacing(/^(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+\.\s+)/, with: "")
        }
        let text = lines.joined(separator: " ")
            .replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
            .replacing("`", with: "")
            .replacing("**", with: "")
            .replacing("__", with: "")
            .replacing("*", with: "")
        return String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maximumLength))
    }
}
