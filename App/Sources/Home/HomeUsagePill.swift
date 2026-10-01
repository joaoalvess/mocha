import MochaClient
import MochaProtocol
import SwiftUI

struct HomeUsageEntry {
    let provider: AgentProvider
    let windows: [UsageWindowSummary]
}

struct HomeUsagePill: View {
    let usages: [HomeUsageEntry]
    let isDimmed: Bool
    let action: () -> Void

    private static let height: CGFloat = 38
    private static let dimmedOpacity = 0.45
    private static let leadingPadding: CGFloat = 13
    private static let trailingPadding: CGFloat = 14
    private static let markSize: CGFloat = 16
    private static let markGap: CGFloat = 5
    private static let nameGap: CGFloat = 7
    private static let dividerGap: CGFloat = 10
    private static let dividerHeight: CGFloat = 15

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                ForEach(Array(usages.enumerated()), id: \.element.provider) { index, usage in
                    if index > 0 {
                        divider
                    }
                    segment(usage)
                }
            }
            .opacity(isDimmed ? Self.dimmedOpacity : 1)
            .padding(.leading, Self.leadingPadding)
            .padding(.trailing, Self.trailingPadding)
            .frame(height: Self.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .mochaGlass(.pill, interactive: true, in: Capsule())
        .accessibilityLabel("Uso do plano")
        .accessibilityValue(accessibilityValue)
    }

    private func segment(_ usage: HomeUsageEntry) -> some View {
        HStack(spacing: 0) {
            ProviderMark(provider: usage.provider, size: Self.markSize)
                .padding(.trailing, Self.markGap)
            Text(Self.name(of: usage.provider))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(usage.provider == .codex ? Palette.codex : Palette.claude)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, Self.nameGap)
            UsageBar(fraction: usage.windows.first?.usedFraction ?? 0, height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.usagePillDivider)
            .frame(width: 1, height: Self.dividerHeight)
            .padding(.horizontal, Self.dividerGap)
    }

    private var accessibilityValue: String {
        usages.map { usage in
            let windows = usage.windows.map { "\($0.label): \($0.percentText)" }.joined(separator: ", ")
            return usages.count > 1 ? "\(Self.name(of: usage.provider)), \(windows)" : windows
        }
        .joined(separator: "; ")
    }

    private static func name(of provider: AgentProvider) -> String {
        provider == .codex ? "Codex" : "Claude"
    }
}
