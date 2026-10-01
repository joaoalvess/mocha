import MochaClient
import MochaProtocol
import SwiftUI

struct SubagentHeaderBar: View {
    var provider: AgentProvider = .claude
    let title: String
    let subtitle: String
    let onBack: () -> Void
    let onPreviewTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SubagentHeaderButton(accessibilityLabel: "Voltar", action: onBack) {
                LineIconView(icon: .chevronRight, size: 15, strokeWidth: 2.6, color: Palette.glyphOnAccent)
                    .rotationEffect(.degrees(180))
            }
            .padding(.leading, 16)
            titleBlock
                .padding(.leading, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            SubagentHeaderButton(accessibilityLabel: "Preview web", action: onPreviewTap) {
                CompassNeedle()
                    .stroke(Palette.glyphOnAccent, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                    .frame(width: 8.5, height: 8.5)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
        }
        .frame(height: Metrics.headerHeight)
        .mochaGlass(.chat, in: Capsule())
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                LineIconView(icon: .agent, size: 15, strokeWidth: 2.1, color: provider == .codex ? Palette.textPrimary : Palette.claude)
                Text(title)
                    .font(Typography.headerTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 22)
            Text(subtitle)
                .font(Typography.headerSubtitle)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 16)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SubagentHeaderButton<Glyph: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Palette.headerButton)
                .frame(width: Metrics.headerButtonSize, height: Metrics.headerButtonSize)
                .overlay { glyph() }
                .frame(width: Metrics.headerButtonSize, height: Metrics.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SubagentStatePill: View {
    let status: SubagentStatus

    var body: some View {
        HStack(spacing: 9) {
            SubagentStateIcon(status: status)
            Text(SubagentText.statePill(status))
                .font(Typography.composer)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .frame(height: 44)
        .mochaGlass(.composer, in: Capsule())
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.composerHeight)
        .accessibilityElement(children: .combine)
    }
}

struct SubagentCompletedFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .chatText(.italic)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
