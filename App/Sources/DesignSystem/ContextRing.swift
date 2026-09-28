import SwiftUI

enum ContextRingStyle: Equatable {
    case ready
    case working
    case blocked
    case archived
    case offline
}

struct ContextRing: View {
    let percent: Int?
    let style: ContextRingStyle

    private static let diameter: CGFloat = 40
    private static let lineWidth: CGFloat = 3
    private static let badgeDiameter: CGFloat = 10.4
    private static let badgeCenterY: CGFloat = 1.5
    private static let workingArcStart = 0.095
    private static let workingArcLength = 0.07

    var body: some View {
        ZStack {
            Circle()
                .inset(by: Self.lineWidth / 2)
                .stroke(Palette.ringTrack, lineWidth: Self.lineWidth)
            arc
            if let badgeColor {
                badge(color: badgeColor)
            }
            Text(percent.map(String.init) ?? "—")
                .systemText(.ringNumber)
                .foregroundStyle(numberColor)
                .monospacedDigit()
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var arc: some View {
        switch style {
        case .working:
            Circle()
                .inset(by: Self.lineWidth / 2)
                .trim(from: Self.workingArcStart, to: Self.workingArcStart + Self.workingArcLength)
                .stroke(Palette.statusOk, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .spinning(period: 1.6)
        case .ready, .blocked, .archived, .offline:
            if let percent {
                Circle()
                    .inset(by: Self.lineWidth / 2)
                    .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                    .stroke(arcColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private var arcColor: Color {
        switch style {
        case .ready, .working: Palette.statusOk
        case .blocked: Palette.dirty
        case .archived: Palette.statusOk.opacity(0.28)
        case .offline: Palette.offlineRing
        }
    }

    private var badgeColor: Color? {
        switch style {
        case .ready, .working: Palette.statusOk
        case .blocked: Palette.dirty
        case .offline: Palette.offlineRing
        case .archived: nil
        }
    }

    private var numberColor: Color {
        switch style {
        case .ready, .working, .blocked: Palette.textPrimary
        case .archived, .offline: Palette.textSecondary
        }
    }

    private func badge(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: Self.badgeDiameter, height: Self.badgeDiameter)
            .overlay { badgeGlyph }
            .position(x: Self.diameter / 2, y: Self.badgeCenterY)
    }

    @ViewBuilder
    private var badgeGlyph: some View {
        switch style {
        case .blocked:
            AttentionGlyph()
        case .offline:
            BoltGlyph().fill(Palette.offlineRingGlyph).frame(width: 4.3, height: 7.4)
        case .ready, .working, .archived:
            BoltGlyph().fill(Palette.glyphOnAccent).frame(width: 4.3, height: 7.4)
        }
    }

    private var accessibilityText: String {
        guard let percent else { return "Contexto desconhecido" }
        return "\(percent)% de contexto livre"
    }
}

struct AttentionGlyph: View {
    var body: some View {
        VStack(spacing: 0.7) {
            Capsule()
                .frame(width: 1.4, height: 3.7)
            Circle()
                .frame(width: 1.6, height: 1.6)
        }
        .foregroundStyle(Palette.glyphOnDirty)
        .offset(y: -0.1)
    }
}

struct BoltGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(6, 1.3), (2.9, 5.6), (5, 5.6), (4.1, 8.7), (7.2, 4.4), (5.1, 4.4)]
        let minX: CGFloat = 2.9, maxX: CGFloat = 7.2, minY: CGFloat = 1.3, maxY: CGFloat = 8.7
        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(
                x: rect.minX + (point.0 - minX) / (maxX - minX) * rect.width,
                y: rect.minY + (point.1 - minY) / (maxY - minY) * rect.height
            )
            if index == 0 {
                path.move(to: mapped)
            } else {
                path.addLine(to: mapped)
            }
        }
        path.closeSubpath()
        return path
    }
}
