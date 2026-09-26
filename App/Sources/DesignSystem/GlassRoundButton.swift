import SwiftUI

struct GlassRoundButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Metrics.glassRoundButtonSize, height: Metrics.glassRoundButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .mochaGlass(interactive: true, in: Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}
