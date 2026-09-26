import SwiftUI

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
