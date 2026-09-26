import SwiftUI

struct OfflineCapsule: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Palette.textSecondary)
                    .frame(width: 7, height: 7)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.offlineCapsuleText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .mochaGlass(.pill, interactive: true, in: Capsule())
        .accessibilityHint("Abre os ajustes")
    }
}
