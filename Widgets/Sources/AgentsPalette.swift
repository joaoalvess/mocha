import MochaClient
import MochaProtocol
import SwiftUI

enum AgentsPalette {
    static let background = Color(hex: 0x010102)
    static let textPrimary = Color(hex: 0xFCFCFC)
    static let textSecondary = Color(hex: 0xA9A9A9)
    static let headerSecondary = Color(hex: 0xD4D4D4)
    static let separator = Color(hex: 0x555555)
    static let claude = Color(hex: 0xCA7B5D)
    static let codex = Color(hex: 0x1A7F64)
    static let statusOk = Color(hex: 0x9AF768)
    static let onStatusOk = Color(hex: 0x021402)
    static let waiting = Color(hex: 0xF4B450)
    static let request = Color(hex: 0xEC9B43)
    static let controlBg = Color(hex: 0x202225)
    static let contextTrack = Color(hex: 0x463B38)

    static func color(for tone: AgentsActivityTone, provider: AgentProvider = .claude) -> Color {
        switch tone {
        case .working: provider == .codex ? codex : claude
        case .waiting: waiting
        case .done: statusOk
        }
    }

    static func labelColor(for tone: AgentsActivityTone) -> Color {
        switch tone {
        case .working, .done: statusOk
        case .waiting: waiting
        }
    }

    static func contextColor(isBlocked: Bool) -> Color {
        isBlocked ? waiting : statusOk
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .displayP3,
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
        ClaudeMark(size: markSize, color: AgentsPalette.textPrimary)
            .frame(width: size, height: size)
            .background(AgentsPalette.claude, in: Circle())
    }
}

struct ProviderMark: View {
    let provider: AgentProvider
    let size: CGFloat
    let color: Color

    var body: some View {
        Group {
            switch provider {
            case .claude:
                ClaudeMark(size: size, color: color)
            case .codex:
                CodexMark(size: size, color: color)
            }
        }
    }
}

struct CodexMark: View {
    let size: CGFloat
    var color: Color = AgentsPalette.codex

    var body: some View {
        Image("CodexMark")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ProviderTile: View {
    let provider: AgentProvider
    let size: CGFloat
    let markSize: CGFloat

    var body: some View {
        ProviderMark(provider: provider, size: markSize, color: AgentsPalette.textPrimary)
            .frame(width: size, height: size)
            .background(provider == .codex ? AgentsPalette.codex : AgentsPalette.claude, in: Circle())
    }
}

struct ContextBar: View {
    let context: AgentsActivityContext

    private static let width: CGFloat = 36
    private static let height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(AgentsPalette.contextTrack)
            .overlay(alignment: .leading) {
                if context.leftPercent > 0 {
                    Capsule()
                        .fill(AgentsPalette.contextColor(isBlocked: context.isBlocked))
                        .frame(width: max(Self.height, Self.width * context.fraction))
                }
            }
            .frame(width: Self.width, height: Self.height)
            .accessibilityElement()
            .accessibilityLabel("\(context.leftPercent)% de contexto livre")
    }
}
