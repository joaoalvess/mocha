import SwiftUI

enum MonoFace: String, CaseIterable {
    case regular = "JetBrainsMono-Regular"
    case italic = "JetBrainsMono-Italic"
    case bold = "JetBrainsMono-Bold"
    case boldItalic = "JetBrainsMono-BoldItalic"
}

enum Typography {
    static let monoFamily = "JetBrains Mono"
    static let monoLineHeightRatio: CGFloat = 1.32

    static let chatBodySize: CGFloat = 14.67
    static let chatLinePitch: CGFloat = 20
    static let headerTitleSize: CGFloat = 16
    static let headerSubtitleSize: CGFloat = 12
    static let toolCardSize: CGFloat = 12
    static let composerSize: CGFloat = 14

    static let systemLineHeightRatio: CGFloat = 1.193

    static func lineSpacing(size: CGFloat, pitch: CGFloat) -> CGFloat {
        max(0, pitch - size * monoLineHeightRatio)
    }

    static func systemLineSpacing(size: CGFloat, pitch: CGFloat) -> CGFloat {
        max(0, pitch - size * systemLineHeightRatio)
    }

    static func mono(_ size: CGFloat, _ face: MonoFace = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    static let headerTitle = mono(headerTitleSize, .bold, relativeTo: .headline)
    static let headerSubtitle = mono(headerSubtitleSize, relativeTo: .caption)
    static let toolCard = mono(toolCardSize, relativeTo: .caption)
    static let toolCardName = mono(toolCardSize, .bold, relativeTo: .caption)
    static let slashChip = mono(toolCardSize, .bold, relativeTo: .caption)
    static let composer = mono(composerSize)
    static let pendingLabel = mono(11, relativeTo: .caption2)
    static let usageLabel = mono(11, relativeTo: .caption2)
    static let usageValue = mono(12, relativeTo: .caption)
}

enum SystemTextStyle {
    case sectionHeader
    case cardTitle
    case cardSubtitle
    case badge
    case stateBadge
    case cardMetaClaude
    case cardMetaTime
    case ringNumber
    case sheetTitle
    case sheetRowLabel
    case sheetRowCompactLabel
    case sheetRowAction
    case sheetNote
    case body

    var size: CGFloat {
        switch self {
        case .sectionHeader: 12
        case .cardTitle: 16
        case .cardSubtitle: 14
        case .badge, .stateBadge: 11
        case .cardMetaClaude, .cardMetaTime: 12
        case .ringNumber: 11
        case .sheetTitle: 17
        case .sheetRowLabel, .sheetRowAction: 15
        case .sheetRowCompactLabel: 14
        case .sheetNote: 12
        case .body: 15
        }
    }

    var weight: Font.Weight {
        switch self {
        case .cardTitle, .badge, .ringNumber: .semibold
        case .cardMetaClaude, .sheetRowAction: .medium
        case .sheetTitle, .stateBadge: .bold
        case .sectionHeader, .cardSubtitle, .cardMetaTime, .sheetRowLabel, .sheetRowCompactLabel, .sheetNote, .body: .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .sectionHeader: 0.25
        case .badge: 0.1
        case .stateBadge: 0.9
        case .ringNumber: -0.1
        default: 0
        }
    }

    var relativeStyle: Font.TextStyle {
        switch self {
        case .sectionHeader, .cardMetaClaude, .cardMetaTime, .sheetNote: .caption
        case .badge, .stateBadge, .ringNumber: .caption2
        case .cardTitle, .sheetTitle: .headline
        case .cardSubtitle, .sheetRowCompactLabel: .subheadline
        case .sheetRowLabel, .sheetRowAction, .body: .body
        }
    }
}

private struct SystemTextStyleModifier: ViewModifier {
    let style: SystemTextStyle
    @ScaledMetric private var size: CGFloat

    init(style: SystemTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight))
            .tracking(style.tracking)
    }
}

private struct MonoTextModifier: ViewModifier {
    let face: MonoFace
    let hasPitch: Bool
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var pitch: CGFloat

    init(size: CGFloat, face: MonoFace, relativeTo style: Font.TextStyle, pitch: CGFloat?) {
        self.face = face
        hasPitch = pitch != nil
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        _pitch = ScaledMetric(wrappedValue: pitch ?? size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        if hasPitch {
            content
                .font(.custom(face.rawValue, fixedSize: size))
                .lineSpacing(Typography.lineSpacing(size: size, pitch: pitch))
        } else {
            content
                .font(.custom(face.rawValue, fixedSize: size))
        }
    }
}

extension View {
    func monoText(_ size: CGFloat, _ face: MonoFace = .regular, relativeTo style: Font.TextStyle = .body, pitch: CGFloat? = nil) -> some View {
        modifier(MonoTextModifier(size: size, face: face, relativeTo: style, pitch: pitch))
    }

    func chatText(_ face: MonoFace = .regular) -> some View {
        monoText(Typography.chatBodySize, face, pitch: Typography.chatLinePitch)
    }

    func linePitch(_ pitch: CGFloat, size: CGFloat) -> some View {
        let spacing = Typography.lineSpacing(size: size, pitch: pitch)
        return lineSpacing(spacing).padding(.vertical, spacing / 2)
    }

    func systemLinePitch(_ pitch: CGFloat, size: CGFloat) -> some View {
        let spacing = Typography.systemLineSpacing(size: size, pitch: pitch)
        return lineSpacing(spacing).padding(.vertical, spacing / 2)
    }

    func chatBodyStyle() -> some View {
        chatText()
            .foregroundStyle(Palette.textPrimary)
    }

    func systemText(_ style: SystemTextStyle) -> some View {
        modifier(SystemTextStyleModifier(style: style))
    }
}
