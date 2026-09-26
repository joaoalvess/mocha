import MochaProtocol
import SwiftUI

enum StatusIndicator: Equatable {
    case agent(AgentStatus)
    case disconnected
    case archived

    var color: Color {
        switch self {
        case .agent(.idle), .agent(.done), .agent(.working):
            Palette.statusOk
        case .agent(.blocked):
            Palette.dirty
        case .agent(.unknown), .disconnected, .archived:
            Palette.textSecondary
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
        case .archived: "Sessão encerrada"
        }
    }
}

struct StatusDot: View {
    let indicator: StatusIndicator
    var diameter: CGFloat = Metrics.statusDotSize

    var body: some View {
        disc
            .background {
                if indicator.pulses {
                    PulseGlow(diameter: diameter, color: indicator.color)
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
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.glyphOnAccent)
                    .frame(width: diameter * 0.425, height: diameter * 0.1)
            }
    }
}

private struct PulseGlow: View {
    let diameter: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .phaseAnimator([false, true]) { content, expanded in
                content
                    .background {
                        Circle()
                            .fill(color.opacity(expanded ? 0.2 : 0.12))
                            .padding(expanded ? -6 : -3)
                    }
                    .shadow(color: color.opacity(expanded ? 0.45 : 0.25), radius: expanded ? 8 : 4)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
    }
}
