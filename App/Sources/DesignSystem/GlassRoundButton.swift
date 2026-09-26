import SwiftUI

enum GlassRoundButtonStyle {
    case chat
    case home
    case hero
    case black

    var diameter: CGFloat {
        switch self {
        case .chat: 38
        case .home, .hero, .black: 44
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .chat, .hero, .black: 19
        case .home: 21
        }
    }

    var lineStrokeWidth: CGFloat {
        switch self {
        case .chat, .hero, .black: 2.1
        case .home: 1.8
        }
    }

    var tint: GlassTint {
        switch self {
        case .chat: .chat
        case .home: .home
        case .hero: .hero
        case .black: .black
        }
    }
}

struct GlassRoundButton: View {
    enum Glyph {
        case symbol(String)
        case line(LineIcon)
    }

    let glyph: Glyph
    let accessibilityLabel: String
    let style: GlassRoundButtonStyle
    let action: () -> Void

    init(systemImage: String, accessibilityLabel: String, style: GlassRoundButtonStyle = .chat, action: @escaping () -> Void) {
        glyph = .symbol(systemImage)
        self.accessibilityLabel = accessibilityLabel
        self.style = style
        self.action = action
    }

    init(icon: LineIcon, accessibilityLabel: String, style: GlassRoundButtonStyle = .chat, action: @escaping () -> Void) {
        glyph = .line(icon)
        self.accessibilityLabel = accessibilityLabel
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            glyphView
                .frame(width: style.diameter, height: style.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .mochaGlass(style.tint, interactive: true, in: Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: style.iconSize * 0.9, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
        case .line(let icon):
            LineIconView(icon: icon, size: style.iconSize, strokeWidth: style.lineStrokeWidth, color: Palette.textPrimary)
        }
    }
}
