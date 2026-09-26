import MochaProtocol
import SwiftUI

struct ToolCallCard<Details: View>: View {
    let name: String
    let count: Int
    let summary: String
    let status: ToolStatus
    let isExpanded: Bool
    @ViewBuilder let details: () -> Details

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolCallRow(name: name, count: count, summary: summary, status: status)
            if isExpanded {
                details()
                    .padding(.horizontal, Metrics.toolCardLeadingPadding)
                    .padding(.bottom, Metrics.toolCardLeadingPadding)
            }
        }
        .background(shape.fill(Palette.toolCard))
        .overlay {
            if isExpanded {
                shape.strokeBorder(Palette.toolCardBorder, lineWidth: 1)
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.toolCardExpandedCornerRadius, style: .circular)
    }
}

extension ToolCallCard where Details == EmptyView {
    init(name: String, count: Int, summary: String, status: ToolStatus) {
        self.init(name: name, count: count, summary: summary, status: status, isExpanded: false) {
            EmptyView()
        }
    }
}

struct ToolCallRow: View {
    let name: String
    let count: Int
    let summary: String
    let status: ToolStatus

    var body: some View {
        HStack(spacing: 0) {
            prefix
                .fixedSize()
            Text(summary)
                .font(Typography.toolCard)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Metrics.toolCardTrailingPadding)
            ToolStatusIcon(status: status)
        }
        .padding(.leading, Metrics.toolCardLeadingPadding)
        .padding(.trailing, Metrics.toolCardTrailingPadding)
        .frame(height: Metrics.toolCardHeight)
        .accessibilityElement(children: .combine)
    }

    private var prefix: some View {
        HStack(spacing: Metrics.toolCardIconSpacing) {
            PromptIcon(width: Metrics.toolCardIconWidth, lineWidth: 1, color: Palette.textSecondary)
            prefixText
        }
        .font(Typography.toolCard)
    }

    private var prefixText: Text {
        let nameText = Text(name).font(Typography.toolCardName).foregroundStyle(Palette.textPrimary)
        guard count > 1 else {
            return Text(" \(nameText) ")
        }
        let countText = Text("×\(count)").foregroundStyle(Palette.textSecondary)
        return Text(" \(nameText) \(countText) ")
    }
}

struct ToolStatusIcon: View {
    let status: ToolStatus

    var body: some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(Palette.textSecondary)
                .accessibilityLabel("Rodando")
        case .succeeded:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityLabel("Concluída")
        case .failed:
            Image(systemName: "xmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.error)
                .accessibilityLabel("Falhou")
        }
    }
}
