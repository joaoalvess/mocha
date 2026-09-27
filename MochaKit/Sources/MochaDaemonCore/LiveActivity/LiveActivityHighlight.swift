import Foundation
import MochaProtocol
import MochaTranscript

extension LiveActivityContentState.Highlight {
    static let previewLimit = PushAlertText.bodyLimit
    static let activityLimit = PushAlertText.summaryLimit

    static let droppedToFitBudget: [@Sendable (inout Self) -> Void] = [
        { $0.preview = nil },
        { $0.activity = nil },
        { $0.tabTitle = nil },
        { $0.model = nil },
        { $0.contextLeftPercent = nil },
    ]

    init(_ agent: AgentSummary, status: AgentStatus, since: Date, tabTitle: String?, titleLimit: Int, showsProgress: Bool) {
        self.init(
            agentId: agent.id,
            title: String(agent.title.prefix(titleLimit)),
            workspaceLabel: agent.workspaceLabel,
            status: status.rawValue,
            since: since,
            tabTitle: tabTitle.flatMap { Self.nonBlank(String($0.prefix(titleLimit))) },
            model: agent.model,
            contextLeftPercent: agent.contextLeftPercent,
            preview: showsProgress ? Self.preview(of: agent.preview) : nil,
            activity: showsProgress ? Self.activity(of: agent.activity) : nil
        )
    }

    static func preview(of message: MessagePreview?) -> String? {
        guard let message, message.author == .assistant else { return nil }
        return nonBlank(PlainText.preview(fromMarkdown: message.text, limit: previewLimit))
    }

    static func activity(of tool: ToolActivity?) -> String? {
        guard let tool, tool.status == .running else { return nil }
        let summary = tool.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = summary.isEmpty ? tool.toolName : "\(tool.toolName): \(summary)"
        return nonBlank(String(text.prefix(activityLimit)))
    }

    private static func nonBlank(_ text: String) -> String? {
        text.allSatisfy(\.isWhitespace) ? nil : text
    }
}
