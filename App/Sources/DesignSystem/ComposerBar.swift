import MochaClient
import SwiftUI

struct ComposerButtons: OptionSet {
    let rawValue: Int

    static let attach = ComposerButtons(rawValue: 1 << 0)
    static let slashMenu = ComposerButtons(rawValue: 1 << 1)
    static let microphone = ComposerButtons(rawValue: 1 << 2)
}

struct CollapsedComposer: View {
    let draft: String
    var placeholder = ComposerText.placeholder
    var sendMode: ComposerSendMode = .send
    var onExpand: () -> Void = {}
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onExpand) {
                Text(hasDraft ? firstLine : placeholder)
                    .font(Typography.composer)
                    .foregroundStyle(hasDraft ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasDraft ? "Rascunho: \(draft)" : placeholder)
            .accessibilityHint("Abre o composer")
            SendButton(isEnabled: hasDraft, mode: sendMode, action: onSend, onStop: onStop)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: Metrics.composerHeight)
        .mochaGlass(.composer, in: Capsule())
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
    var onAttach: () -> Void = {}
    var onSlashMenu: () -> Void = {}
    var onMicrophone: () -> Void = {}
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field()
                .padding(.horizontal, 16)
            HStack(spacing: 0) {
                if buttons.contains(.attach) {
                    ComposerIconButton(systemImage: "plus", accessibilityLabel: "Anexar imagem", action: onAttach)
                }
                if buttons.contains(.slashMenu) {
                    ComposerIconButton(lineIcon: .redo, accessibilityLabel: "Controles", isActive: activeButtons.contains(.slashMenu), action: onSlashMenu)
                }
                Spacer(minLength: 0)
                if buttons.contains(.microphone) {
                    ComposerIconButton(
                        systemImage: "mic",
                        accessibilityLabel: activeButtons.contains(.microphone) ? "Parar ditado" : "Ditado",
                        isActive: activeButtons.contains(.microphone),
                        action: onMicrophone
                    )
                }
                SendButton(isEnabled: canSend, mode: sendMode, action: onSend, onStop: onStop)
                    .padding(.leading, 4)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 44)
        }
        .padding(.top, 13)
        .padding(.bottom, 6)
        .mochaGlass(.composer, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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

struct SendButton: View {
    let isEnabled: Bool
    var mode: ComposerSendMode = .send
    let action: () -> Void
    var onStop: () -> Void = {}

    var body: some View {
        Button(action: mode == .stop ? onStop : action) {
            Circle()
                .fill(isLit ? Palette.textPrimary : Palette.sendDisabled)
                .frame(width: Metrics.sendButtonSize, height: Metrics.sendButtonSize)
                .overlay { glyph }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!isLit)
        .accessibilityLabel(mode == .stop ? "Parar" : "Enviar")
    }

    private var isLit: Bool {
        mode == .stop || isEnabled
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
        }
    }
}
