import MochaProtocol
import SwiftUI

enum SlashMenuAction: CaseIterable, Identifiable {
    case compact
    case clear
    case context
    case cost
    case interrupt

    static let commands: [SlashMenuAction] = [.compact, .clear, .context, .cost]

    var id: Self { self }

    var command: String? {
        switch self {
        case .compact: "/compact"
        case .clear: "/clear"
        case .context: "/context"
        case .cost: "/cost"
        case .interrupt: nil
        }
    }

    var title: String {
        command ?? "Interromper (Esc)"
    }

    var detail: String? {
        switch self {
        case .compact: "Resumir a conversa"
        case .clear: "Começar do zero"
        case .context: "Uso da janela de contexto"
        case .cost: "Custo e tokens da sessão"
        case .interrupt: nil
        }
    }

    var icon: SlashMenuIcon {
        switch self {
        case .compact: .compress
        case .clear: .trash
        case .context: .pie
        case .cost: .dollar
        case .interrupt: .stopCircle
        }
    }

    var isDestructive: Bool {
        self == .interrupt
    }

    var needsConfirmation: Bool {
        self == .clear
    }

    func message(for agentId: AgentID) -> ClientMessage {
        guard let command else { return .interrupt(agentId: agentId) }
        return .slash(agentId: agentId, command: command)
    }

    static func matching(command: String) -> SlashMenuAction? {
        allCases.first { $0.command == command }
    }
}

enum SlashMenuStyle {
    static let background = Color(hex: 0x28282A, opacity: 0.97)
    static let border = Color(hex: 0xFFFFFF, opacity: 0.12)
    static let separator = Color(hex: 0xFFFFFF, opacity: 0.1)
    static let iconSize: CGFloat = 21
    static let iconStrokeWidth: CGFloat = 1.8
    static let rowSpacing: CGFloat = 14
    static let rowPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 7
    static let separatorMargin: CGFloat = 5
}

struct SlashMenu: View {
    let onSelect: (SlashMenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SlashMenuAction.commands) { action in
                SlashMenuRow(action: action) { onSelect(action) }
            }
            SlashMenuStyle.separator
                .frame(height: 1)
                .padding(.horizontal, SlashMenuStyle.rowPadding)
                .padding(.vertical, SlashMenuStyle.separatorMargin)
                .accessibilityHidden(true)
            SlashMenuRow(action: .interrupt) { onSelect(.interrupt) }
        }
        .padding(.vertical, SlashMenuStyle.rowVerticalPadding)
        .frame(width: AttachmentLayout.menuWidth, alignment: .leading)
        .background(menuShape.fill(SlashMenuStyle.background))
        .overlay(menuShape.strokeBorder(SlashMenuStyle.border, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comandos")
    }

    private var menuShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AttachmentLayout.menuRadius, style: .continuous)
    }
}

struct SlashMenuRow: View {
    let action: SlashMenuAction
    let onSelect: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 13

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SlashMenuStyle.rowSpacing) {
                SlashMenuIconView(icon: action.icon, size: SlashMenuStyle.iconSize, strokeWidth: SlashMenuStyle.iconStrokeWidth, color: tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(action.title)
                        .font(Typography.mono(15, .bold))
                        .foregroundStyle(tint)
                    if let detail = action.detail {
                        Text(detail)
                            .font(.system(size: detailSize))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SlashMenuStyle.rowPadding)
            .padding(.vertical, SlashMenuStyle.rowVerticalPadding)
            .frame(minHeight: AttachmentLayout.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel([action.title, action.detail].compactMap(\.self).joined(separator: ", "))
    }

    private var tint: Color {
        action.isDestructive ? Palette.destructive : Palette.textPrimary
    }
}
