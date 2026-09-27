import Foundation
import Markdown
import MochaClient
import MochaProtocol

struct ChatRow: Identifiable, Equatable {
    enum Content: Equatable {
        case userPrompt(String)
        case slashCommand(label: String, output: String?)
        case sessionStart(Date)
        case markdown(String)
        case thinking(ThinkingRun)
        case tools(ToolGroup)
        case turnFooter(durationMs: Int)
        case recap(String)
        case notice(String)
        case subagent(SubagentCall)
        case workflow(WorkflowCall)
        case task(String)
    }

    let id: String
    let content: Content
    var spacingBelow: CGFloat
    var toolRowBelowId: String?

    var signpostKind: StaticString {
        switch content {
        case .userPrompt: "userPrompt"
        case .slashCommand: "slashCommand"
        case .sessionStart: "sessionStart"
        case .markdown: "markdown"
        case .thinking: "thinking"
        case .tools: "tools"
        case .turnFooter: "turnFooter"
        case .recap: "recap"
        case .notice: "notice"
        case .subagent: "subagent"
        case .workflow: "workflow"
        case .task: "task"
        }
    }

    var isToolRow: Bool {
        switch content {
        case .tools, .subagent, .workflow: true
        default: false
        }
    }

    var isExpandedByDefault: Bool {
        if case .workflow(let call) = content { call.status == .running } else { false }
    }
}

enum ChatRowSpacing {
    static let standard: CGFloat = Metrics.listItemSpacing
    static let afterHeading: CGFloat = 8
    static let betweenTools: CGFloat = 6
}

@MainActor
final class ChatRowBuilder {
    private struct CachedChunks {
        let markdown: String
        let chunks: [MarkdownChunk]
    }

    private var chunkCache: [String: CachedChunks] = [:]

    func rows(for items: [ChatItem]) -> [ChatRow] {
        var rows: [ChatRow] = []
        rows.reserveCapacity(items.count)
        for entry in ToolGrouping.entries(from: items) {
            switch entry {
            case .tools(let group):
                rows.append(ChatRow(id: group.id, content: .tools(group), spacingBelow: ChatRowSpacing.standard))
            case .thinking(let run):
                rows.append(ChatRow(id: run.id, content: .thinking(run), spacingBelow: ChatRowSpacing.standard))
            case .item(let item):
                append(item, to: &rows)
            }
        }
        for index in rows.indices.dropLast() where rows[index].isToolRow && rows[index + 1].isToolRow {
            rows[index].toolRowBelowId = rows[index + 1].id
        }
        return rows
    }

    private func append(_ item: ChatItem, to rows: inout [ChatRow]) {
        switch item.kind {
        case .userPrompt(let text, let imageCount):
            rows.append(ChatRow(id: item.id, content: .userPrompt(PromptImages.bubbleText(text, imageCount: imageCount)), spacingBelow: ChatRowSpacing.standard))
        case .slashCommand(let name, let args, let output):
            let label = Self.commandLabel(name: name, args: args)
            rows.append(ChatRow(id: item.id, content: .slashCommand(label: label, output: output), spacingBelow: ChatRowSpacing.standard))
            if name == Self.clearCommand {
                rows.append(ChatRow(id: item.id + "#start", content: .sessionStart(item.at), spacingBelow: ChatRowSpacing.standard))
            }
        case .assistantText(let markdown):
            for (index, chunk) in chunks(for: item.id, markdown: markdown).enumerated() {
                let spacing = chunk.endsWithHeading ? ChatRowSpacing.afterHeading : ChatRowSpacing.standard
                rows.append(ChatRow(id: index == 0 ? item.id : "\(item.id)#\(index)", content: .markdown(chunk.markdown), spacingBelow: spacing))
            }
        case .turnFooter(let durationMs):
            rows.append(ChatRow(id: item.id, content: .turnFooter(durationMs: durationMs), spacingBelow: ChatRowSpacing.standard))
        case .recap(let text):
            rows.append(ChatRow(id: item.id, content: .recap(text), spacingBelow: ChatRowSpacing.standard))
        case .notice(let text):
            rows.append(ChatRow(id: item.id, content: .notice(text), spacingBelow: ChatRowSpacing.standard))
        case .subagent(let call):
            rows.append(ChatRow(id: item.id, content: .subagent(call), spacingBelow: ChatRowSpacing.standard))
        case .workflow(let call):
            rows.append(ChatRow(id: item.id, content: .workflow(call), spacingBelow: ChatRowSpacing.standard))
        case .task(let text):
            rows.append(ChatRow(id: item.id, content: .task(text), spacingBelow: ChatRowSpacing.standard))
        case .thinking, .toolCall, .unsupported:
            break
        }
    }

    private func chunks(for itemId: String, markdown: String) -> [MarkdownChunk] {
        if let cached = chunkCache[itemId], cached.markdown == markdown {
            return cached.chunks
        }
        let chunks = MarkdownChunker.chunks(of: markdown)
        chunkCache[itemId] = CachedChunks(markdown: markdown, chunks: chunks)
        return chunks
    }

    static func commandLabel(name: String, args: String) -> String {
        let args = args.trimmingCharacters(in: .whitespacesAndNewlines)
        return args.isEmpty ? name : name + " " + args
    }

    private static let clearCommand = "/clear"
}

struct MarkdownChunk: Equatable {
    let markdown: String
    let endsWithHeading: Bool
}

enum MarkdownChunker {
    static let splitThreshold = 1_500

    static func chunks(of markdown: String) -> [MarkdownChunk] {
        let whole = [MarkdownChunk(markdown: markdown, endsWithHeading: false)]
        guard markdown.utf8.count > splitThreshold else { return whole }
        let starts = Document(parsing: markdown).children.compactMap { child -> (line: Int, isHeading: Bool)? in
            guard let range = child.range else { return nil }
            return (range.lowerBound.line - 1, child is Heading)
        }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard starts.count > 1, starts.allSatisfy({ (0..<lines.count).contains($0.line) }) else { return whole }
        var chunks: [MarkdownChunk] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].line : lines.count
            guard start.line < end else { return whole }
            let text = trimmingTrailingWhitespace(lines[start.line..<end].joined(separator: "\n"))
            guard !text.isEmpty else { continue }
            chunks.append(MarkdownChunk(markdown: text, endsWithHeading: start.isHeading))
        }
        return chunks.isEmpty ? whole : chunks
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        var text = Substring(text)
        while let last = text.last, last.isWhitespace {
            text.removeLast()
        }
        return String(text)
    }
}
