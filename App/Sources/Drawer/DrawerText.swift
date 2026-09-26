import SwiftUI

enum DrawerTextStyle {
    case search
    case sectionHeader
    case row
    case workspaceName
    case branch
    case dirtyMark
    case recentTitle
    case recentSubtitle
    case hint

    var size: CGFloat {
        switch self {
        case .search: 16
        case .sectionHeader: 11
        case .row, .workspaceName, .recentTitle: 15
        case .branch, .recentSubtitle: 13
        case .dirtyMark: 21
        case .hint: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .sectionHeader: .semibold
        case .workspaceName: .medium
        case .search, .row, .branch, .dirtyMark, .recentTitle, .recentSubtitle, .hint: .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .sectionHeader: 0.3
        default: 0
        }
    }

    var relativeStyle: Font.TextStyle {
        switch self {
        case .search, .row, .workspaceName, .dirtyMark, .recentTitle: .body
        case .sectionHeader: .caption2
        case .branch, .recentSubtitle: .footnote
        case .hint: .caption
        }
    }
}

private struct DrawerTextModifier: ViewModifier {
    let style: DrawerTextStyle
    @ScaledMetric private var size: CGFloat

    init(style: DrawerTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight))
            .tracking(style.tracking)
    }
}

extension View {
    func drawerText(_ style: DrawerTextStyle) -> some View {
        modifier(DrawerTextModifier(style: style))
    }
}
