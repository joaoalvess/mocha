import SwiftUI

enum BadgeTone {
    case ok
    case warning
    case offline

    var background: Color {
        switch self {
        case .ok: Palette.badgeOk
        case .warning: Palette.badgeWarn
        case .offline: Palette.offlineBadge
        }
    }

    var foreground: Color {
        switch self {
        case .ok: Palette.statusOk
        case .warning: Palette.dirty
        case .offline: Palette.offlineBadgeText
        }
    }
}

struct Badge: View {
    let text: String
    var tone: BadgeTone = .ok

    var body: some View {
        Text(text)
            .systemText(.badge)
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 17.3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tone.background))
    }
}

struct SectionHeader: View {
    let title: String
    var topPadding: CGFloat = 12

    var body: some View {
        Text(title.uppercased())
            .systemText(.sectionHeader)
            .foregroundStyle(Palette.textSecondary)
            .frame(height: 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Palette.grabber)
            .frame(width: 34, height: 4.5)
            .padding(.top, 9)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
