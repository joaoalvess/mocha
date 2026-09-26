import SwiftUI

enum PairingGlyph {
    case cup
    case qr
    case link
    case warning
}

struct PairingGlyphView: View {
    let glyph: PairingGlyph
    var size: CGFloat
    var strokeWidth: CGFloat
    var color: Color

    var body: some View {
        ZStack {
            PairingGlyphShape(glyph: glyph)
                .stroke(color, style: StrokeStyle(lineWidth: size * strokeWidth / 24, lineCap: .round, lineJoin: .round))
            PairingGlyphDots(glyph: glyph)
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PairingGlyphShape: Shape {
    let glyph: PairingGlyph

    func path(in rect: CGRect) -> Path {
        viewBoxPath.applying(ViewBox.transform(for: rect))
    }

    private var viewBoxPath: Path {
        var path = Path()
        switch glyph {
        case .cup:
            path.move(to: CGPoint(x: 4.6, y: 10.4))
            path.addLine(to: CGPoint(x: 16.2, y: 10.4))
            path.addLine(to: CGPoint(x: 16.2, y: 14.6))
            path.addViewBoxArc(to: CGPoint(x: 11.4, y: 19.4), radius: 4.8, sweep: true)
            path.addLine(to: CGPoint(x: 9.4, y: 19.4))
            path.addViewBoxArc(to: CGPoint(x: 4.6, y: 14.6), radius: 4.8, sweep: true)
            path.closeSubpath()
            path.move(to: CGPoint(x: 16.2, y: 11.6))
            path.addLine(to: CGPoint(x: 17.5, y: 11.6))
            path.addViewBoxArc(to: CGPoint(x: 17.5, y: 16.4), radius: 2.4, sweep: true)
            path.addLine(to: CGPoint(x: 15.9, y: 16.4))
            path.addLines([CGPoint(x: 3.4, y: 21.2), CGPoint(x: 17.6, y: 21.2)])
            path.addLines([CGPoint(x: 10.4, y: 2.6), CGPoint(x: 10.4, y: 7.6)])
            path.addLines([CGPoint(x: 8, y: 3.6), CGPoint(x: 12.8, y: 6.6)])
            path.addLines([CGPoint(x: 8, y: 6.6), CGPoint(x: 12.8, y: 3.6)])
            path.addLines([CGPoint(x: 7.9, y: 5.1), CGPoint(x: 12.9, y: 5.1)])
        case .qr:
            path.move(to: CGPoint(x: 3.5, y: 8.2))
            path.addLine(to: CGPoint(x: 3.5, y: 5.6))
            path.addViewBoxArc(to: CGPoint(x: 5.6, y: 3.5), radius: 2.1, sweep: true)
            path.addLine(to: CGPoint(x: 8.2, y: 3.5))
            path.move(to: CGPoint(x: 15.8, y: 3.5))
            path.addLine(to: CGPoint(x: 18.4, y: 3.5))
            path.addViewBoxArc(to: CGPoint(x: 20.5, y: 5.6), radius: 2.1, sweep: true)
            path.addLine(to: CGPoint(x: 20.5, y: 8.2))
            path.move(to: CGPoint(x: 20.5, y: 15.8))
            path.addLine(to: CGPoint(x: 20.5, y: 18.4))
            path.addViewBoxArc(to: CGPoint(x: 18.4, y: 20.5), radius: 2.1, sweep: true)
            path.addLine(to: CGPoint(x: 15.8, y: 20.5))
            path.move(to: CGPoint(x: 8.2, y: 20.5))
            path.addLine(to: CGPoint(x: 5.6, y: 20.5))
            path.addViewBoxArc(to: CGPoint(x: 3.5, y: 18.4), radius: 2.1, sweep: true)
            path.addLine(to: CGPoint(x: 3.5, y: 15.8))
            for origin in [CGPoint(x: 7.2, y: 7.2), CGPoint(x: 13, y: 7.2), CGPoint(x: 7.2, y: 13)] {
                path.addRoundedRect(in: CGRect(origin: origin, size: CGSize(width: 3.8, height: 3.8)), cornerSize: CGSize(width: 0.6, height: 0.6), style: .circular)
            }
            path.addLines([CGPoint(x: 13.2, y: 13.2), CGPoint(x: 14.8, y: 13.2), CGPoint(x: 14.8, y: 14.8)])
            path.addLines([CGPoint(x: 16.8, y: 13.6), CGPoint(x: 16.8, y: 16.8), CGPoint(x: 13.4, y: 16.8)])
        case .link:
            path.move(to: CGPoint(x: 10, y: 14))
            path.addViewBoxArc(to: CGPoint(x: 15.7, y: 14), radius: 4, sweep: false)
            path.addLine(to: CGPoint(x: 18.7, y: 11))
            path.addViewBoxArc(to: CGPoint(x: 13, y: 5.3), radius: 4, sweep: false)
            path.addLine(to: CGPoint(x: 11.8, y: 6.5))
            path.move(to: CGPoint(x: 14, y: 10))
            path.addViewBoxArc(to: CGPoint(x: 8.3, y: 10), radius: 4, sweep: false)
            path.addLine(to: CGPoint(x: 5.3, y: 13))
            path.addViewBoxArc(to: CGPoint(x: 11, y: 18.7), radius: 4, sweep: false)
            path.addLine(to: CGPoint(x: 12.2, y: 17.5))
        case .warning:
            path.move(to: CGPoint(x: 10.4, y: 4.6))
            path.addViewBoxArc(to: CGPoint(x: 13.6, y: 4.6), radius: 1.8, sweep: true)
            path.addLine(to: CGPoint(x: 20.9, y: 17.6))
            path.addViewBoxArc(to: CGPoint(x: 19.3, y: 20.3), radius: 1.8, sweep: true)
            path.addLine(to: CGPoint(x: 4.7, y: 20.3))
            path.addViewBoxArc(to: CGPoint(x: 3.1, y: 17.6), radius: 1.8, sweep: true)
            path.closeSubpath()
            path.addLines([CGPoint(x: 12, y: 9.6), CGPoint(x: 12, y: 14.2)])
        }
        return path
    }
}

private struct PairingGlyphDots: Shape {
    let glyph: PairingGlyph

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch glyph {
        case .warning:
            path.addEllipse(in: CGRect(x: 11.1, y: 16.1, width: 1.8, height: 1.8))
        case .cup, .qr, .link:
            break
        }
        return path.applying(ViewBox.transform(for: rect))
    }
}

private enum ViewBox {
    static let side: CGFloat = 24

    static func transform(for rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / side, y: rect.height / side)
    }
}

private extension Path {
    mutating func addViewBoxArc(to end: CGPoint, radius: CGFloat, sweep: Bool) {
        guard let start = currentPoint else { return }
        let halfX = (start.x - end.x) / 2
        let halfY = (start.y - end.y) / 2
        let halfChordSquared = halfX * halfX + halfY * halfY
        guard halfChordSquared > 0 else { return }
        let arcRadius = max(radius, halfChordSquared.squareRoot())
        let offset = max(0, (arcRadius * arcRadius - halfChordSquared) / halfChordSquared).squareRoot() * (sweep ? 1 : -1)
        let center = CGPoint(x: offset * halfY + (start.x + end.x) / 2, y: -offset * halfX + (start.y + end.y) / 2)
        addArc(
            center: center,
            radius: arcRadius,
            startAngle: .radians(atan2(start.y - center.y, start.x - center.x)),
            endAngle: .radians(atan2(end.y - center.y, end.x - center.x)),
            clockwise: !sweep
        )
    }
}
