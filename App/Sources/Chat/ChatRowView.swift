import MochaClient
import MochaProtocol
import SwiftUI

struct ChatRowView: View {
    let row: ChatRow
    let model: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    var onOpenSubagent: (String) -> Void = { _ in }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch row.content {
        case .userPrompt(let text, let imagePaths):
            if imagePaths.isEmpty {
                UserBubble(text: text)
            } else {
                UserBubble(text: text) {
                    ChatImageStrip(paths: imagePaths, alignment: .trailing)
                }
            }
        case .slashCommand(let label, let output):
            SlashCommandRow(label: label, output: output, isExpanded: isExpanded, onToggle: onToggle)
        case .sessionStart(let date):
            ChatNoticeText(text: SessionStartNotice.text(at: date, model: model))
        case .markdown(let markdown, let imagePaths):
            if imagePaths.isEmpty {
                MarkdownView(markdown: markdown)
            } else {
                VStack(alignment: .leading, spacing: ChatImageLayout.contentSpacing) {
                    MarkdownView(markdown: markdown)
                    ChatImageStrip(paths: imagePaths, alignment: .leading)
                }
            }
        case .thinking(let run):
            ThinkingRow(run: run, isExpanded: isExpanded, onToggle: onToggle)
        case .tools(let group):
            ToolGroupRow(group: group, isExpanded: isExpanded, onToggle: onToggle)
        case .turnFooter(let durationMs):
            Text("Brewed for \(TurnDuration.text(milliseconds: durationMs))")
                .chatText(.italic)
                .foregroundStyle(Palette.textSecondary)
        case .recap(let text):
            Text("\(Text("Recap:").bold()) \(text)")
                .chatText(.italic)
                .foregroundStyle(Palette.textSecondary)
        case .notice(let text):
            ChatNoticeText(text: text)
        case .subagent(let call):
            SubagentCard(call: call, onOpen: onOpenSubagent)
        case .workflow(let call):
            WorkflowCard(call: call, isExpanded: isExpanded, onToggle: onToggle, onOpen: onOpenSubagent)
        case .task(let text):
            TaskCard(text: text, isExpanded: isExpanded, onToggle: onToggle)
        }
    }
}

struct ChatNoticeText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.mono(12, relativeTo: .caption))
            .linePitch(16, size: 12)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

enum SessionStartNotice {
    static func text(at date: Date, model: String?) -> String {
        let parts = ["Sessão nova", date.formatted(timeStyle), model.map(ModelName.abbreviated)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private static var timeStyle: Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .current,
            calendar: .current
        )
    }
}

struct ThinkingRow: View {
    let run: ThinkingRun
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Text(label)
            .chatText(.italic)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(isExpanded ? nil : 1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if run.text != nil { onToggle() }
            }
            .accessibilityAddTraits(run.text == nil ? [] : .isButton)
    }

    private var label: String {
        run.text.map { "Pensou: " + $0 } ?? "Pensou"
    }
}

struct ToolGroupRow: View {
    let group: ToolGroup
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ChatImageLayout.contentSpacing) {
            card
            if !group.imagePaths.isEmpty {
                ChatImageStrip(paths: group.imagePaths, alignment: .leading)
            }
        }
    }

    private var card: some View {
        Button(action: onToggle) {
            ToolCallCard(
                icon: group.icon,
                name: group.displayName,
                count: group.count,
                summary: group.summary,
                status: group.status,
                isExpanded: isExpanded
            ) {
                ForEach(group.calls, id: \.toolUseId) { call in
                    let input = ToolGrouping.input(for: call)
                    ToolCallDetailBox(input: input.text, showsPrompt: input.isShellCommand, output: call.resultPreview)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Recolhe o card" : "Mostra a entrada e o resultado")
    }
}

struct SlashCommandRow: View {
    let label: String
    let output: String?
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            SlashChip(command: label)
                .contentShape(Rectangle())
                .onTapGesture {
                    if output != nil { onToggle() }
                }
                .accessibilityAddTraits(output == nil ? [] : .isButton)
            if isExpanded, let output {
                Text(output)
                    .font(Typography.toolCard)
                    .linePitch(18, size: Typography.toolCardSize)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(Palette.toolCard))
            }
        }
    }
}
