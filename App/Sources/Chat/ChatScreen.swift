import MochaClient
import MochaProtocol
import SwiftUI

struct ChatScreen: View {
    @Bindable var session: AppSession
    let target: ChatTarget
    @State private var draft = ""
    @State private var isComposing = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.listItemSpacing) {
                if chat?.hasMore == true {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear { session.loadOlderItems() }
                }
                ForEach(chat?.items ?? []) { item in
                    if let line = Self.placeholderLine(for: item.kind) {
                        Text(line)
                            .chatBodyStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let failure = chat?.failure {
                    Text(failure.message)
                        .chatText()
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.vertical, Metrics.listItemSpacing)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.immediately)
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatHeaderBar(
                indicator: indicator,
                title: title,
                subtitle: subtitle,
                onStatusTap: { session.closeChat() },
                onTitleTap: { session.showDetail(chat?.target ?? target) },
                onOpenDrawer: {
                    isFieldFocused = false
                    session.openDrawer()
                }
            )
            .padding(.horizontal, Metrics.floatingMargin)
            .padding(.top, Metrics.headerTopInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
                .padding(.horizontal, Metrics.floatingMargin)
                .padding(.bottom, Metrics.composerBottomInset)
        }
    }

    @ViewBuilder
    private var composer: some View {
        if chat?.isReadOnly == true || isArchivedTarget {
            Text("Sessão encerrada · só leitura")
                .font(Typography.composer)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.composerHeight)
                .mochaGlass(.composer, in: Capsule())
        } else if isComposing {
            ExpandedComposer(canSend: canSend, onSend: send) {
                ComposerTextField(text: $draft)
                    .focused($isFieldFocused)
            }
            .onAppear { isFieldFocused = true }
            .onChange(of: isFieldFocused) { _, focused in
                if !focused { isComposing = false }
            }
        } else {
            CollapsedComposer(draft: draft, onExpand: { isComposing = true }, onSend: send)
        }
    }

    private var chat: ChatState? {
        session.chat(for: target)
    }

    private var liveTarget: ChatTarget {
        chat?.target ?? target
    }

    private var isArchivedTarget: Bool {
        if case .session = liveTarget { true } else { false }
    }

    private var agent: AgentSummary? {
        guard case .agent(let agentId) = liveTarget else { return nil }
        return session.workspaces.agent(withId: agentId)
    }

    private var archived: ArchivedSession? {
        guard case .session(let sessionId) = liveTarget else { return nil }
        return session.archivedSessions.first { $0.id == sessionId }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var indicator: StatusIndicator {
        guard session.connectionState == .connected else { return .disconnected }
        if isArchivedTarget { return .archived }
        return .agent(chat?.meta?.status ?? agent?.status ?? .unknown)
    }

    private var title: String {
        chat?.meta?.title ?? agent?.title ?? archived?.title ?? "ChatScreen"
    }

    private var subtitle: String {
        if let meta = chat?.meta {
            return ChatSubtitle.text(workspace: meta.workspaceLabel, model: meta.model, branch: meta.branch)
        }
        if let agent {
            return ChatSubtitle.text(workspace: agent.workspaceLabel, model: agent.model, branch: agent.branch)
        }
        if let archived {
            return ChatSubtitle.text(workspace: archived.workspaceLabel, model: archived.model, branch: archived.branch)
        }
        return session.connectionState.statusText
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isFieldFocused = false
        isComposing = false
        Task { try? await session.sendPrompt(text) }
    }

    private static func placeholderLine(for kind: ChatItemKind) -> String? {
        switch kind {
        case .userPrompt(let text, _): "› " + text
        case .slashCommand(let name, let args, _): [name, args].filter { !$0.isEmpty }.joined(separator: " ")
        case .assistantText(let markdown): markdown
        case .thinking: "Pensou"
        case .toolCall(let call): "\(ToolPresentation.displayName(for: call.name)) \(call.summary)"
        case .turnFooter(let durationMs): "Brewed for \(TurnDuration.text(milliseconds: durationMs))"
        case .recap(let text): "Recap: " + text
        case .notice(let text): text
        case .unsupported: nil
        }
    }
}
