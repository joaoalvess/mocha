import MochaClient
import MochaProtocol
import SwiftUI

enum PendingCardHeading {
    case chat
    case inbox(agentTitle: String, workspace: String?, onOpenAgent: () -> Void)
}

enum PendingCardStyle {
    static let cornerRadius: CGFloat = 18
    static let borderOpacity = 0.3
    static let choiceBorder = Color(hex: 0x5E646B)
    static let onAccent = Color(hex: 0x021402)
    static let disabledOpacity = 0.45
}

struct PendingRequestCard: View {
    let request: PendingRequest
    let heading: PendingCardHeading
    let isSending: Bool
    let failure: String?
    let onRespond: (PendingResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PendingCardHeader(request: request, heading: heading)
            switch request.kind {
            case .permission(let toolName, let summary, let inputJSON):
                PendingPermissionBody(
                    text: PendingText.permission(toolName: toolName, summary: summary, inputJSON: inputJSON),
                    isSending: isSending,
                    onRespond: onRespond
                )
            case .question(let questions):
                PendingQuestionBody(questions: questions, isSending: isSending, onRespond: onRespond)
            }
            if let failure {
                Text(failure)
                    .font(Typography.toolCard)
                    .linePitch(16, size: Typography.toolCardSize)
                    .foregroundStyle(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Palette.toolCard))
        .overlay(shape.strokeBorder(Palette.dirty.opacity(PendingCardStyle.borderOpacity), lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PendingCardStyle.cornerRadius, style: .circular)
    }
}

private struct PendingCardHeader: View {
    let request: PendingRequest
    let heading: PendingCardHeading

    var body: some View {
        HStack(spacing: 7) {
            PendingGlyph(kind: PendingGlyphKind(request.kind))
            title
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(meta(now: context.date))
                    .font(Typography.toolCard)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .frame(minHeight: 18)
        .padding(.leading, 2)
    }

    @ViewBuilder
    private var title: some View {
        switch heading {
        case .chat:
            titleText(PendingText.header(for: request.kind))
                .accessibilityAddTraits(.isHeader)
        case .inbox(let agentTitle, _, let onOpenAgent):
            Button(action: onOpenAgent) {
                titleText(agentTitle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Abre o chat")
        }
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(Typography.toolCardName)
            .foregroundStyle(Palette.dirty)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func meta(now: Date) -> String {
        switch heading {
        case .chat:
            PendingText.age(from: request.createdAt, now: now)
        case .inbox(_, let workspace, _):
            PendingText.inboxMeta(workspace: workspace, createdAt: request.createdAt, now: now)
        }
    }
}

private struct PendingPermissionBody: View {
    let text: PendingPermissionText
    let isSending: Bool
    let onRespond: (PendingResponse) -> Void
    @State private var isInputExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .chatText()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .padding(.horizontal, 2)
            if let detail = text.detail {
                PendingCodeBox {
                    if text.showsPrompt {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("$ ").foregroundStyle(Palette.link)
                            Text(detail).foregroundStyle(Palette.textPrimary)
                        }
                    } else {
                        Text(detail).foregroundStyle(Palette.textPrimary)
                    }
                }
                .lineLimit(Self.detailLineLimit)
                .padding(.top, 10)
            }
            inputToggle
                .padding(.top, 8)
                .padding(.horizontal, 2)
            if isInputExpanded {
                PendingCodeBox {
                    Text(text.fullInput)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(.top, 8)
            }
            HStack(spacing: 8) {
                PendingActionButton(title: PendingText.deny, style: .secondary, isEnabled: !isSending) {
                    onRespond(.deny(reason: nil))
                }
                PendingActionButton(title: PendingText.allow, style: .primary, isEnabled: !isSending) {
                    onRespond(.allow)
                }
            }
            .padding(.top, 12)
        }
    }

    private var title: Text {
        let name = Text(text.toolName)
            .font(Typography.mono(Typography.chatBodySize, .bold))
            .foregroundStyle(Palette.textPrimary)
        let verb = Text(text.verb).foregroundStyle(Palette.textSecondary)
        return Text("\(name) \(verb)")
    }

    private var inputToggle: some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { isInputExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.2, color: Palette.textSecondary)
                    .rotationEffect(.degrees(isInputExpanded ? -90 : 90))
                Text(isInputExpanded ? PendingText.hideFullInput : PendingText.showFullInput)
                    .font(Typography.toolCard)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private static let detailLineLimit = 6
}

private struct PendingQuestionBody: View {
    let isSending: Bool
    let onRespond: (PendingResponse) -> Void
    @State private var draft: PendingAnswerDraft

    init(questions: [PendingQuestion], isSending: Bool, onRespond: @escaping (PendingResponse) -> Void) {
        self.isSending = isSending
        self.onRespond = onRespond
        _draft = State(initialValue: PendingAnswerDraft(questions: questions))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if draft.isStepped {
                steppedBody
            } else {
                singleBody
            }
        }
    }

    private var singleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(draft.questions.enumerated()), id: \.offset) { index, question in
                block(question, at: index)
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                PendingActionButton(title: PendingText.answer, style: .primary, isEnabled: draft.isComplete && !isSending) {
                    send()
                }
                .frame(width: Self.answerWidth)
            }
            .padding(.top, 12)
        }
    }

    private var steppedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            PendingQuestionStepHeader(
                text: PendingText.questionStep(header: draft.questions[draft.step].question.header, step: draft.step, total: draft.questions.count),
                step: draft.step,
                total: draft.questions.count
            )
            .padding(.top, 10)
            block(draft.questions[draft.step], at: draft.step)
                .id(draft.step)
            HStack(spacing: 8) {
                if draft.step > 0 {
                    PendingActionButton(title: PendingText.back, style: .secondary, isEnabled: !isSending) {
                        withAnimation(.smooth(duration: 0.2)) { draft.goBack() }
                    }
                    .frame(width: Self.backWidth)
                }
                Spacer(minLength: 0)
                if draft.isLastStep {
                    PendingActionButton(title: PendingText.send, style: .primary, isEnabled: draft.isComplete && !isSending) {
                        send()
                    }
                    .frame(width: Self.answerWidth)
                } else {
                    PendingActionButton(title: PendingText.next, style: .primary, isEnabled: draft.isCurrentStepAnswered && !isSending) {
                        withAnimation(.smooth(duration: 0.2)) { draft.advance() }
                    }
                    .frame(width: Self.answerWidth)
                }
            }
            .padding(.top, 12)
        }
    }

    private func block(_ question: PendingQuestionDraft, at index: Int) -> some View {
        PendingQuestionBlock(
            draft: question,
            showsHeader: false,
            onToggle: { label in
                if draft.isStepped {
                    withAnimation(.smooth(duration: 0.2)) { draft.choose(label) }
                } else {
                    draft.toggle(label, inQuestion: index)
                }
            },
            otherText: Binding(
                get: { draft.questions[index].otherText },
                set: { draft.setOtherText($0, inQuestion: index) }
            )
        )
    }

    private func send() {
        guard let response = draft.response else { return }
        onRespond(response)
    }

    private static let answerWidth: CGFloat = 130
    private static let backWidth: CGFloat = 110
}

