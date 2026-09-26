import SwiftUI

enum GlassTint {
    case chat
    case composer
    case home
    case pill
    case hero
    case black

    var color: Color {
        switch self {
        case .chat: Palette.glassChat
        case .composer: Palette.glassComposer
        case .home: Palette.glassHome
        case .pill: Palette.glassPill
        case .hero: Palette.glassHero
        case .black: Palette.glassBlack
        }
    }

    var paintsSurface: Bool {
        switch self {
        case .chat, .composer: true
        case .home, .pill, .hero, .black: false
        }
    }
}

extension View {
    func mochaGlass(_ tint: GlassTint, interactive: Bool = false, in shape: some Shape) -> some View {
        background(shape.fill(tint.paintsSurface ? tint.color : .clear))
            .glassEffect((tint.paintsSurface ? Glass.regular : Glass.clear).tint(tint.color).interactive(interactive), in: shape)
    }
}
