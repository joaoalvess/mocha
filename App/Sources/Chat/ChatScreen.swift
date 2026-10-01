import CoreGraphics
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
    @State private var isConfirmingClear = false
    @State private var listGeneration = 0
    @State private var isModelPickerOpen = false
    @State private var modelOverride = ControlOverride<ModelAlias>()
    @State private var effortOverride = ControlOverride<EffortLevel>()
    @State private var modeOverride = ControlOverride<PermissionModeTarget>()
    @State private var toast: ControlToastMessage?
    @State private var imageViewer = ChatImageViewerPresenter()
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
            .overlay { clearConfirmation }
            .environment(\.chatImageCache, session.imageCache)
            .environment(\.chatImageViewer, imageViewer)
            .fullScreenCover(item: $imageViewer.selection) { selection in
                ImageViewerScreen(path: selection.path, cache: session.imageCache, onClose: imageViewer.close)
            }
            .onChange(of: imageViewer.selection) { _, selection in
                guard selection != nil else { return }
                dismissComposer()
                closeModelPicker()
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
            .onChange(of: isComposing) { _, composing in
                if composing { closeModelPicker() }
            }
            .onChange(of: confirmedModel) { modelOverride.confirmedChanged() }
            .onChange(of: confirmedEffort) { effortOverride.confirmedChanged() }
            .onChange(of: confirmedMode) { modeOverride.confirmedChanged() }
            .task(id: toast) { await expireToast() }
            .onChange(of: session.pendingReveal, initial: true) { _, agentId in
                revealPendingRequest(agentId)
            }
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
                if let notice = subagentTopNotice {
                    ChatNoticeText(text: notice)
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                ForEach(list.rows) { row in
                    SignpostedRowLayout(kind: row.signpostKind) {
                        ChatRowView(
                            row: row,
                            model: chat?.meta?.model,
                            isExpanded: list.isExpanded(row.id),
                            onToggle: { list.toggleExpansion(row.id) },
                            onOpenSubagent: openSubagent
                        )
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
                    PendingBubbleRow(bubble: bubble, thumbnails: list.pendingThumbnails[bubble.id]) { list.discardPending(bubble.id) }
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                if let pendingRequest {
                    PendingChatCard(session: session, request: pendingRequest)
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                if let footer = subagentCompletedFooter {
                    SubagentCompletedFooter(text: footer)
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                if let reason = subagentFailureNotice {
                    ChatNoticeText(text: reason)
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, ChatRowSpacing.standard)
                }
                if showsWorkingLine {
                    WorkingStatusLine(provider: provider, startedAt: agent?.turnStartedAt, canStop: isConnected && controlAvailable) { stop() }
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
        .id(listGeneration)
        .contentMargins(.top, Metrics.listItemSpacing, for: .scrollContent)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(TapGesture().onEnded {
            dismissComposer()
            closeModelPicker()
        })
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: ChatScrollMetrics.self, of: ChatScrollMetrics.init) { old, new in
            scrollMetricsChanged(from: old, to: new)
        }
        .overlay(alignment: .bottomTrailing) { jumpButton }
    }

    @ViewBuilder
    private var header: some View {
        if isSubagent {
            SubagentHeaderBar(
                title: title,
                subtitle: subagentInfo.map { SubagentText.parentSubtitle($0.parentTitle) } ?? session.connectionState.statusText,
                onBack: { session.goBack() },
                onPreviewTap: { session.showWorkspaceWebServers(for: liveTarget) }
            )
        } else {
            agentHeader
        }
    }

    private var agentHeader: some View {
        ChatHeaderBar(
            provider: provider,
            indicator: indicator,
            title: title,
            subtitle: subtitle,
            onStatusTap: { session.openDrawer() },
            onTitleTap: { session.showDetail(liveTarget) },
            onPreviewTap: { session.showWorkspaceWebServers(for: liveTarget) }
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isSubagent {
            SubagentStatePill(status: subagentInfo?.status ?? .running)
        } else if isReadOnly {
            ReadOnlyComposerPill(text: controlAvailable ? "Sessão encerrada · só leitura" : "Controle indisponível nesta tab Codex")
        } else {
            VStack(spacing: ChatScreenLayout.panelGap) {
                if let toast {
                    ControlToast(message: toast.text)
                        .transition(.opacity)
                }
                if isModelPickerOpen {
                    ModelPickerPanel(model: displayedModel, effort: displayedEffort, onModel: chooseModel, onEffort: chooseEffort)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ChatComposer(
                    draft: $draft,
                    isExpanded: $isComposing,
                    isFocused: $isFieldFocused,
                    attachments: attachments,
                    showsSlashMenu: provider == .claude,
                    isWorking: status == .working,
                    effort: displayedEffort,
                    onModelPicker: modelPickerAction,
                    onSend: send,
                    onStop: stop
                ) { maxHeight, close in
                    ChatControlsPanel(
                        session: session,
                        state: controlsState,
                        maxHeight: maxHeight,
                        onMode: chooseMode,
                        onOpenSubagent: { subagent in
                            close()
                            dismissComposer()
                            session.openChat(subagent)
                        },
                        onAction: { action in
                            close()
                            runSlashAction(action)
                        }
                    )
                }
            }
            .animation(.smooth(duration: 0.2), value: isModelPickerOpen)
            .animation(.smooth(duration: 0.2), value: toast)
        }
    }

    private var clearConfirmation: some View {
        ZStack {
            if isConfirmingClear {
                ClearConfirmation(
                    onCancel: { isConfirmingClear = false },
                    onConfirm: {
                        isConfirmingClear = false
                        perform(.clear)
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: isConfirmingClear)
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
        switch liveTarget {
        case .agent: !controlAvailable
        case .session, .codexThread, .subagent: true
        }
    }

    private var controlAvailable: Bool {
        guard let agent else { return true }
        return agent.kind != AgentKind.codex || agent.controlAvailable == true
    }

    private var provider: AgentProvider {
        if case .codexThread = liveTarget { return .codex }
        if let archived { return archived.provider }
        return agent?.kind == AgentKind.codex ? .codex : .claude
    }

    private var isSubagent: Bool {
        if case .subagent = liveTarget { true } else { false }
    }

    private var subagentInfo: SubagentChatInfo? {
        isSubagent ? chat?.meta?.subagent : nil
    }

    private var subagentTopNotice: String? {
        guard let chat, let info = subagentInfo, !chat.isLoading, !chat.hasMore else { return nil }
        return SubagentText.topNotice(agentType: info.agentType, startedAt: info.startedAt, model: chat.meta?.model)
    }

    private var subagentCompletedFooter: String? {
        guard let info = subagentInfo, info.status == .completed else { return nil }
        return SubagentText.completedFooter(durationMs: info.durationMs, toolUses: info.toolUses)
    }

    private var subagentFailureNotice: String? {
        SubagentText.failureNotice(subagentInfo, lastItem: chat?.items.last)
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
        switch liveTarget {
        case .session(let sessionId):
            return session.archivedSessions.first { $0.id == sessionId && $0.provider == .claude }
        case .codexThread(let threadId):
            return session.archivedSessions.first { $0.id == threadId && $0.provider == .codex }
        case .agent, .subagent:
            return nil
        }
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
        if pendingRequest != nil { return .agent(.blocked) }
        return .agent(status)
    }

    private var pendingRequest: PendingRequest? {
        guard case .agent(let agentId) = liveTarget else { return nil }
        return session.pending.request(forAgent: agentId)
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

    private var ringStyle: ContextRingStyle {
        switch indicator {
        case .disconnected: .offline
        case .archived: .archived
        case .agent(.blocked): .blocked
        case .agent(.working): .working
        default: .ready
        }
    }

    private var canControlModel: Bool {
        guard case .agent = liveTarget else { return false }
        return !isReadOnly && provider == .claude
    }

    private var confirmedModel: ModelAlias? {
        SessionControlChoices.alias(of: chat?.meta?.model ?? agent?.model)
    }

    private var confirmedEffort: EffortLevel? {
        SessionControlChoices.effort(chat?.meta?.effort ?? agent?.effort)
    }

    private var confirmedMode: PermissionModeTarget? {
        SessionControlChoices.mode(chat?.meta?.permissionMode ?? agent?.permissionMode)
    }

    private var displayedModel: ModelAlias? {
        modelOverride.displayed(confirmed: confirmedModel)
    }

    private var displayedEffort: EffortLevel? {
        effortOverride.displayed(confirmed: confirmedEffort)
    }

    private var controlsState: ChatControlsState {
        ChatControlsState(
            agentId: agent?.id,
            sessionId: chat?.sessionId ?? agent?.sessionId,
            contextLeftPercent: agent?.contextLeftPercent,
            contextUsedTokens: agent?.contextUsedTokens,
            ringStyle: ringStyle,
            usage: session.usage(for: provider),
            model: displayedModel,
            mode: modeOverride.displayed(confirmed: confirmedMode),
            runningSubagents: agent?.runningSubagents ?? 0,
            chatItems: chat?.items ?? []
        )
    }

    private var modelPickerAction: (() -> Void)? {
        guard canControlModel else { return nil }
        return { toggleModelPicker() }
    }

    private func toggleModelPicker() {
        guard canControlModel else { return }
        if !isModelPickerOpen {
            dismissComposer()
        }
        isModelPickerOpen.toggle()
    }

    private func closeModelPicker() {
        guard isModelPickerOpen else { return }
        isModelPickerOpen = false
    }

    private func chooseModel(_ model: ModelAlias) {
        isModelPickerOpen = false
        guard case .agent(let agentId) = liveTarget, model != displayedModel else { return }
        modelOverride.choose(model)
        sendControl(.setModel(agentId: agentId, model: model)) { modelOverride.release(model) }
    }

    private func chooseEffort(_ level: EffortLevel) {
        guard case .agent(let agentId) = liveTarget, level != displayedEffort else { return }
        effortOverride.choose(level)
        sendControl(.setEffort(agentId: agentId, level: level)) { effortOverride.release(level) }
    }

    private func chooseMode(_ mode: PermissionModeTarget) {
        guard case .agent(let agentId) = liveTarget, mode != modeOverride.displayed(confirmed: confirmedMode) else { return }
        modeOverride.choose(mode)
        sendControl(.setMode(agentId: agentId, mode: mode)) { modeOverride.release(mode) }
    }

    private func sendControl(_ message: ClientMessage, release: @escaping @MainActor () -> Void) {
        Task {
            do {
                try await session.request(message)
                try? await Task.sleep(for: ChatScreenLayout.controlConfirmationWindow)
                release()
            } catch {
                release()
                toast = ControlToastMessage(text: (error as? AppSessionError)?.message ?? ChatScreenLayout.controlFailureText)
            }
        }
    }

    private func expireToast() async {
        guard toast != nil else { return }
        try? await Task.sleep(for: ChatScreenLayout.toastDuration)
        guard !Task.isCancelled else { return }
        toast = nil
    }

    private func itemsChanged(_ items: [ChatItem]) {
        switch list.apply(items, imageCache: session.imageCache) {
        case .replaced:
            listGeneration += 1
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

    private func revealPendingRequest(_ agentId: AgentID?) {
        guard let agentId, liveTarget == .agent(agentId) else { return }
        session.consumePendingReveal()
        dismissComposer()
        jumpToBottom()
    }

    private func loadOlderItems() {
        guard !isPinnedToBottom else { return }
        #if DEBUG
        if let delay = ChatDebugOptions.current().olderPageDelay {
            Task {
                try? await Task.sleep(for: delay)
                session.loadOlderItems(for: target)
            }
            return
        }
        #endif
        session.loadOlderItems(for: target)
    }

    private func openSubagent(_ agentId: String) {
        guard let subagent = session.subagentTarget(agentId: agentId, in: target) else { return }
        dismissComposer()
        session.openChat(subagent)
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
        let images = sent.compactMap(\.image)
        let thumbnails = Task { await Self.thumbnails(of: images) }
        let cache = session.imageCache
        if !images.isEmpty {
            Task { list.setPendingThumbnails(await thumbnails.value.compactMap { $0 }, for: bubble.id) }
        }
        Task {
            do {
                try await session.sendPrompt(text, images: images) { @MainActor paths in
                    for (path, thumbnail) in zip(paths, await thumbnails.value) {
                        guard let thumbnail else { continue }
                        cache.seed(path: path, image: thumbnail, maxPixelSize: ChatImageCache.thumbnailPixelSize)
                    }
                }
            } catch AppSessionError.uploadFailed {
                list.rejectPending(bubble.id)
                restoreComposer(text, attachments: sent)
            } catch {
                list.rejectPending(bubble.id)
            }
        }
    }

    @concurrent
    private nonisolated static func thumbnails(of images: [PromptImage]) async -> [CGImage?] {
        images.map { ImageReduction.thumbnail(of: $0.data, maximumPixelSize: ChatImageCache.thumbnailPixelSize) }
    }

    private func restoreComposer(_ text: String, attachments restored: [ComposerAttachment]) {
        attachments.restore(restored)
        draft = [text, draft].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func stop() {
        Task { try? await session.interrupt() }
    }

    private func runSlashAction(_ action: SlashMenuAction) {
        dismissComposer()
        if action.needsConfirmation {
            isConfirmingClear = true
        } else {
            perform(action)
        }
    }

    private func perform(_ action: SlashMenuAction) {
        guard case .agent(let agentId) = liveTarget else { return }
        pinToBottom()
        Task { try? await session.request(action.message(for: agentId)) }
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
        if let agentId = options.openSubagentId, ChatDebugLaunch.consume(ChatDebugOptions.openSubagentKey), let subagent = session.subagentTarget(agentId: agentId, in: target) {
            session.openChat(subagent)
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
        if LaunchArguments.argumentDomain()[ChatScreenLayout.modelPickerDebugKey] != nil, ChatDebugLaunch.consume(ChatScreenLayout.modelPickerDebugKey) {
            isModelPickerOpen = true
        }
        if options.confirmsClear, ChatDebugLaunch.consume(ChatDebugOptions.confirmClearKey) {
            isConfirmingClear = true
        }
        if let command = options.slashCommand, let action = SlashMenuAction.matching(command: command), ChatDebugLaunch.consume(ChatDebugOptions.slashCommandKey) {
            perform(action)
        }
        if let delay = options.closeChatAfter, ChatDebugLaunch.consume(ChatDebugOptions.closeChatAfterKey) {
            try? await Task.sleep(for: delay)
            session.closeChat()
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
                session.loadOlderItems(for: target)
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

struct ControlToastMessage: Equatable {
    let id = UUID()
    let text: String
}

enum ChatScreenLayout {
    static let jumpButtonGap: CGFloat = 8
    static let panelGap: CGFloat = 8
    static let toastDuration: Duration = .seconds(3)
    static let controlConfirmationWindow: Duration = .seconds(3)
    static let controlFailureText = "Não foi possível mudar no Mac"
    static let modelPickerDebugKey = "chat-model-picker"
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
