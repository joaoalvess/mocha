import SwiftUI

enum SlashMenuIcon {
    case compress
    case trash
    case mode
    case usage
    case subagents
    case plan
    case chevronLeft
}

struct SlashMenuIconShape: Shape {
    let icon: SlashMenuIcon

    func path(in rect: CGRect) -> Path {
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return outline.applying(scale)
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
        case .mode:
            path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
            path.addLines([CGPoint(x: 10.2, y: 8.6), CGPoint(x: 15.4, y: 12), CGPoint(x: 10.2, y: 15.4)])
            path.closeSubpath()
        case .usage:
            path.addEllipse(in: CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8))
            path.addLines([CGPoint(x: 12, y: 3.4), CGPoint(x: 12, y: 12), CGPoint(x: 20.6, y: 12)])
        case .subagents:
            path.addRoundedRect(in: CGRect(x: 3.6, y: 3.6, width: 7, height: 7), cornerSize: CGSize(width: 1.8, height: 1.8), style: .circular)
            path.addRoundedRect(in: CGRect(x: 13.4, y: 3.6, width: 7, height: 7), cornerSize: CGSize(width: 1.8, height: 1.8), style: .circular)
            path.addRoundedRect(in: CGRect(x: 3.6, y: 13.4, width: 7, height: 7), cornerSize: CGSize(width: 1.8, height: 1.8), style: .circular)
            path.addRoundedRect(in: CGRect(x: 13.4, y: 13.4, width: 7, height: 7), cornerSize: CGSize(width: 1.8, height: 1.8), style: .circular)
        case .plan:
            path.addLines([CGPoint(x: 9.4, y: 6.5), CGPoint(x: 20.2, y: 6.5)])
            path.addLines([CGPoint(x: 9.4, y: 12), CGPoint(x: 20.2, y: 12)])
            path.addLines([CGPoint(x: 9.4, y: 17.5), CGPoint(x: 20.2, y: 17.5)])
            path.addEllipse(in: CGRect(x: 4, y: 5.7, width: 1.6, height: 1.6))
            path.addEllipse(in: CGRect(x: 4, y: 11.2, width: 1.6, height: 1.6))
            path.addEllipse(in: CGRect(x: 4, y: 16.7, width: 1.6, height: 1.6))
        case .chevronLeft:
            path.addLines([CGPoint(x: 15.5, y: 4.5), CGPoint(x: 8, y: 12), CGPoint(x: 15.5, y: 19.5)])
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
        SlashMenuIconShape(icon: icon)
            .stroke(color, style: StrokeStyle(lineWidth: size * strokeWidth / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
