import MochaClient
import SwiftUI

enum AgentsPalette {
    static let background = Color(hex: 0x121416).opacity(0.8)
    static let textPrimary = Color(hex: 0xFCFCFC)
    static let textSecondary = Color(hex: 0x98A0A8)
    static let link = Color(hex: 0x78A0F4)
    static let claude = Color(hex: 0xD87454)
    static let claudeTile = Color(hex: 0x2E221F)
    static let statusOk = Color(hex: 0x00FF00)
    static let onStatusOk = Color(hex: 0x021402)
    static let waiting = Color(hex: 0xF4B450)
    static let controlBg = Color(hex: 0x202225)
    static let divider = Color.white.opacity(0.08)

    static func color(for tone: AgentsActivityTone) -> Color {
        switch tone {
        case .working: claude
        case .waiting: waiting
        case .done: statusOk
        }
    }

    static func dotColor(for tone: AgentsActivityTone) -> Color {
        switch tone {
        case .working: statusOk
        case .waiting: waiting
        case .done: textSecondary
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct ClaudeMark: View {
    let size: CGFloat
    var color: Color = AgentsPalette.claude

    var body: some View {
        Image("ClaudeMark")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ClaudeTile: View {
    let size: CGFloat
    let markSize: CGFloat

    var body: some View {
        ClaudeMark(size: markSize)
            .frame(width: size, height: size)
            .background(AgentsPalette.claudeTile, in: RoundedRectangle(cornerRadius: size * 10 / 34, style: .continuous))
    }
}

struct StatusDot: View {
    let tone: AgentsActivityTone

    var body: some View {
        Circle()
            .fill(AgentsPalette.dotColor(for: tone))
            .frame(width: 9, height: 9)
            .shadow(color: tone == .working ? AgentsPalette.statusOk.opacity(0.6) : .clear, radius: 3)
    }
}

struct ElapsedTimer: View {
    let since: Date
    let tone: AgentsActivityTone
    let size: CGFloat

    var body: some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(tone == .waiting ? AgentsPalette.waiting : AgentsPalette.textSecondary)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: size * 4.8, alignment: .trailing)
    }
}

struct SummaryText: View {
    let content: AgentsActivityContent
    let size: CGFloat

    var body: some View {
        text
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(AgentsPalette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var text: Text {
        let summary = AgentsActivityText.summary(of: content)
        switch (summary.working, summary.waiting) {
        case let (working?, waiting?):
            return Text("\(working)\(AgentsActivityText.separator)\(Text(waiting).foregroundStyle(AgentsPalette.waiting))")
        case let (nil, waiting?):
            return Text(waiting).foregroundStyle(AgentsPalette.waiting)
        default:
            return Text(summary.text)
        }
    }
}
