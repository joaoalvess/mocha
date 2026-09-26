import SwiftUI

enum SlashMenuIcon {
    case compress
    case trash
    case pie
    case dollar
    case stopCircle
}

struct SlashMenuIconShape: Shape {
    enum Layer {
        case outline
        case fill
    }

    let icon: SlashMenuIcon
    var layer: Layer = .outline

    func path(in rect: CGRect) -> Path {
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return (layer == .outline ? outline : filled).applying(scale)
    }

    private var outline: Path {
        var path = Path()
        switch icon {
        case .compress:
            path.addLines([CGPoint(x: 4, y: 14), CGPoint(x: 10, y: 14), CGPoint(x: 10, y: 20)])
            path.addLines([CGPoint(x: 20, y: 10), CGPoint(x: 14, y: 10), CGPoint(x: 14, y: 4)])
            path.addLines([CGPoint(x: 10, y: 14), CGPoint(x: 3.8, y: 20.2)])
            path.addLines([CGPoint(x: 14, y: 10), CGPoint(x: 20.2, y: 3.8)])
        case .trash:
            path.addLines([CGPoint(x: 4.3, y: 6.4), CGPoint(x: 19.7, y: 6.4)])
            path.addLines([CGPoint(x: 9.4, y: 6.4), CGPoint(x: 9.4, y: 4.2), CGPoint(x: 14.6, y: 4.2), CGPoint(x: 14.6, y: 6.4)])
            path.addLines([CGPoint(x: 6.3, y: 6.4), CGPoint(x: 7.3, y: 19.8), CGPoint(x: 16.7, y: 19.8), CGPoint(x: 17.7, y: 6.4)])
            path.addLines([CGPoint(x: 10, y: 10.4), CGPoint(x: 10, y: 16)])
            path.addLines([CGPoint(x: 14, y: 10.4), CGPoint(x: 14, y: 16)])
        case .pie:
            path.move(to: CGPoint(x: 11, y: 4.1))
            path.addArc(center: CGPoint(x: 11.5158, y: 12.4842), radius: 8.4, startAngle: .degrees(-93.522), endAngle: .degrees(3.522), clockwise: true)
            path.addLine(to: CGPoint(x: 11, y: 13))
            path.closeSubpath()
            path.move(to: CGPoint(x: 14, y: 2.9))
            path.addLine(to: CGPoint(x: 14, y: 10))
            path.addLine(to: CGPoint(x: 21.1, y: 10))
            path.addArc(center: CGPoint(x: 13.8027, y: 10.1973), radius: 7.3, startAngle: .degrees(-1.549), endAngle: .degrees(-88.451), clockwise: true)
            path.closeSubpath()
        case .dollar:
            path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
            path.move(to: CGPoint(x: 14.7, y: 9.3))
            path.addCurve(to: CGPoint(x: 12, y: 7.5), control1: CGPoint(x: 14.4, y: 8.2), control2: CGPoint(x: 13.3, y: 7.5))
            path.addCurve(to: CGPoint(x: 9.3, y: 9.5), control1: CGPoint(x: 10.5, y: 7.5), control2: CGPoint(x: 9.3, y: 8.3))
            path.addCurve(to: CGPoint(x: 14.8, y: 13.8), control1: CGPoint(x: 9.3, y: 12.3), control2: CGPoint(x: 14.8, y: 10.9))
            path.addCurve(to: CGPoint(x: 12, y: 15.9), control1: CGPoint(x: 14.8, y: 15), control2: CGPoint(x: 13.6, y: 15.9))
            path.addCurve(to: CGPoint(x: 9.1, y: 14), control1: CGPoint(x: 10.6, y: 15.9), control2: CGPoint(x: 9.4, y: 15.2))
            path.addLines([CGPoint(x: 12, y: 5.9), CGPoint(x: 12, y: 7.5)])
            path.addLines([CGPoint(x: 12, y: 16), CGPoint(x: 12, y: 17.8)])
        case .stopCircle:
            path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
        }
        return path
    }

    private var filled: Path {
        var path = Path()
        if icon == .stopCircle {
            path.addRoundedRect(in: CGRect(x: 8.9, y: 8.9, width: 6.2, height: 6.2), cornerSize: CGSize(width: 1.3, height: 1.3), style: .circular)
        }
        return path
    }
}

struct SlashMenuIconView: View {
    let icon: SlashMenuIcon
    var size: CGFloat
    var strokeWidth: CGFloat
    var color: Color

    var body: some View {
        ZStack {
            SlashMenuIconShape(icon: icon)
                .stroke(color, style: StrokeStyle(lineWidth: size * strokeWidth / 24, lineCap: .round, lineJoin: .round))
            SlashMenuIconShape(icon: icon, layer: .fill)
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
