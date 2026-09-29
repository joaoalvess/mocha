import MochaClient
import MochaProtocol
import SwiftUI

struct ComposerButtons: OptionSet {
    let rawValue: Int

    static let attach = ComposerButtons(rawValue: 1 << 0)
    static let slashMenu = ComposerButtons(rawValue: 1 << 1)
    static let microphone = ComposerButtons(rawValue: 1 << 2)
    static let modelPicker = ComposerButtons(rawValue: 1 << 3)
}

struct CollapsedComposer: View {
    let draft: String
    var placeholder = ComposerText.placeholder
    var sendMode: ComposerSendMode = .send
    var buttons: ComposerButtons = [.attach]
    var effort: EffortLevel?
    var onAttach: () -> Void = {}
    var onExpand: () -> Void = {}
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}
    var onMicrophone: () -> Void = {}
    var onModelPicker: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            if buttons.contains(.attach) {
                ComposerIconButton(systemImage: "plus", accessibilityLabel: "Anexar imagem", action: onAttach)
            }
            Button(action: onExpand) {
                Text(hasDraft ? firstLine : placeholder)
                    .font(Typography.composer)
                    .foregroundStyle(hasDraft ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, buttons.contains(.attach) ? 4 : 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasDraft ? "Rascunho: \(draft)" : placeholder)
            .accessibilityHint("Abre o composer")
            if buttons.contains(.modelPicker) {
                ModelPickerButton(effort: effort, action: onModelPicker)
            }
            SendButton(isEnabled: hasDraft, mode: sendMode, action: onSend, onStop: onStop, onMicrophone: onMicrophone)
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(height: Metrics.composerHeight)
        .mochaGlass(.composerClear, in: Capsule())
    }

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var firstLine: String {
        draft.split(whereSeparator: \.isNewline).first.map(String.init) ?? draft
    }
}

struct ExpandedComposer<Field: View>: View {
    let canSend: Bool
    var sendMode: ComposerSendMode = .send
    var buttons: ComposerButtons = []
    var activeButtons: ComposerButtons = []
    var effort: EffortLevel?
    var onAttach: () -> Void = {}
    var onSlashMenu: () -> Void = {}
    var onMicrophone: () -> Void = {}
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}
    var onModelPicker: () -> Void = {}
    @ViewBuilder let field: () -> Field

    private var controlInset: CGFloat { (Metrics.composerHeight - Metrics.sendButtonSize) / 2 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if buttons.contains(.attach) {
                ComposerIconButton(systemImage: "plus", accessibilityLabel: "Anexar imagem", action: onAttach)
                    .padding(.bottom, controlInset)
            }
            if buttons.contains(.slashMenu) {
                ComposerIconButton(lineIcon: .redo, accessibilityLabel: "Controles", isActive: activeButtons.contains(.slashMenu), action: onSlashMenu)
                    .padding(.bottom, controlInset)
            }
            field()
                .padding(.leading, buttons.isEmpty ? 10 : 4)
                .padding(.trailing, 8)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: Metrics.composerHeight, alignment: .leading)
            if buttons.contains(.modelPicker) {
                ModelPickerButton(effort: effort, action: onModelPicker)
                    .padding(.bottom, controlInset)
            }
            SendButton(isEnabled: canSend, mode: sendMode, action: onSend, onStop: onStop, onMicrophone: onMicrophone)
                .padding(.bottom, controlInset)
        }
        .padding(.horizontal, 6)
        .mochaGlass(.composerClear, in: RoundedRectangle(cornerRadius: Metrics.composerHeight / 2, style: .continuous))
    }
}

struct ComposerTextField: View {
    @Binding var text: String
    var placeholder = ComposerText.placeholder

    var body: some View {
        TextField(
            "Mensagem",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(Palette.textSecondary),
            axis: .vertical
        )
        .font(Typography.composer)
        .lineSpacing(Typography.lineSpacing(size: Typography.composerSize, pitch: 20))
        .foregroundStyle(Palette.textPrimary)
        .tint(Palette.statusOk)
        .lineLimit(1...6)
    }
}

enum ComposerText {
    static let placeholder = "Chat via Mocha…"
}

struct ComposerIconButton: View {
    var systemImage: String?
    var lineIcon: LineIcon?
    let accessibilityLabel: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, height: 36)
                .background(Capsule().fill(Color.white.opacity(isActive ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var glyph: some View {
        if let lineIcon {
            LineIconView(icon: lineIcon, size: 21, strokeWidth: 1.9, color: Palette.textPrimary)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
        }
    }
}

struct ModelPickerButton: View {
    let effort: EffortLevel?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EffortGaugeGlyph(fraction: EffortGauge.fraction(for: effort))
                .frame(width: 22, height: 22)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modelo")
        .accessibilityValue(effort?.rawValue ?? "")
    }
}

struct EffortGaugeGlyph: View {
    let fraction: Double

    private static let sweep: Double = 270
    private static let start: Double = 135

    var body: some View {
        Canvas { context, size in
            let lineWidth = size.width * 0.1
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - lineWidth / 2
            let end = Self.start + Self.sweep * min(max(fraction, 0), 1)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            context.stroke(arc(center: center, radius: radius, from: end, to: Self.start + Self.sweep), with: .color(Palette.textSecondary), style: style)
            context.stroke(arc(center: center, radius: radius, from: Self.start, to: end), with: .color(Palette.link), style: style)
            let angle = Angle.degrees(end).radians
            let tip = CGPoint(x: center.x + cos(angle) * radius * 0.62, y: center.y + sin(angle) * radius * 0.62)
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            context.stroke(needle, with: .color(Palette.textPrimary), style: style)
            let hub = lineWidth * 1.3
            context.stroke(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)), with: .color(Palette.textPrimary), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }

    private func arc(center: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        return path
    }
}

struct SendButton: View {
    let isEnabled: Bool
    var mode: ComposerSendMode = .send
    let action: () -> Void
    var onStop: () -> Void = {}
    var onMicrophone: () -> Void = {}

    var body: some View {
        Button(action: perform) {
            Circle()
                .fill(fill)
                .frame(width: Metrics.sendButtonSize, height: Metrics.sendButtonSize)
                .overlay { glyph }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!isLit)
        .accessibilityLabel(label)
    }

    private func perform() {
        switch mode {
        case .send: action()
        case .stop: onStop()
        case .microphone, .dictating: onMicrophone()
        }
    }

    private var isLit: Bool {
        mode != .send || isEnabled
    }

    private var fill: Color {
        switch mode {
        case .dictating: Palette.statusOk
        case .send, .stop, .microphone: isLit ? Palette.textPrimary : Palette.sendDisabled
        }
    }

    private var label: String {
        switch mode {
        case .send: "Enviar"
        case .stop: "Parar"
        case .microphone: "Ditado"
        case .dictating: "Parar ditado"
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch mode {
        case .send:
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? Palette.bg : Palette.textSecondary)
        case .stop:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Palette.bg)
                .frame(width: 12, height: 12)
        case .microphone:
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.bg)
        case .dictating:
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.glyphOnAccent)
                .symbolEffect(.variableColor.iterative)
        }
    }
}
