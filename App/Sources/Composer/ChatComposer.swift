import SwiftUI

struct ChatComposer: View {
    @Binding var draft: String
    @Binding var isExpanded: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        if isExpanded {
            ExpandedComposer(canSend: canSend, onSend: onSend) {
                ComposerTextField(text: $draft)
                    .focused(isFocused)
            }
            .onAppear { isFocused.wrappedValue = true }
        } else {
            CollapsedComposer(draft: draft, onExpand: { isExpanded = true }, onSend: onSend)
        }
    }

    private var canSend: Bool {
        !ComposerDraft.trimmed(draft).isEmpty
    }
}

struct ReadOnlyComposerPill: View {
    var body: some View {
        Text("Sessão encerrada · só leitura")
            .font(Typography.composer)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.composerHeight)
            .mochaGlass(.composer, in: Capsule())
    }
}

enum ComposerDraft {
    static func trimmed(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
