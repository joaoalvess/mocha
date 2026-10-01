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

enum MenuRowStyle {
    static let badgeSize: CGFloat = 40
    static let iconSize: CGFloat = 19
    static let iconStrokeWidth: CGFloat = 1.8
    static let rowHeight: CGFloat = 58
    static let detailRowHeight: CGFloat = 62
    static let rowSpacing: CGFloat = 14
    static let rowPadding: CGFloat = 12
    static let titleSize: CGFloat = 17
}

struct MenuIconBadge<Icon: View>: View {
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        icon()
            .frame(width: MenuRowStyle.badgeSize, height: MenuRowStyle.badgeSize)
            .background(Circle().fill(Palette.menuIconBadge))
            .overlay(Circle().strokeBorder(Palette.menuIconBadgeBorder, lineWidth: 0.6))
    }
}

struct SlashMenuRow: View {
    let action: SlashMenuAction
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MenuRowStyle.rowSpacing) {
                MenuIconBadge {
                    SlashMenuIconView(icon: action.icon, size: MenuRowStyle.iconSize, strokeWidth: MenuRowStyle.iconStrokeWidth, color: titleColor)
                }
                Text(action.title)
                    .font(Typography.mono(16, .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MenuRowStyle.rowPadding)
            .frame(height: MenuRowStyle.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(action.title)
    }

    private var titleColor: Color {
        action.isDestructive ? Palette.destructive : Palette.textPrimary
    }
}
