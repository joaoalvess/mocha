import SwiftUI

struct ClaudeMark: View {
    var size: CGFloat = Metrics.claudeMarkHeaderSize

    var body: some View {
        Image("ClaudeMark")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(Palette.claude)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CompassNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(1.0, 0.03, in: rect))
        path.addLine(to: point(0.27, 0.24, in: rect))
        path.addLine(to: point(0.03, 0.97, in: rect))
        path.addLine(to: point(0.73, 0.76, in: rect))
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

struct PromptGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.0, 0.0, in: rect))
        path.addLine(to: point(0.43, 0.445, in: rect))
        path.addLine(to: point(0.0, 0.89, in: rect))
        path.move(to: point(0.57, 1.0, in: rect))
        path.addLine(to: point(1.0, 1.0, in: rect))
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

struct PromptIcon: View {
    var width: CGFloat
    var lineWidth: CGFloat
    var color: Color

    var body: some View {
        PromptGlyph()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: width * 0.85)
            .padding(lineWidth / 2)
            .accessibilityHidden(true)
    }
}