private struct PendingQuestionStepHeader: View {
    let text: String
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(Typography.toolCard)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Palette.dirty : Palette.accessoryBar)
                        .frame(width: 22, height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(minHeight: 16)
        .padding(.horizontal, 2)
    }
}

private struct PendingQuestionBlock: View {
    let draft: PendingQuestionDraft
    let showsHeader: Bool
    let onToggle: (String) -> Void
    @Binding var otherText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader, !draft.question.header.isEmpty {
                Text(draft.question.header)
                    .font(Typography.toolCardName)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: 16)
                    .padding(.top, 9)
                    .padding(.horizontal, 2)
            }
            Text(draft.question.question)
                .chatText()
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, hasHeader ? 4 : 9)
                .padding(.horizontal, 2)
            VStack(spacing: 2) {
                ForEach(Array(draft.question.options.enumerated()), id: \.offset) { _, option in
                    PendingOptionRow(
                        option: option,
                        isMultiSelect: draft.question.multiSelect,
                        isSelected: draft.isSelected(option.label)
                    ) {
                        onToggle(option.label)
                    }
                }
            }
            .padding(.top, 10)
            TextField(PendingText.otherPlaceholder, text: $otherText, prompt: Text(PendingText.otherPlaceholder).foregroundStyle(Palette.textSecondary))
                .font(Typography.mono(13))
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.statusOk)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(Palette.codeInner))
                .padding(.top, 8)
        }
    }

    private var hasHeader: Bool {
        showsHeader && !draft.question.header.isEmpty
    }
}

private struct PendingOptionRow: View {
    let option: PendingOption
    let isMultiSelect: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                PendingChoiceMark(isMultiSelect: isMultiSelect, isSelected: isSelected)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(Typography.mono(14))
                        .linePitch(20, size: 14)
                        .foregroundStyle(Palette.textPrimary)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .systemLinePitch(16, size: 12)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(shape.fill(isSelected ? Palette.selectedRow : Color.clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .circular)
    }
}

private struct PendingChoiceMark: View {
    let isMultiSelect: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isMultiSelect {
                box
            } else {
                radio
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var radio: some View {
        if isSelected {
            Circle()
                .fill(PendingCardStyle.onAccent)
                .overlay(Circle().strokeBorder(Palette.statusOk, lineWidth: 5))
        } else {
            Circle().strokeBorder(PendingCardStyle.choiceBorder, lineWidth: 1.6)
        }
    }

    @ViewBuilder
    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .circular)
        if isSelected {
            shape
                .fill(Palette.statusOk)
                .overlay(LineIconView(icon: .check, size: 13, strokeWidth: 3, color: PendingCardStyle.onAccent))
        } else {
            shape.strokeBorder(PendingCardStyle.choiceBorder, lineWidth: 1.6)
        }
    }
}

struct PendingCodeBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(Typography.toolCard)
            .linePitch(18, size: Typography.toolCardSize)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Palette.codeInner))
    }
}

struct PendingActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let style: Style
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style == .primary ? PendingCardStyle.onAccent : Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(style == .primary ? Palette.statusOk : Palette.controlBg))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : PendingCardStyle.disabledOpacity)
    }
}
