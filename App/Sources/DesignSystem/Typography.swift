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

    static var chatLineSpacing: CGFloat {
        max(0, chatLinePitch - chatBodySize * monoLineHeightRatio)
    }

    static func mono(_ size: CGFloat, _ face: MonoFace = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    static let chatBody = mono(chatBodySize)
    static let chatBodyBold = mono(chatBodySize, .bold)
    static let chatItalic = mono(chatBodySize, .italic)
    static let chatBoldItalic = mono(chatBodySize, .boldItalic)
    static let headerTitle = mono(headerTitleSize, .bold, relativeTo: .headline)
    static let headerSubtitle = mono(headerSubtitleSize, relativeTo: .caption)
    static let toolCard = mono(toolCardSize, relativeTo: .caption)
    static let toolCardName = mono(toolCardSize, .bold, relativeTo: .caption)
    static let composer = mono(composerSize)

    static let drawerRow = Font.body
    static let drawerWorkspace = Font.body.weight(.medium)
    static let drawerDetail = Font.subheadline
    static let drawerSectionHeader = Font.footnote.weight(.semibold)
}

extension View {
    func chatBodyStyle() -> some View {
        font(Typography.chatBody)
            .lineSpacing(Typography.chatLineSpacing)
            .foregroundStyle(Palette.textPrimary)
    }
}
