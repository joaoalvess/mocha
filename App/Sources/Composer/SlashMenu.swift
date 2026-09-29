import MochaProtocol
import SwiftUI

enum SlashMenuAction: CaseIterable, Identifiable {
    case compact
    case clear

    var id: Self { self }

    var command: String {
        switch self {
        case .compact: "/compact"
        case .clear: "/clear"
        }
    }

    var title: String {
        command
    }

    var icon: SlashMenuIcon {
        switch self {
        case .compact: .compress
        case .clear: .trash
        }
    }

    var needsConfirmation: Bool {
        self == .clear
    }

    var isDestructive: Bool {
        self == .clear
    }

    func message(for agentId: AgentID) -> ClientMessage {
        .slash(agentId: agentId, command: command)
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

struct SlashMenuRow: View {
    let action: SlashMenuAction
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SlashMenuStyle.rowSpacing) {
                SlashMenuIconView(icon: action.icon, size: SlashMenuStyle.iconSize, strokeWidth: SlashMenuStyle.iconStrokeWidth, color: titleColor)
                Text(action.title)
                    .font(Typography.mono(15, .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SlashMenuStyle.rowPadding)
            .padding(.vertical, SlashMenuStyle.rowVerticalPadding)
            .frame(minHeight: AttachmentLayout.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(action.title)
    }

    private var titleColor: Color {
        action.isDestructive ? Palette.destructive : Palette.textPrimary
    }
}
