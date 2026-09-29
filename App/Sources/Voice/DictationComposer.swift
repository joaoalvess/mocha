import SwiftUI

struct DictationComposer: View {
    let line: DictationLine?
    let waveform: DictationWaveform
    let canStop: Bool
    let canSend: Bool
    let onDiscard: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            DictationRoundButton(accessibilityLabel: "Descartar ditado", action: onDiscard) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
            }
            center
                .frame(maxWidth: .infinity, maxHeight: 30)
                .padding(.horizontal, 4)
            DictationRoundButton(accessibilityLabel: "Parar ditado", action: onStop) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .frame(width: 12, height: 12)
            }
            .disabled(!canStop)
            SendButton(isEnabled: canSend, action: onSend)
        }
        .padding(.horizontal, 6)
        .frame(height: Metrics.composerHeight)
        .mochaGlass(.composerClear, in: Capsule())
    }

    @ViewBuilder
    private var center: some View {
        if let line {
            Text(line.text)
                .font(Typography.composer)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DictationWaveformView(waveform: waveform)
        }
    }
}

private struct DictationRoundButton<Glyph: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: Metrics.sendButtonSize, height: Metrics.sendButtonSize)
                .overlay { glyph().foregroundStyle(isEnabled ? Palette.textPrimary : Palette.textSecondary) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}
