import SwiftUI
import MochaProtocol

struct ProviderTile: View {
    let provider: AgentProvider
    let size: CGFloat
    let cornerRadius: CGFloat
    let markSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(provider == .codex ? Palette.toolCard : Palette.claudeTile)
            .frame(width: size, height: size)
            .overlay { ProviderMark(provider: provider, size: markSize) }
    }
}

struct ClaudeTile: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    let background: Color
    let markSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay { ClaudeMark(size: markSize) }
            .accessibilityHidden(true)
    }
}
