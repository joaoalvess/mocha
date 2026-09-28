import SwiftUI

struct UsageBar: View {
    let fraction: Double
    var paceFraction: Double?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.barTrack)
                    .frame(height: height)
                Capsule()
                    .fill(Palette.usageBarFill)
                    .frame(width: proxy.size.width * clamped(fraction), height: height)
            }
            .overlay(alignment: .leading) {
                if let paceFraction {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.paceMark)
                        .frame(width: 2, height: height + 4)
                        .offset(x: proxy.size.width * clamped(paceFraction))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((clamped(fraction) * 100).rounded()))%")
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
