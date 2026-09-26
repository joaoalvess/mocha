import SwiftUI

enum DrawerIcon {
    case search
    case clock
    case listRect
    case gear
}

struct DrawerIconShape: Shape {
    let icon: DrawerIcon

    func path(in rect: CGRect) -> Path {
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return viewBoxPath.applying(scale)
    }

    private var viewBoxPath: Path {
        var path = Path()
        switch icon {
        case .search:
            path.addEllipse(in: CGRect(x: 3.7, y: 3.7, width: 13.6, height: 13.6))
            path.addLines([CGPoint(x: 15.6, y: 15.6), CGPoint(x: 20.5, y: 20.5)])
        case .clock:
            path.addEllipse(in: CGRect(x: 3.2, y: 3.2, width: 17.6, height: 17.6))
            path.addLines([CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 12.3), CGPoint(x: 15.3, y: 14.3)])
        case .listRect:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 3.8, width: 5.2, height: 5.2), cornerSize: CGSize(width: 1.2, height: 1.2), style: .circular)
            path.addRoundedRect(in: CGRect(x: 3.5, y: 10.9, width: 5.2, height: 5.2), cornerSize: CGSize(width: 1.2, height: 1.2), style: .circular)
            path.addRoundedRect(in: CGRect(x: 3.5, y: 18, width: 5.2, height: 2.6), cornerSize: CGSize(width: 1, height: 1), style: .circular)
            for (y, end) in Self.listLines {
                path.addLines([CGPoint(x: 12, y: y), CGPoint(x: end, y: y)])
            }
        case .gear:
            path.addLines(Self.gearOutline)
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: 8.7, y: 8.7, width: 6.6, height: 6.6))
        }
        return path
    }

    private static let listLines: [(CGFloat, CGFloat)] = [(5.2, 20.5), (7.8, 17.5), (12.3, 20.5), (14.9, 17.5), (19.3, 20.5)]

    private static let gearCoordinates: [(CGFloat, CGFloat)] = [
        (10.10, 4.33), (10.56, 1.90), (13.44, 1.90), (13.90, 4.33), (16.07, 5.23), (18.12, 3.84),
        (20.16, 5.88), (18.77, 7.93), (19.67, 10.10), (22.10, 10.56), (22.10, 13.44), (19.67, 13.90),
        (18.77, 16.07), (20.16, 18.12), (18.12, 20.16), (16.07, 18.77), (13.90, 19.67), (13.44, 22.10),
        (10.56, 22.10), (10.10, 19.67), (7.93, 18.77), (5.88, 20.16), (3.84, 18.12), (5.23, 16.07),
        (4.33, 13.90), (1.90, 13.44), (1.90, 10.56), (4.33, 10.10), (5.23, 7.93), (3.84, 5.88),
        (5.88, 3.84), (7.93, 5.23),
    ]

    private static let gearOutline = gearCoordinates.map { CGPoint(x: $0.0, y: $0.1) }
}

struct DrawerIconView: View {
    let icon: DrawerIcon
    var size: CGFloat
    var strokeWidth: CGFloat
    var color: Color

    var body: some View {
        DrawerIconShape(icon: icon)
            .stroke(color, style: StrokeStyle(lineWidth: size * strokeWidth / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
