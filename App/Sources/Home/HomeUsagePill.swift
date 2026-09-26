import MochaClient
import SwiftUI

struct HomeUsagePill: View {
    let windows: [UsageWindowSummary]
    let isDimmed: Bool
    let action: () -> Void

    private static let height: CGFloat = 38
    private static let dimmedOpacity = 0.45
    private static let dividerColor = Color.white.opacity(0.13)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 {
                        Rectangle()
                            .fill(Self.dividerColor)
                            .frame(width: 1, height: 18)
                            .padding(.horizontal, 14)
                    }
                    half(window, showsMark: index == 0)
                        .opacity(isDimmed ? Self.dimmedOpacity : 1)
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 16)
            .frame(height: Self.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .mochaGlass(.pill, interactive: true, in: Capsule())
        .accessibilityLabel("Uso do plano")
        .accessibilityValue(windows.map { "\($0.label): \($0.percentText)" }.joined(separator: ", "))
    }

    private func half(_ window: UsageWindowSummary, showsMark: Bool) -> some View {
        HStack(spacing: 0) {
            if showsMark {
                ClaudeMark(size: 16)
                    .padding(.trailing, 8)
            }
            Text(window.label)
                .font(Typography.mono(12, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)
                .padding(.trailing, 8)
            UsageBar(fraction: window.usedFraction, height: 4)
            Text(window.percentText)
                .font(Typography.mono(12, relativeTo: .caption))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity)
    }
}
