import MochaClient
import SwiftUI

struct RespondButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                PendingGlyph(kind: .exclamation, size: 19, strokeWidth: 2, color: Palette.dirty)
                Text(PendingText.answer)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Palette.toolCard))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Abre o pedido no chat")
    }
}
