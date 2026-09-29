import SwiftUI

struct DictationWaveformView: View {
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2.5
    private static let dotSize: CGFloat = 3

    let waveform: DictationWaveform

    var body: some View {
        Canvas { context, size in
            let pitch = Self.barWidth + Self.barSpacing
            let slots = Int((size.width + Self.barSpacing) / pitch)
            let levels = Array(waveform.levels.suffix(slots))
            for slot in 0..<slots {
                let index = levels.count - 1 - slot
                let level = index >= 0 ? CGFloat(levels[index]) : 0
                let barHeight = Self.dotSize + level * (size.height - Self.dotSize)
                let rect = CGRect(
                    x: size.width - Self.barWidth - CGFloat(slot) * pitch,
                    y: (size.height - barHeight) / 2,
                    width: Self.barWidth,
                    height: barHeight
                )
                context.fill(Capsule().path(in: rect), with: .color(Palette.textSecondary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Ditado em andamento")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
