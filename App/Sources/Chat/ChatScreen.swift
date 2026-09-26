import MochaProtocol
import SwiftUI

struct ChatScreen: View {
    @Bindable var session: AppSession
    let agentId: AgentID
    @State private var draft = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
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
                        .font(Typography.chatBody)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, Metrics.contentMargin)
        }
        .defaultScrollAnchor(.bottom)
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatHeaderBar(
                indicator: indicator,
                title: title,
                subtitle: subtitle,
                onOpenDrawer: { session.isDrawerOpen = true }
            )
            .padding(.horizontal, Metrics.floatingMargin)
            .padding(.top, Metrics.headerTopInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerBar(
                text: $draft,
                mode: isWorking && draft.isEmpty ? .stop : .send,
                onSend: send,
                onStop: stop
            )
            .padding(.horizontal, Metrics.floatingMargin)
            .padding(.bottom, Metrics.composerBottomInset)
        }
    }

    private var chat: VisibleChat? {
        session.visibleChat?.agentId == agentId ? session.visibleChat : nil
    }

    private var agent: AgentSummary? {
        session.workspaces.agent(withId: agentId)
    }

    private var isWorking: Bool {
        (chat?.meta?.status ?? agent?.status) == .working
    }

    private var indicator: StatusIndicator {
        guard session.connectionState == .connected else { return .disconnected }
        return .agent(chat?.meta?.status ?? agent?.status ?? .unknown)
    }

    private var title: String {
        chat?.meta?.title ?? agent?.title ?? agentId
    }

    private var subtitle: String {
        if let meta = chat?.meta {
            return ChatSubtitle.text(workspace: meta.workspaceLabel, model: meta.model, branch: meta.branch)
        }
        guard let agent else { return session.connectionState.statusText }
        return ChatSubtitle.text(workspace: agent.workspaceLabel, model: agent.model, branch: agent.branch)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { try? await session.sendPrompt(text) }
    }

    private func stop() {
        Task { try? await session.interrupt() }
    }

    private static func placeholderLine(for kind: ChatItemKind) -> String? {
        switch kind {
        case .userPrompt(let text, _): "› " + text
        case .slashCommand(let name, let args, _): [name, args].filter { !$0.isEmpty }.joined(separator: " ")
        case .assistantText(let markdown): markdown
        case .thinking: "Pensou"
        case .toolCall(let call): "\(call.name) \(call.summary)"
        case .turnFooter(let durationMs): "Brewed for \(durationMs / 1_000)s"
        case .recap(let text): "Recap: " + text
        case .notice(let text): text
        case .unsupported: nil
        }
    }
}
