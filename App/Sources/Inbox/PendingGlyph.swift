import MochaProtocol
import SwiftUI

enum PendingGlyphKind {
    case exclamation
    case question

    init(_ kind: PendingKind) {
        switch kind {
        case .permission: self = .exclamation
        case .question: self = .question
        }
    }
}

struct PendingGlyphShape: Shape {
    enum Layer {
        case outline
        case fill
    }

    let kind: PendingGlyphKind
    var layer: Layer = .outline

    func path(in rect: CGRect) -> Path {
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return (layer == .outline ? outline : dot).applying(scale)
    }

    private var outline: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
        switch kind {
        case .exclamation:
            path.addLines([CGPoint(x: 12, y: 7.4), CGPoint(x: 12, y: 13.2)])
        case .question:
            path.move(to: CGPoint(x: 9.5, y: 9.7))
            path.addArc(center: CGPoint(x: 12.0996, y: 9.7443), radius: 2.6, startAngle: .degrees(180.98), endAngle: .degrees(64.96), clockwise: false)
            path.addCurve(to: CGPoint(x: 12, y: 13.9), control1: CGPoint(x: 12.4, y: 12.5), control2: CGPoint(x: 12, y: 13.1))
            path.addLine(to: CGPoint(x: 12, y: 14.3))
        }
        return path
    }

    private var dot: Path {
        let centerY: CGFloat = kind == .exclamation ? 16.4 : 16.9
        return Path(ellipseIn: CGRect(x: 12 - 0.95, y: centerY - 0.95, width: 1.9, height: 1.9))
    }
}

struct PendingGlyph: View {
    let kind: PendingGlyphKind
    var size: CGFloat = 15
    var strokeWidth: CGFloat = 2
    var color: Color = Palette.dirty

    var body: some View {
        ZStack {
            PendingGlyphShape(kind: kind)
                .stroke(color, style: StrokeStyle(lineWidth: size * strokeWidth / 24, lineCap: .round, lineJoin: .round))
            PendingGlyphShape(kind: kind, layer: .fill)
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
