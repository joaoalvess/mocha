import SwiftUI

enum StateBadgeStyle: CaseIterable {
    case working
    case ready
    case needsYou
    case ended

    var title: String {
        switch self {
        case .working: "TRABALHANDO"
        case .ready: "PRONTO"
        case .needsYou: "PRECISA DE VOCÊ"
        case .ended: "ENCERRADA"
        }
    }

    var foreground: Color {
        switch self {
        case .working, .ready: Palette.statusOk
        case .needsYou: Palette.dirty
        case .ended: Palette.textSecondary
        }
    }

    var background: Color {
        switch self {
        case .working, .ready: Palette.stateBadgeOk
        case .needsYou: Palette.stateBadgeWarn
        case .ended: Palette.offlineBadge
        }
    }

    var border: Color {
        switch self {
        case .working: Palette.statusOk
        case .ready: Palette.stateBadgeOk
        case .needsYou: Palette.dirty
        case .ended: Palette.offlineBadge
        }
    }
}

struct StateBadge: View {
    let style: StateBadgeStyle

    private static let height: CGFloat = 25
    private static let borderWidth: CGFloat = 2
    private static let horizontalPadding: CGFloat = 12
    private static let gapTravelPeriod: Double = 3

    var body: some View {
        Text(style.title)
            .systemText(.stateBadge)
            .foregroundStyle(style.foreground)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Self.horizontalPadding + Self.borderWidth)
            .frame(minHeight: Self.height)
            .background { capsule }
    }

    private var capsule: some View {
        ZStack {
            Capsule()
                .fill(style.background)
            Capsule()
                .strokeBorder(style.border, lineWidth: Self.borderWidth)
            if style == .working {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    StateBadgeBorderGaps(
                        progress: elapsed.truncatingRemainder(dividingBy: Self.gapTravelPeriod) / Self.gapTravelPeriod,
                        borderWidth: Self.borderWidth
                    )
                    .fill(Color.black)
                    .blendMode(.destinationOut)
                }
            }
        }
        .compositingGroup()
    }
}

private struct StateBadgeBorderGaps: Shape {
    var progress: Double
    let borderWidth: CGFloat

    private static let gapLength: CGFloat = 7
    private static let gapDepth: CGFloat = 3
    private static let firstGapFraction: CGFloat = 0.26
    private static let secondGapFraction: CGFloat = 0.64

    func path(in rect: CGRect) -> Path {
        let centerline = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let radius = centerline.height / 2
        guard centerline.width > 2 * radius, radius > 0 else { return Path() }

        var outline = Path()
        outline.move(to: CGPoint(x: centerline.minX + radius, y: centerline.minY))
        outline.addLine(to: CGPoint(x: centerline.maxX - radius, y: centerline.minY))
        outline.addArc(center: CGPoint(x: centerline.maxX - radius, y: centerline.midY), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        outline.addLine(to: CGPoint(x: centerline.minX + radius, y: centerline.maxY))
        outline.addArc(center: CGPoint(x: centerline.minX + radius, y: centerline.midY), radius: radius, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        outline.closeSubpath()

        let perimeter = 2 * (centerline.width - 2 * radius) + 2 * .pi * radius
        let innerWidth = rect.width - 2 * borderWidth
        let firstGapX = rect.minX + borderWidth + Self.firstGapFraction * innerWidth
        let secondGapX = rect.minX + borderWidth + Self.secondGapFraction * innerWidth
        let firstGapDistance = firstGapX - (centerline.minX + radius)
        let between = max(secondGapX - firstGapX - Self.gapLength, 0)
        let rest = max(perimeter - 2 * Self.gapLength - between, 0)
        let start = (firstGapDistance + CGFloat(progress) * perimeter).truncatingRemainder(dividingBy: perimeter)
        let phase = (perimeter - start).truncatingRemainder(dividingBy: perimeter)

        return outline.strokedPath(StrokeStyle(
            lineWidth: Self.gapDepth,
            lineCap: .butt,
            dash: [Self.gapLength, between, Self.gapLength, rest],
            dashPhase: phase
        ))
    }
}
