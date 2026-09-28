import MochaClient
import MochaProtocol
import SwiftUI

struct HomeUsagePill: View {
    var provider: AgentProvider = .claude
    let windows: [UsageWindowSummary]
    let isDimmed: Bool
    let action: () -> Void

    private static let height: CGFloat = 38
    private static let dimmedOpacity = 0.45

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                usage
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

    private var usage: some View {
        HStack(spacing: 0) {
            ProviderMark(provider: provider, size: 16)
                .padding(.trailing, 7)
            Text(provider == .codex ? Self.codexName : Self.claudeName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(provider == .codex ? Palette.textPrimary : Palette.claude)
                .padding(.trailing, 10)
            UsageBar(fraction: windows.first?.usedFraction ?? 0, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private static let claudeName = "Claude"
    private static let codexName = "Codex"
}
