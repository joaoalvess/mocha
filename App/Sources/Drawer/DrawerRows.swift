import MochaClient
import MochaProtocol
import SwiftUI

enum DrawerLayout {
    static let topBarHeight: CGFloat = 44
    static let topBarInset: CGFloat = 8
    static let horizontalMargin: CGFloat = 16
    static let rowLeading: CGFloat = 16
    static let rowTrailing: CGFloat = 16.3
    static let levelIndent: CGFloat = 17.3
    static let treeRowHeight: CGFloat = 36
    static let recentRowHeight: CGFloat = 56
    static let sectionHeaderLeading: CGFloat = 20.3
    static let sectionHeaderTop: CGFloat = 17
    static let sectionHeaderHeight: CGFloat = 16
    static let treeTopGap: CGFloat = 3
    static let recentTopGap: CGFloat = 4
    static let blockedDotSize: CGFloat = 8
    static let branchLeading: CGFloat = 7.7
    static let claudeMarkScale: CGFloat = 1.18
    static let newTabButtonSize: CGFloat = 28
    static let newTabButtonTrailing: CGFloat = 2
    static let newTabIconSize: CGFloat = 14
    static let newTabIconStroke: CGFloat = 2
    static let newTabHitOutset: CGFloat = 4

    static func chevronInset(level: Int) -> CGFloat {
        9.7 + CGFloat(level) * levelIndent
    }

    static func workspaceNameInset(level: Int) -> CGFloat {
        27.3 + CGFloat(level) * levelIndent
    }

    static func tabIconInset(level: Int) -> CGFloat {
        26.7 + CGFloat(level) * levelIndent
    }

    static func tabTextInset(level: Int) -> CGFloat {
        48.3 + CGFloat(level) * levelIndent
    }
}

struct DrawerWorkspaceRowView: View {
    let row: DrawerWorkspaceRow
    let isCreatingTab: Bool
    let action: () -> Void
    let onNewTab: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(row.label)
                    .drawerText(.workspaceName)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let branch = row.branch {
                    DrawerBranchLabel(branch: branch)
                        .padding(.leading, DrawerLayout.branchLeading)
                }
                if row.isDirty {
                    Text(verbatim: "*")
                        .drawerText(.dirtyMark)
                        .foregroundStyle(Palette.dirty)
                        .offset(y: 4)
                        .padding(.leading, 7)
                        .accessibilityLabel("Alterações pendentes")
                }
            }
            .padding(.leading, DrawerLayout.workspaceNameInset(level: row.level))
            .padding(.trailing, DrawerLayout.newTabButtonTrailing + DrawerLayout.newTabButtonSize)
            .frame(maxWidth: .infinity, minHeight: DrawerLayout.treeRowHeight, alignment: .leading)
            .overlay(alignment: .leading) {
                LineIconView(icon: .chevronRight, size: 10, strokeWidth: 2.2, color: Palette.textSecondary)
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    .offset(y: 0.5)
                    .padding(.leading, DrawerLayout.chevronInset(level: row.level))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.isExpanded ? "Expandido" : "Recolhido")
        .overlay(alignment: .trailing) {
            DrawerNewTabButton(workspaceLabel: row.label, isCreating: isCreatingTab, action: onNewTab)
                .padding(.trailing, DrawerLayout.newTabButtonTrailing)
        }
    }
}

struct DrawerNewTabButton: View {
    let workspaceLabel: String
    let isCreating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.textSecondary)
                } else {
                    DrawerIconView(
                        icon: .plus,
                        size: DrawerLayout.newTabIconSize,
                        strokeWidth: DrawerLayout.newTabIconStroke,
                        color: Palette.textSecondary
                    )
                }
            }
            .frame(width: DrawerLayout.newTabButtonSize, height: DrawerLayout.newTabButtonSize)
            .contentShape(Rectangle().inset(by: -DrawerLayout.newTabHitOutset))
        }
        .buttonStyle(.pressable)
        .disabled(isCreating)
        .accessibilityLabel(isCreating ? "Abrindo tab em \(workspaceLabel)" : "Nova tab em \(workspaceLabel)")
    }
}

