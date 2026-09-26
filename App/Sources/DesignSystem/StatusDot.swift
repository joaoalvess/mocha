import MochaProtocol
import SwiftUI

enum StatusIndicator: Equatable {
    case agent(AgentStatus)
    case disconnected

    var color: Color {
        switch self {
        case .agent(.idle), .agent(.done), .agent(.working):
            Palette.statusOk
        case .agent(.blocked):
            Palette.dirty
        case .agent(.unknown), .disconnected:
            Palette.textSecondary
        }
    }

    var showsIdleGlyph: Bool {
        switch self {
        case .agent(.idle), .agent(.done), .agent(.working):
            true
        case .agent(.blocked), .agent(.unknown), .disconnected:
            false
        }
    }

    var pulses: Bool {
        self == .agent(.working)
    }

    var accessibilityLabel: String {
        switch self {
        case .agent(.idle): "Ocioso"
        case .agent(.done): "Concluído"
        case .agent(.working): "Trabalhando"
        case .agent(.blocked): "Esperando você"
        case .agent(.unknown): "Estado desconhecido"
        case .disconnected: "Sem conexão"
        }
    }
}

struct StatusDot: View {
    let indicator: StatusIndicator
    var diameter: CGFloat = Metrics.statusDotSize

    var body: some View {
        Group {
            if indicator.pulses {
                disc.phaseAnimator([1.0, 0.35]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            } else {
                disc
            }
        }
        .accessibilityElement()
        .accessibilityLabel(indicator.accessibilityLabel)
    }

    private var disc: some View {
        Circle()
            .fill(indicator.color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if indicator.showsIdleGlyph {
                    Capsule()
                        .fill(Palette.glyphOnAccent)
                        .frame(width: diameter * 0.44, height: max(1, diameter * 0.08))
                }
            }
    }
}
