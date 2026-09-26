import SwiftUI

enum SendButtonMode: Equatable {
    case send
    case stop
}

struct ComposerBar: View {
    @Binding var text: String
    var placeholder = "Chat via Mocha…"
    var mode: SendButtonMode = .send
    var showsTerminalButton = false
    var onAttach: (() -> Void)?
    var onTerminal: (() -> Void)?
    var onSlashMenu: (() -> Void)?
    var onMicrophone: (() -> Void)?
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "Mensagem",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Palette.textSecondary),
                axis: .vertical
            )
            .font(Typography.composer)
            .foregroundStyle(Palette.textPrimary)
            .tint(Palette.textPrimary)
            .lineLimit(1...6)
            .padding(.top, Metrics.composerFieldTopPadding)
            .padding(.horizontal, Metrics.composerHorizontalPadding)
            buttonRow
                .padding(.top, Metrics.composerButtonsTopPadding)
                .padding(.bottom, Metrics.composerButtonsBottomPadding)
        }
        .mochaGlass(tint: Palette.composer, in: RoundedRectangle(cornerRadius: Metrics.composerCornerRadius, style: .continuous))
    }

    private var buttonRow: some View {
        HStack(spacing: 0) {
            ComposerIconButton(accessibilityLabel: "Anexar imagem", action: onAttach) {
                Image(systemName: "plus").font(.system(size: 19, weight: .light))
            }
            if showsTerminalButton {
                ComposerIconButton(accessibilityLabel: "Terminal", action: onTerminal) {
                    PromptIcon(width: 16, lineWidth: 1.7, color: Palette.textPrimary)
                }
            }
            ComposerIconButton(accessibilityLabel: "Comandos", action: onSlashMenu) {
                Image(systemName: "arrow.uturn.forward").font(.system(size: 17, weight: .regular))
            }
            Spacer(minLength: 0)
            ComposerIconButton(accessibilityLabel: "Ditado", action: onMicrophone) {
                Image(systemName: "mic").font(.system(size: 19, weight: .regular))
            }
            .padding(.trailing, Metrics.composerMicTrailingGap)
            SendButton(mode: mode, isEnabled: canSend) {
                switch mode {
                case .send: onSend()
                case .stop: onStop()
                }
            }
        }
        .padding(.leading, Metrics.composerIconLeadingCenter - Metrics.composerIconSpacing / 2)
        .padding(.trailing, Metrics.composerSendTrailingPadding)
    }

    private var canSend: Bool {
        switch mode {
        case .send: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stop: true
        }
    }
}

struct ComposerIconButton<Icon: View>: View {
    let accessibilityLabel: String
    let action: (() -> Void)?
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button {
            action?()
        } label: {
            icon()
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Metrics.composerIconSpacing, height: Metrics.sendButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SendButton: View {
    let mode: SendButtonMode
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isEnabled ? Palette.textPrimary : Palette.textPrimary.opacity(0.07))
                .frame(width: Metrics.sendButtonSize, height: Metrics.sendButtonSize)
                .overlay { glyph }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(mode == .send ? "Enviar" : "Parar")
    }

    @ViewBuilder
    private var glyph: some View {
        switch mode {
        case .send:
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(isEnabled ? Palette.glyphOnAccent : Palette.textSecondary)
        case .stop:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.glyphOnAccent)
                .frame(width: 11, height: 11)
        }
    }
}
