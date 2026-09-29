import MochaClient
import MochaProtocol
import SwiftUI

enum ChatSubtitle {
    static let separator = " • "

    static func text(workspace: String, model: String?, effort: String? = nil, branch: String?) -> String {
        [workspace, model.map { ModelName.withEffort($0, effort: effort) }, branch]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}

struct ChatHeaderBar: View {
    var provider: AgentProvider = .claude
    let indicator: StatusIndicator
    let title: String
    let subtitle: String
    var contextLeftPercent: Int?
    var ringStyle: ContextRingStyle = .ready
    var onStatusTap: () -> Void = {}
    var onTitleTap: () -> Void = {}
    var onTitleLongPress: () -> Void = {}
    var onPreviewTap: (() -> Void)?

    private static let ringScale: CGFloat = 0.55
    private static let ringSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onStatusTap) {
                StatusDot(indicator: indicator)
                    .frame(width: 44, height: Metrics.headerHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
            .accessibilityLabel("Abrir gaveta")
            .accessibilityValue(indicator.accessibilityLabel)
            titleBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTitleTap)
                .onLongPressGesture(perform: onTitleLongPress)
                .padding(.leading, -2.5)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Abre o seletor de modelo")
                .accessibilityAction(.default, onTitleTap)
                .accessibilityAction(named: "Ver detalhes", onTitleLongPress)
            HStack(spacing: 8) {
                HeaderRoundButton(accessibilityLabel: "Git", isEnabled: false, action: {}) {
                    LineIconView(icon: .branch, size: 16, strokeWidth: 2.1, color: Palette.glyphOnAccent)
                }
                HeaderRoundButton(accessibilityLabel: "Preview web", isEnabled: onPreviewTap != nil, action: { onPreviewTap?() }) {
                    CompassNeedle()
                        .stroke(Palette.glyphOnAccent, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                        .frame(width: 8.5, height: 8.5)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
        }
        .frame(height: Metrics.headerHeight)
        .mochaGlass(.chat, in: Capsule())
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6.5) {
                ProviderMark(provider: provider, size: Metrics.claudeMarkHeaderSize)
                Text(title)
                    .font(Typography.headerTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 22)
                if let contextLeftPercent {
                    ContextRing(percent: contextLeftPercent, style: ringStyle)
                        .scaleEffect(Self.ringScale)
                        .frame(width: Self.ringSize, height: Self.ringSize)
                        .padding(.top, 2)
                }
            }
            Text(subtitle)
                .font(Typography.headerSubtitle)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 16)
        }
    }
}

private struct HeaderRoundButton<Glyph: View>: View {
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Palette.headerButton)
                .frame(width: Metrics.headerButtonSize, height: Metrics.headerButtonSize)
                .overlay { glyph().foregroundStyle(Palette.glyphOnAccent) }
                .frame(width: Metrics.headerButtonSize, height: Metrics.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .compositingGroup()
        .opacity(isEnabled ? 1 : 0.32)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
