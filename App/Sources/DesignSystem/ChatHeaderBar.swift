import Foundation
import SwiftUI

enum ChatSubtitle {
    static let separator = " • "

    static func text(workspace: String, model: String?, branch: String?) -> String {
        [workspace, model.map(abbreviatedModel), branch]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    static func abbreviatedModel(_ model: String) -> String {
        var name = model
        if name.hasPrefix(claudePrefix) {
            name.removeFirst(claudePrefix.count)
        }
        if let dateSuffix = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name.removeSubrange(dateSuffix)
        }
        return name
    }

    private static let claudePrefix = "claude-"
}

struct ChatHeaderBar: View {
    let indicator: StatusIndicator
    let title: String
    let subtitle: String
    let onOpenDrawer: () -> Void

    var body: some View {
        HStack(spacing: Metrics.headerItemSpacing) {
            StatusDot(indicator: indicator)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Metrics.headerTitleSpacing) {
                    ClaudeMark(size: Metrics.claudeMarkHeaderSize)
                    Text(title)
                        .font(Typography.headerTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(subtitle)
                    .font(Typography.headerSubtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Metrics.headerButtonSpacing) {
                Color.clear
                    .frame(width: Metrics.headerButtonSize, height: Metrics.headerButtonSize)
                    .accessibilityHidden(true)
                DrawerButton(action: onOpenDrawer)
            }
        }
        .padding(.horizontal, Metrics.headerHorizontalPadding)
        .frame(height: Metrics.headerHeight)
        .mochaGlass(in: Capsule())
    }
}

struct DrawerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Palette.textSecondary)
                .frame(width: Metrics.headerButtonSize, height: Metrics.headerButtonSize)
                .overlay {
                    CompassNeedle()
                        .stroke(
                            Palette.glyphOnAccent,
                            style: StrokeStyle(lineWidth: Metrics.compassNeedleLineWidth, lineJoin: .round)
                        )
                        .frame(width: Metrics.compassNeedleSize, height: Metrics.compassNeedleSize)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir gaveta")
    }
}
