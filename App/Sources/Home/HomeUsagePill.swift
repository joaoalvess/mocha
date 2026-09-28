import MochaClient
import SwiftUI

struct HomeUsagePill: View {
    let windows: [UsageWindowSummary]
    let isDimmed: Bool
    let action: () -> Void

    private static let height: CGFloat = 38
    private static let dimmedOpacity = 0.45

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                claude
                    .opacity(isDimmed ? Self.dimmedOpacity : 1)
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

    private var claude: some View {
        HStack(spacing: 0) {
            ClaudeMark(size: 16)
                .padding(.trailing, 7)
            Text(Self.claudeName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.claude)
                .padding(.trailing, 10)
            UsageBar(fraction: windows.first?.usedFraction ?? 0, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private static let claudeName = "Claude"
}
