import SwiftUI

struct HomeCardFrame<Ring: View, Content: View>: View {
    var isWarning = false
    @ViewBuilder let ring: () -> Ring
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12.5)
            .padding(.bottom, 12)
            .padding(.leading, 68)
            .padding(.trailing, 44)
            .frame(minHeight: 65.3)
            .background(alignment: .leading) {
                ring()
                    .padding(.leading, 16)
            }
            .overlay(alignment: .trailing) {
                LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.3, color: Palette.textSecondary)
                    .frame(width: 12, height: 19)
                    .padding(.trailing, 17)
                    .accessibilityHidden(true)
            }
            .background(shape.fill(Palette.toolCard))
            .overlay {
                if isWarning {
                    shape.strokeBorder(Palette.dirty.opacity(0.3), lineWidth: 1)
                }
            }
            .contentShape(shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}

enum HomeCardTone {
    case normal
    case archived
    case offline
}

struct HomeCardTitle: View {
    let text: String
    var tone: HomeCardTone = .normal

    var body: some View {
        Text(text)
            .systemText(.cardTitle)
            .foregroundStyle(tone == .archived ? Palette.archivedTitle : Palette.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 21)
    }
}

struct HomeCardSubtitle: View {
    let text: String
    var isWarning = false

    var body: some View {
        Text(text)
            .systemText(.cardSubtitle)
            .foregroundStyle(isWarning ? Palette.dirty : Palette.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 21)
    }
}

struct HomeCardMeta: View {
    let workspace: String
    let time: String
    var tone: HomeCardTone = .normal

    var body: some View {
        HStack(spacing: 0) {
            Badge(text: workspace, tone: tone == .offline ? .offline : .ok)
            MetaSeparator()
            Text("Claude Code")
                .systemText(.cardMetaClaude)
                .foregroundStyle(tone == .offline ? Palette.offlineClaude : Palette.claude)
            MetaSeparator()
            Text(time)
                .systemText(.cardMetaTime)
                .foregroundStyle(Palette.textSecondary)
        }
        .lineLimit(1)
        .frame(height: 17.3)
    }
}

struct MetaSeparator: View {
    var body: some View {
        Circle()
            .fill(Palette.sepDot)
            .frame(width: 4, height: 4)
            .padding(.leading, 6.3)
            .padding(.trailing, 6.5)
            .accessibilityHidden(true)
    }
}

struct HomeCardContent: View {
    let title: String
    var subtitle: String?
    var subtitleIsWarning = false
    let workspace: String
    let time: String
    var tone: HomeCardTone = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeCardTitle(text: title, tone: tone)
            if let subtitle {
                HomeCardSubtitle(text: subtitle, isWarning: subtitleIsWarning && tone != .offline)
            }
            HomeCardMeta(workspace: workspace, time: time, tone: tone)
                .padding(.top, subtitle == nil ? 2.5 : 5.5)
        }
    }
}