struct DrawerBranchLabel: View {
    let branch: String

    var body: some View {
        HStack(spacing: 3) {
            LineIconView(icon: .branch, size: 12.5, strokeWidth: 1.8, color: Palette.textSecondary)
            Text(branch)
                .drawerText(.branch)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("branch \(branch)")
    }
}

enum DrawerTabIcon: Equatable {
    case claude(isWorking: Bool)
    case codex(isWorking: Bool)
    case otherAgent(isWorking: Bool)
    case shell
}

struct DrawerTabRowView: View {
    let icon: DrawerTabIcon
    let title: String
    var branch: String?
    let level: Int
    var isBlocked = false
    var isSelected = false
    var statusLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(title)
                    .drawerText(.row)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let branch {
                    DrawerBranchLabel(branch: branch)
                        .padding(.leading, DrawerLayout.branchLeading)
                }
            }
            .padding(.leading, DrawerLayout.tabTextInset(level: level))
            .padding(.trailing, 28)
            .frame(maxWidth: .infinity, minHeight: DrawerLayout.treeRowHeight, alignment: .leading)
            .overlay(alignment: .leading) {
                DrawerTabIconView(icon: icon, size: Metrics.claudeMarkDrawerSize)
                    .padding(.leading, DrawerLayout.tabIconInset(level: level))
            }
            .overlay(alignment: .trailing) {
                if isBlocked {
                    DrawerBlockedDot()
                        .padding(.trailing, 12)
                }
            }
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.selectedRow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusLabel ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DrawerRecentRowView: View {
    let row: DrawerRecentRow
    let now: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                DrawerTabIconView(icon: row.agent.kind == "codex" ? .codex(isWorking: row.agent.status == .working) : .claude(isWorking: row.agent.status == .working), size: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.agent.title)
                        .drawerText(.recentTitle)
                        .systemLinePitch(20, size: DrawerTextStyle.recentTitle.size)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(row.subtitle(now: now))
                        .drawerText(.recentSubtitle)
                        .systemLinePitch(17, size: DrawerTextStyle.recentSubtitle.size)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.agent.status == .blocked {
                    DrawerBlockedDot()
                }
            }
            .padding(.leading, 10.7)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: DrawerLayout.recentRowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.selectedRow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DrawerBlockedDot: View {
    var body: some View {
        Circle()
            .fill(Palette.dirty)
            .frame(width: DrawerLayout.blockedDotSize, height: DrawerLayout.blockedDotSize)
            .accessibilityHidden(true)
    }
}

struct DrawerTabIconView: View {
    let icon: DrawerTabIcon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .claude(let isWorking):
            ClaudeMark(size: size * DrawerLayout.claudeMarkScale)
                .frame(width: size, height: size)
                .modifier(DrawerWorkingPulse(isWorking: isWorking, color: Palette.claude))
        case .codex(let isWorking):
            ProviderMark(provider: .codex, size: size)
                .modifier(DrawerWorkingPulse(isWorking: isWorking, color: Palette.textPrimary))
        case .otherAgent(let isWorking):
            LineIconView(icon: .sparkles, size: size, strokeWidth: 2.2, color: Palette.textSecondary)
                .modifier(DrawerWorkingPulse(isWorking: isWorking, color: Palette.textSecondary))
        case .shell:
            LineIconView(icon: .prompt, size: size, strokeWidth: 2.2, color: Palette.textSecondary)
        }
    }
}

private struct DrawerWorkingPulse: ViewModifier {
    let isWorking: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if !isWorking {
            content
        } else if reduceMotion {
            glowing(content)
        } else {
            glowing(content)
                .phaseAnimator([false, true]) { view, isDimmed in
                    view
                        .opacity(isDimmed ? 0.55 : 1)
                        .scaleEffect(isDimmed ? 0.82 : 1)
                } animation: { _ in
                    .easeInOut(duration: 0.7)
                }
        }
    }

    private func glowing(_ content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.95), radius: 1.5)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}
