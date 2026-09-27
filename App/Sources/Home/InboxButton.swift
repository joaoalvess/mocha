import MochaClient
import SwiftUI

struct InboxButton: View {
    let count: Int
    let action: () -> Void

    static let spacing: CGFloat = 8

    private static let badgeSide: CGFloat = 18
    private static let badgeInset: CGFloat = 2

    var body: some View {
        GlassRoundButton(systemImage: "bell", accessibilityLabel: "Pedidos pendentes", style: .home, action: action)
            .overlay(alignment: .topTrailing) {
                if let badge = PendingText.badge(count) {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.glyphOnDirty)
                        .padding(.horizontal, 5)
                        .frame(minWidth: Self.badgeSide, minHeight: Self.badgeSide)
                        .background(Capsule().fill(Palette.dirty))
                        .offset(x: Self.badgeInset, y: -Self.badgeInset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue("\(count)")
    }
}
