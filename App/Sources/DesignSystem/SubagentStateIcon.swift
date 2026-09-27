import MochaProtocol
import SwiftUI

struct SubagentStateIcon: View {
    let status: SubagentStatus
    var size: CGFloat = 15

    var body: some View {
        glyph
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        switch status {
        case .running:
            ToolSpinner(diameter: size - 2)
                .accessibilityLabel("Rodando")
        case .completed:
            LineIconView(icon: .check, size: size, strokeWidth: 2, color: Palette.textSecondary)
                .accessibilityElement()
                .accessibilityLabel("Concluído")
        case .failed:
            LineIconView(icon: .xCircle, size: size, strokeWidth: 1.8, color: Palette.error)
                .accessibilityElement()
                .accessibilityLabel("Falhou")
        case .stopped:
            LineIconView(icon: .stopCircle, size: size, strokeWidth: 2, color: Palette.textSecondary)
                .accessibilityElement()
                .accessibilityLabel("Parado")
        }
    }
}
