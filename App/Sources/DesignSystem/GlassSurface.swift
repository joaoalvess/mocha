import SwiftUI

enum GlassTint {
    case chat
    case composer
    case home
    case pill
    case hero
    case black
    case composerClear
    case menu

    var color: Color {
        switch self {
        case .chat: Palette.glassChat
        case .composer: Palette.glassComposer
        case .home: Palette.glassHome
        case .pill: Palette.glassPill
        case .hero: Palette.glassHero
        case .black: Palette.glassBlack
        case .composerClear: Palette.glassComposerClear
        case .menu: Palette.glassMenu
        }
    }

    var paintsSurface: Bool {
        switch self {
        case .chat, .composer: true
        case .home, .pill, .hero, .black, .composerClear, .menu: false
        }
    }

    var usesClearGlass: Bool {
        switch self {
        case .chat, .composer, .composerClear, .menu: false
        case .home, .pill, .hero, .black: true
        }
    }
}

extension View {
    func mochaGlass(_ tint: GlassTint, interactive: Bool = false, in shape: some Shape) -> some View {
        background(shape.fill(tint.paintsSurface ? tint.color : .clear))
            .glassEffect((tint.usesClearGlass ? Glass.clear : Glass.regular).tint(tint.color).interactive(interactive), in: shape)
    }
}
