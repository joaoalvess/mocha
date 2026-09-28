import MochaClient
import MochaProtocol
import SwiftUI

struct ProviderMark: View {
    let provider: AgentProvider
    var size: CGFloat = Metrics.claudeMarkHeaderSize

    var body: some View {
        Group {
            switch provider {
            case .claude:
                ClaudeMark(size: size)
            case .codex:
                Image(systemName: "diamond.inset.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct ClaudeMark: View {
    var size: CGFloat = Metrics.claudeMarkHeaderSize
    var color: Color = Palette.claude

    var body: some View {
        Image("ClaudeMark")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CompassNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(1.0, 0.0, in: rect))
        path.addLine(to: point(0.7, 0.7, in: rect))
        path.addLine(to: point(0.0, 1.0, in: rect))
        path.addLine(to: point(0.3, 0.3, in: rect))
        path.closeSubpath()
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

enum LineIcon {
    case prompt
    case document
    case pencil
    case sparkles
    case branch
    case redo
    case chevronRight
    case check
    case xCircle
    case copy
    case sidebar
    case laptop
    case agent
    case flow
    case stopCircle
}

struct LineIconShape: Shape {
    enum Layer {
        case outline
        case fill
    }

    let icon: LineIcon
    var layer: Layer = .outline

    func path(in rect: CGRect) -> Path {
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return (layer == .outline ? viewBoxPath : viewBoxFillPath).applying(scale)
    }

    private var viewBoxPath: Path {
        var path = Path()
        switch icon {
        case .prompt:
            path.addLines([CGPoint(x: 3.5, y: 6.2), CGPoint(x: 9.3, y: 12), CGPoint(x: 3.5, y: 17.8)])
            path.addLines([CGPoint(x: 11.8, y: 18.3), CGPoint(x: 20.5, y: 18.3)])
        case .document:
            path.move(to: CGPoint(x: 6.6, y: 3.4))
            path.addLine(to: CGPoint(x: 13.6, y: 3.4))
            path.addLine(to: CGPoint(x: 18.4, y: 8.2))
            path.addArc(tangent1End: CGPoint(x: 18.4, y: 20.8), tangent2End: CGPoint(x: 16.8, y: 20.8), radius: 1.6)
            path.addArc(tangent1End: CGPoint(x: 5, y: 20.8), tangent2End: CGPoint(x: 5, y: 19.2), radius: 1.6)
            path.addArc(tangent1End: CGPoint(x: 5, y: 3.4), tangent2End: CGPoint(x: 6.6, y: 3.4), radius: 1.6)
            path.closeSubpath()
            path.addLines([CGPoint(x: 13.4, y: 3.6), CGPoint(x: 13.4, y: 8.4), CGPoint(x: 18.2, y: 8.4)])
            path.addLines([CGPoint(x: 8.4, y: 12.8), CGPoint(x: 15.4, y: 12.8)])
            path.addLines([CGPoint(x: 8.4, y: 16.2), CGPoint(x: 13, y: 16.2)])
        case .pencil:
            path.addLines([
                CGPoint(x: 15.3, y: 4.6), CGPoint(x: 19.4, y: 8.7), CGPoint(x: 8.6, y: 19.5),
                CGPoint(x: 3.8, y: 20.2), CGPoint(x: 4.5, y: 15.4),
            ])
            path.closeSubpath()
            path.addLines([CGPoint(x: 13.4, y: 6.5), CGPoint(x: 17.5, y: 10.6)])
        case .sparkles:
            path.move(to: CGPoint(x: 9.6, y: 5.3))
            path.addCurve(to: CGPoint(x: 15.7, y: 11.4), control1: CGPoint(x: 10.2, y: 9), control2: CGPoint(x: 12, y: 10.8))
            path.addCurve(to: CGPoint(x: 9.6, y: 17.5), control1: CGPoint(x: 12, y: 12), control2: CGPoint(x: 10.2, y: 13.8))
            path.addCurve(to: CGPoint(x: 3.5, y: 11.4), control1: CGPoint(x: 9, y: 13.8), control2: CGPoint(x: 7.2, y: 12))
            path.addCurve(to: CGPoint(x: 9.6, y: 5.3), control1: CGPoint(x: 7.2, y: 10.8), control2: CGPoint(x: 9, y: 9))
            path.closeSubpath()
            path.move(to: CGPoint(x: 17.6, y: 2.8))
            path.addCurve(to: CGPoint(x: 20.1, y: 5.3), control1: CGPoint(x: 17.86, y: 4.3), control2: CGPoint(x: 18.6, y: 5.04))
            path.addCurve(to: CGPoint(x: 17.6, y: 7.8), control1: CGPoint(x: 18.6, y: 5.56), control2: CGPoint(x: 17.86, y: 6.3))
            path.addCurve(to: CGPoint(x: 15.1, y: 5.3), control1: CGPoint(x: 17.34, y: 6.3), control2: CGPoint(x: 16.6, y: 5.56))
            path.addCurve(to: CGPoint(x: 17.6, y: 2.8), control1: CGPoint(x: 16.6, y: 5.04), control2: CGPoint(x: 17.34, y: 4.3))
            path.closeSubpath()
            path.addLines([CGPoint(x: 17.4, y: 17.2), CGPoint(x: 17.4, y: 20.6)])
            path.addLines([CGPoint(x: 15.7, y: 18.9), CGPoint(x: 19.1, y: 18.9)])
        case .branch:
            path.addEllipse(in: CGRect(x: 4.5, y: 15.5, width: 5, height: 5))
            path.addEllipse(in: CGRect(x: 14.7, y: 3.5, width: 5, height: 5))
            path.addLines([CGPoint(x: 7, y: 15.5), CGPoint(x: 7, y: 3.3)])
            path.move(to: CGPoint(x: 17.2, y: 8.5))
            path.addCurve(to: CGPoint(x: 7, y: 15.5), control1: CGPoint(x: 17.2, y: 13.3), control2: CGPoint(x: 7, y: 11.7))
        case .redo:
            path.move(to: CGPoint(x: 4, y: 16.2))
            path.addCurve(to: CGPoint(x: 9.93, y: 8.01), control1: CGPoint(x: 3.86, y: 12.43), control2: CGPoint(x: 6.3, y: 9.05))
            path.addCurve(to: CGPoint(x: 19.3, y: 11.8), control1: CGPoint(x: 13.55, y: 6.97), control2: CGPoint(x: 17.42, y: 8.53))
            path.addLines([CGPoint(x: 20.3, y: 6.6), CGPoint(x: 20.3, y: 12.4), CGPoint(x: 14.5, y: 12.4)])
            path.addEllipse(in: CGRect(x: 11.6, y: 16.9, width: 0.8, height: 0.8))
        case .chevronRight:
            path.addLines([CGPoint(x: 8.5, y: 4.5), CGPoint(x: 16, y: 12), CGPoint(x: 8.5, y: 19.5)])
        case .check:
            path.addLines([CGPoint(x: 4.6, y: 12.8), CGPoint(x: 9.4, y: 17.6), CGPoint(x: 19.6, y: 6.8)])
        case .xCircle:
            path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
            path.addLines([CGPoint(x: 8.9, y: 8.9), CGPoint(x: 15.1, y: 15.1)])
            path.addLines([CGPoint(x: 15.1, y: 8.9), CGPoint(x: 8.9, y: 15.1)])
        case .copy:
            path.addRoundedRect(in: CGRect(x: 8.5, y: 8.5, width: 11.8, height: 11.8), cornerSize: CGSize(width: 2.7, height: 2.7), style: .circular)
            path.move(to: CGPoint(x: 15.5, y: 5.4))
            path.addArc(center: CGPoint(x: 13.1188, y: 5.6999), radius: 2.4, startAngle: .degrees(-7.179), endAngle: .degrees(-90.449), clockwise: true)
            path.addLine(to: CGPoint(x: 6.1, y: 3.3))
            path.addArc(tangent1End: CGPoint(x: 3.7, y: 3.3), tangent2End: CGPoint(x: 3.7, y: 5.7), radius: 2.4)
            path.addLine(to: CGPoint(x: 3.7, y: 12.7))
            path.addArc(center: CGPoint(x: 6.0998, y: 12.7335), radius: 2.4, startAngle: .degrees(-179.2), endAngle: .degrees(99.588), clockwise: true)
        case .sidebar:
            path.addRoundedRect(in: CGRect(x: 3, y: 4.5, width: 18, height: 15), cornerSize: CGSize(width: 3.3, height: 3.3), style: .circular)
            path.addLines([CGPoint(x: 9.3, y: 4.5), CGPoint(x: 9.3, y: 19.5)])
            path.addLines([CGPoint(x: 5.7, y: 8.4), CGPoint(x: 6.9, y: 8.4)])
            path.addLines([CGPoint(x: 5.7, y: 11.2), CGPoint(x: 6.9, y: 11.2)])
            path.addLines([CGPoint(x: 5.7, y: 14), CGPoint(x: 6.9, y: 14)])
        case .laptop:
            path.addRoundedRect(in: CGRect(x: 4.5, y: 5, width: 15, height: 10.6), cornerSize: CGSize(width: 1.7, height: 1.7), style: .circular)
            path.addLines([CGPoint(x: 2.4, y: 18.8), CGPoint(x: 21.6, y: 18.8)])
        case .agent:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 3.5, width: 7.2, height: 7.2), cornerSize: CGSize(width: 1.9, height: 1.9), style: .circular)
            path.addRoundedRect(in: CGRect(x: 13.3, y: 13.3, width: 7.2, height: 7.2), cornerSize: CGSize(width: 1.9, height: 1.9), style: .circular)
            path.move(to: CGPoint(x: 7.1, y: 10.7))
            path.addArc(tangent1End: CGPoint(x: 7.1, y: 17.1), tangent2End: CGPoint(x: 13.3, y: 17.1), radius: 2.9)
            path.addLine(to: CGPoint(x: 13.3, y: 17.1))
        case .flow:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 3.5, width: 6, height: 6), cornerSize: CGSize(width: 1.6, height: 1.6), style: .circular)
            path.addRoundedRect(in: CGRect(x: 14.5, y: 9, width: 6, height: 6), cornerSize: CGSize(width: 1.6, height: 1.6), style: .circular)
            path.addRoundedRect(in: CGRect(x: 3.5, y: 14.5, width: 6, height: 6), cornerSize: CGSize(width: 1.6, height: 1.6), style: .circular)
            path.move(to: CGPoint(x: 9.5, y: 6.5))
            path.addArc(tangent1End: CGPoint(x: 13.5, y: 6.5), tangent2End: CGPoint(x: 13.5, y: 12), radius: 1.6)
            path.addLine(to: CGPoint(x: 13.5, y: 12))
            path.addLine(to: CGPoint(x: 14.5, y: 12))
            path.move(to: CGPoint(x: 9.5, y: 17.5))
            path.addArc(tangent1End: CGPoint(x: 13.5, y: 17.5), tangent2End: CGPoint(x: 13.5, y: 12), radius: 1.6)
            path.addLine(to: CGPoint(x: 13.5, y: 12))
        case .stopCircle:
            path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
        }
        return path
    }

    private var viewBoxFillPath: Path {
        var path = Path()
        if icon == .stopCircle {
            path.addRoundedRect(in: CGRect(x: 8.9, y: 8.9, width: 6.2, height: 6.2), cornerSize: CGSize(width: 1.3, height: 1.3), style: .circular)
        }
        return path
    }
}

struct LineIconView: View {
    let icon: LineIcon
    var size: CGFloat
    var strokeWidth: CGFloat
    var color: Color

    var body: some View {
        ZStack {
            LineIconShape(icon: icon)
                .stroke(color, style: StrokeStyle(lineWidth: size * strokeWidth / 24, lineCap: .round, lineJoin: .round))
            LineIconShape(icon: icon, layer: .fill)
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ToolIconView: View {
    let icon: ToolIcon
    var size: CGFloat = 15
    var color: Color = Palette.textSecondary

    var body: some View {
        LineIconView(icon: lineIcon, size: size, strokeWidth: 1.9, color: color)
    }

    private var lineIcon: LineIcon {
        switch icon {
        case .shell: .prompt
        case .document: .document
        case .pencil: .pencil
        case .sparkles: .sparkles
        }
    }
}
