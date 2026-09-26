import MochaClient
import MochaProtocol
import SwiftUI

struct ChatScreen: View {
    let session: AppSession
    let target: ChatTarget

    var body: some View {
        ChatConversation(session: session, target: target)
            .id(target)
    }
}

struct ChatConversation: View {
    @Bindable var session: AppSession
    let target: ChatTarget
    @State private var list = ChatListModel()
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isPinnedToBottom = true
    @State private var isAtBottom = true
    @State private var isUserScrolling = false
    @State private var viewport = ChatViewportTracker()
    @State private var draft = ""
    @State private var attachments = ComposerAttachments()
    @State private var isComposing = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        chatList
            .background(Palette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, Metrics.floatingMargin)
                    .padding(.top, Metrics.headerTopInset)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .padding(.horizontal, Metrics.floatingMargin)
                    .padding(.bottom, Metrics.composerBottomInset)
            }
            .onChange(of: chat?.items ?? [], initial: true) { _, items in
                itemsChanged(items)
            }
            .onChange(of: chat?.isLoading ?? false) { wasLoading, isLoading in
                guard wasLoading, !isLoading, chat?.failure == nil else { return }
                list.pageReplaced()
                pinToBottom()
            }
            .onChange(of: isFieldFocused) { _, isFocused in
                if !isFocused { isComposing = false }
            }
            .onChange(of: foregroundReport, initial: true) {
                reportForeground()
            }
            .onDisappear { reportForeground() }
            .task { await runDebugLaunch() }
    }

    private var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if chat?.hasMore == true {
                    OlderItemsLoader()
                        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                            if isVisible { loadOlderItems() }
                        }
                }
                ForEach(list.rows) { row in
                    SignpostedRowLayout(kind: row.signpostKind) {
                        ChatRowView(row: row, model: chat?.meta?.model, isExpanded: list.isExpanded(row.id)) {
                            list.toggleExpansion(row.id)
                        }
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                    .padding(.bottom, list.spacingBelow(row))
                    .modifier(OlderPageTrigger(isActive: row.id == list.prefetchRowId && chat?.hasMore == true, onVisible: loadOlderItems))
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .scrollView(axis: .vertical)) }) { frame in
                        viewport.rowFrames[row.id] = frame
                    }
                    .onDisappear { viewport.rowFrames[row.id] = nil }
                }
                ForEach(list.pending.bubbles) { bubble in
                    PendingBubbleRow(bubble: bubble) { list.discardPending(bubble.id) }
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                if showsWorkingLine {
                    WorkingStatusLine(startedAt: agent?.turnStartedAt, canStop: isConnected) { stop() }
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                if let failure = chat?.failure {
                    ChatNoticeText(text: failure.message)
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                } else if isLoadingFirstPage {
                    OlderItemsLoader()
                }
                Color.clear
                    .frame(height: ChatScreenLayout.bottomAnchorHeight)
                    .id(ChatScreenLayout.bottomAnchorId)
            }
            .scrollTargetLayout()
        }
        .contentMargins(.top, Metrics.listItemSpacing, for: .scrollContent)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded { dismissComposer() })
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: ChatScrollMetrics.self, of: ChatScrollMetrics.init) { old, new in
            scrollMetricsChanged(from: old, to: new)
        }
        .overlay(alignment: .bottomTrailing) { jumpButton }
    }

    private var header: some View {
        ChatHeaderBar(
            indicator: indicator,
            title: title,
            subtitle: subtitle,
            onStatusTap: { session.closeChat() },
            onTitleTap: { session.showDetail(liveTarget) },
            onOpenDrawer: {
                dismissComposer()
                session.openDrawer()
            }
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isReadOnly {
            ReadOnlyComposerPill()
        } else {
            ChatComposer(draft: $draft, isExpanded: $isComposing, isFocused: $isFieldFocused, attachments: attachments, onSend: send)
        }
    }

    private var jumpButton: some View {
        ZStack {
            if showsJumpButton {
                GlassRoundButton(systemImage: "arrow.down.to.line", accessibilityLabel: "Ir para o fim", style: .chat) {
                    jumpToBottom()
                }
                .transition(.opacity)
            }
        }
        .padding(.trailing, Metrics.floatingMargin)
        .padding(.bottom, ChatScreenLayout.jumpButtonGap)
        .animation(.smooth(duration: 0.2), value: showsJumpButton)
    }

    private var chat: ChatState? {
        session.chat(for: target)
    }

    private var liveTarget: ChatTarget {
        chat?.target ?? target
    }

    private var isReadOnly: Bool {
        if case .session = liveTarget { true } else { false }
    }

    private var isConnected: Bool {
        session.connectionState == .connected
    }

    private var isLoadingFirstPage: Bool {
        guard let chat else { return true }
        return chat.isLoading && chat.items.isEmpty
    }

    private var agent: AgentSummary? {
        guard case .agent(let agentId) = liveTarget else { return nil }
        return session.workspaces.agent(withId: agentId)
    }

    private var archived: ArchivedSession? {
        guard case .session(let sessionId) = liveTarget else { return nil }
        return session.archivedSessions.first { $0.id == sessionId }
    }

    private var status: AgentStatus {
        chat?.meta?.status ?? agent?.status ?? .unknown
    }

    private var showsWorkingLine: Bool {
        !isReadOnly && status == .working
    }

    private var showsJumpButton: Bool {
        !isPinnedToBottom && !isAtBottom && !(chat?.items.isEmpty ?? true)
    }

    private var indicator: StatusIndicator {
        guard isConnected else { return .disconnected }
        if isReadOnly { return .archived }
        return .agent(status)
    }

    private var title: String {
        chat?.meta?.title ?? agent?.title ?? archived?.title ?? ""
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

    private func itemsChanged(_ items: [ChatItem]) {
        switch list.apply(items) {
        case .replaced:
            pinToBottom()
        case .prepended:
            keepViewportAfterPrepend()
        case .unchanged, .appended:
            break
        }
    }

    private func scrollMetricsChanged(from old: ChatScrollMetrics, to new: ChatScrollMetrics) {
        viewport.visibleHeight = new.containerHeight
        if isAtBottom != new.isAtBottom {
            isAtBottom = new.isAtBottom
        }
        if isUserScrolling {
            if isPinnedToBottom != new.isAtBottom {
                isPinnedToBottom = new.isAtBottom
            }
            return
        }
        if isPinnedToBottom, !new.isAtBottom, new.layoutDiffers(from: old) {
            scrollToBottom()
        }
    }

    private func keepViewportAfterPrepend() {
        guard !isPinnedToBottom, let anchor = viewport.topVisibleRowAnchor() else { return }
        position.scrollTo(id: anchor.rowId, anchor: anchor.point)
    }

    private func pinToBottom() {
        isPinnedToBottom = true
        scrollToBottom()
    }

    private func jumpToBottom() {
        isPinnedToBottom = true
        withAnimation(.smooth(duration: 0.3)) {
            scrollToBottom()
        }
    }

    private func scrollToBottom() {
        position.scrollTo(id: ChatScreenLayout.bottomAnchorId, anchor: .bottom)
    }

    private func loadOlderItems() {
        guard !isPinnedToBottom else { return }
        #if DEBUG
        if let delay = ChatDebugOptions.current().olderPageDelay {
            Task {
                try? await Task.sleep(for: delay)
                session.loadOlderItems()
            }
            return
        }
        #endif
        session.loadOlderItems()
    }

    private func dismissComposer() {
        guard isFieldFocused || isComposing else { return }
        isFieldFocused = false
        isComposing = false
    }

    private func send() {
        let text = ComposerDraft.trimmed(draft)
        guard !attachments.isProcessing, !text.isEmpty || !attachments.isEmpty else { return }
        let sent = attachments.takeAll()
        draft = ""
        dismissComposer()
        submit(text, attachments: sent)
    }

    private func submit(_ text: String, attachments sent: [ComposerAttachment]) {
        guard let bubble = list.addPending(text, imageCount: sent.count) else { return }
        pinToBottom()
        Task {
            do {
                try await session.sendPrompt(text, images: sent.compactMap(\.image))
            } catch AppSessionError.uploadFailed {
                list.rejectPending(bubble.id)
                restoreComposer(text, attachments: sent)
            } catch {
                list.rejectPending(bubble.id)
            }
        }
    }

    private func restoreComposer(_ text: String, attachments restored: [ComposerAttachment]) {
        attachments.restore(restored)
        draft = [text, draft].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func stop() {
        Task { try? await session.interrupt() }
    }

    private var foregroundReport: ForegroundReport {
        ForegroundReport(agentId: ForegroundReport.agentId(of: session.visibleChat?.target), isConnected: isConnected)
    }

    private func reportForeground() {
        guard isConnected else { return }
        let agentId = ForegroundReport.agentId(of: session.visibleChat?.target)
        Task { try? await session.request(.setForeground(agentId: agentId, isActive: true)) }
    }

    private func runDebugLaunch() async {
        #if DEBUG
        let options = ChatDebugOptions.current()
        while !isReadyForDebugLaunch {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let sessionId = options.openSessionId, ChatDebugLaunch.consume(ChatDebugOptions.openSessionKey) {
            session.openChat(.session(sessionId))
            return
        }
        if let text = options.draft, ChatDebugLaunch.consume(ChatDebugOptions.draftKey) {
            draft = text
        }
        if let count = options.attachSampleCount, ChatDebugLaunch.consume(ChatDebugOptions.attachSamplesKey) {
            attachments.add(ComposerSampleImages.loaders(count: count))
            while attachments.isProcessing, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        if options.focusComposer, ChatDebugLaunch.consume(ChatDebugOptions.focusComposerKey) {
            isComposing = true
        }
        if let itemId = options.expandToolItemId, ChatDebugLaunch.consume(ChatDebugOptions.expandToolKey), let rowId = list.rowId(forItem: itemId) {
            list.expand(rowId)
        }
        if let itemId = options.scrollToItemId, ChatDebugLaunch.consume(ChatDebugOptions.scrollToKey), let rowId = list.rowId(forItem: itemId) {
            try? await Task.sleep(for: .milliseconds(300))
            isPinnedToBottom = false
            await walkUp(to: rowId, anchor: options.scrollAnchor)
        }
        if let text = options.sendText, ChatDebugLaunch.consume(ChatDebugOptions.sendKey) {
            submit(text, attachments: attachments.takeAll())
        }
        if options.performanceSweep, ChatDebugLaunch.consume(ChatDebugOptions.performanceSweepKey) {
            await runPerformanceSweep()
        }
        #endif
    }

    #if DEBUG
    private func walkUp(to rowId: String, anchor: UnitPoint) async {
        var index = list.rows.count - 1
        while let targetIndex = list.rows.firstIndex(where: { $0.id == rowId }), index > targetIndex, !Task.isCancelled {
            index = max(targetIndex, index - Self.sweepStep)
            position.scrollTo(id: list.rows[index].id, anchor: anchor)
            try? await Task.sleep(for: .milliseconds(60))
        }
        position.scrollTo(id: rowId, anchor: anchor)
    }

    private var isReadyForDebugLaunch: Bool {
        guard let chat else { return false }
        return !chat.isLoading && chat.failure == nil && !list.rows.isEmpty
    }

    private func runPerformanceSweep() async {
        ChatSignposts.logger.info("chat sweep started with \(list.rows.count, privacy: .public) rows")
        isPinnedToBottom = false
        var currentRowId = list.rows.last?.id
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(80))
            let rows = list.rows
            guard !rows.isEmpty else { continue }
            let index = currentRowId.flatMap { id in rows.firstIndex { $0.id == id } } ?? rows.count - 1
            if index == 0 {
                guard chat?.hasMore == true else { break }
                session.loadOlderItems()
                continue
            }
            let next = max(0, index - Self.sweepStep)
            currentRowId = rows[next].id
            position.scrollTo(id: rows[next].id, anchor: .top)
        }
        ChatSignposts.logger.info("chat sweep finished with \(list.rows.count, privacy: .public) rows")
    }

    private static let sweepStep = 4
    #endif
}

enum ChatScreenLayout {
    static let jumpButtonGap: CGFloat = 8
    static let bottomAnchorId = "chat-bottom"
    static let bottomAnchorHeight: CGFloat = 1
}

struct OlderPageTrigger: ViewModifier {
    let isActive: Bool
    let onVisible: () -> Void

    func body(content: Content) -> some View {
        if isActive {
            content.onScrollVisibilityChange(threshold: 0.1) { isVisible in
                if isVisible { onVisible() }
            }
        } else {
            content
        }
    }
}

struct ForegroundReport: Equatable {
    let agentId: AgentID?
    let isConnected: Bool

    static func agentId(of target: ChatTarget?) -> AgentID? {
        guard case .agent(let agentId) = target else { return nil }
        return agentId
    }
}

@MainActor
final class ChatViewportTracker {
    var visibleHeight: CGFloat = 0
    var rowFrames: [String: CGRect] = [:]

    func topVisibleRowAnchor() -> (rowId: String, point: UnitPoint)? {
        let candidates = rowFrames.filter { $0.value.minY >= 0 && $0.value.minY < visibleHeight }
        guard let (rowId, frame) = candidates.min(by: { $0.value.minY < $1.value.minY }) else { return nil }
        let freeHeight = visibleHeight - frame.height
        guard freeHeight > 1 else { return (rowId, .top) }
        return (rowId, UnitPoint(x: 0.5, y: frame.minY / freeHeight))
    }
}

struct ChatScrollMetrics: Equatable {
    static let bottomTolerance: CGFloat = 24

    let isAtBottom: Bool
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let bottomInset: CGFloat

    init(_ geometry: ScrollGeometry) {
        let visibleBottom = geometry.contentOffset.y + geometry.contentInsets.top + geometry.containerSize.height
        isAtBottom = visibleBottom >= geometry.contentSize.height - Self.bottomTolerance
        contentHeight = geometry.contentSize.height.rounded()
        containerHeight = geometry.containerSize.height.rounded()
        bottomInset = geometry.contentInsets.bottom.rounded()
    }

    func layoutDiffers(from other: ChatScrollMetrics) -> Bool {
        contentHeight != other.contentHeight || containerHeight != other.containerHeight || bottomInset != other.bottomInset
    }
}
