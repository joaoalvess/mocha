import MochaClient
import MochaProtocol
import SwiftUI

struct DrawerScreen: View {
    @Bindable var session: AppSession
    @AppStorage(DrawerPreferences.modeKey) private var mode: DrawerMode = .tree
    @AppStorage(DrawerPreferences.collapsedKey) private var storedCollapsed = ""
    @State private var query = ""
    @State private var hint: String?
    @State private var creatingTabs: Set<WorkspaceID> = []

    var body: some View {
        VStack(spacing: 0) {
            DrawerTopBar(query: $query, mode: $mode) {
                session.showSettings()
            }
            .padding(.horizontal, DrawerLayout.horizontalMargin)
            .padding(.top, DrawerLayout.topBarInset)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader
                    switch mode {
                    case .tree:
                        treeList
                    case .recent:
                        recentList
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Palette.drawerBg
                .ignoresSafeArea()
                .shadow(color: Palette.glyphOnAccent.opacity(0.45), radius: 20, x: 14)
        }
        .overlay(alignment: .bottom) {
            if let hint {
                Text(hint)
                    .drawerText(.hint)
                    .foregroundStyle(Palette.drawerHint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .task(id: hint) {
            guard hint != nil else { return }
            do {
                try await Task.sleep(for: Self.hintDuration)
                withAnimation(.smooth(duration: 0.3)) { hint = nil }
            } catch {
                return
            }
        }
        #if DEBUG
        .task(id: session.connectionState) {
            await runDebugLaunch()
        }
        #endif
    }

    private static let hintDuration: Duration = .seconds(2.5)

    private var sectionHeader: some View {
        Text(mode == .tree ? "WORKSPACES" : "RECENTES")
            .drawerText(.sectionHeader)
            .foregroundStyle(Palette.textSecondary)
            .frame(minHeight: DrawerLayout.sectionHeaderHeight)
            .padding(.leading, DrawerLayout.sectionHeaderLeading)
            .padding(.top, DrawerLayout.sectionHeaderTop)
            .padding(.bottom, mode == .tree ? DrawerLayout.treeTopGap : DrawerLayout.recentTopGap)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var treeList: some View {
        let rows = DrawerContent.treeRows(for: session.workspaces, query: query, collapsed: collapsed)
        if rows.isEmpty, session.hasReceivedTree {
            emptyText(Self.emptyTreeText)
        }
        ForEach(rows) { row in
            treeRow(row)
                .padding(.leading, DrawerLayout.rowLeading)
                .padding(.trailing, DrawerLayout.rowTrailing)
        }
    }

    @ViewBuilder
    private func treeRow(_ row: DrawerTreeRow) -> some View {
        switch row {
        case .workspace(let workspace):
            DrawerWorkspaceRowView(
                row: workspace,
                isCreatingTab: creatingTabs.contains(workspace.id),
                action: { toggle(workspace.id) },
                onNewTab: { createAgentTab(in: workspace.id) }
            )
        case .shell(let shell):
            DrawerTabRowView(icon: .shell, title: shell.title, level: shell.level) {
                show(hint: Self.terminalHint)
            }
        case .agent(let agentRow):
            let agent = agentRow.agent
            DrawerTabRowView(
                icon: agentRow.isClaude ? .claude(isWorking: agent.status == .working) : .otherAgent(isWorking: agent.status == .working),
                title: agentRow.title,
                branch: agentRow.branch,
                level: agentRow.level,
                isBlocked: agent.status == .blocked,
                isSelected: isVisible(agent.id),
                statusLabel: DrawerContent.stateText(for: agent.status)
            ) {
                if agentRow.isClaude {
                    session.openChat(.agent(agent.id))
                } else {
                    show(hint: Self.claudeOnlyHint)
                }
            }
        }
    }

    @ViewBuilder
    private var recentList: some View {
        let rows = DrawerContent.recentRows(for: session.workspaces, query: query)
        if rows.isEmpty, session.hasReceivedTree {
            emptyText(Self.emptyRecentText)
        }
        TimelineView(.periodic(from: .now, by: Self.relativeTimeRefresh)) { context in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    DrawerRecentRowView(row: row, now: context.date, isSelected: isVisible(row.agent.id)) {
                        session.openChat(.agent(row.agent.id))
                    }
                    .padding(.leading, DrawerLayout.rowLeading)
                    .padding(.trailing, DrawerLayout.rowTrailing)
                }
            }
        }
    }

    private static let relativeTimeRefresh: TimeInterval = 30

    private func emptyText(_ text: String) -> some View {
        Text(DrawerContent.searchNeedle(query).map { "Nada encontrado para “\($0)”" } ?? text)
            .drawerText(.recentSubtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.leading, DrawerLayout.sectionHeaderLeading)
            .padding(.trailing, DrawerLayout.horizontalMargin)
            .padding(.top, 8)
    }

    private static let emptyTreeText = "Nenhum workspace aberto no Herdr"
    private static let emptyRecentText = "Nenhum Claude aberto no Herdr"
    private static let terminalHint = "Terminal chega na fase 2"
    private static let claudeOnlyHint = "Chat disponível só para Claude Code"

    private var collapsed: Set<WorkspaceID> {
        DrawerContent.collapsedWorkspaces(from: storedCollapsed)
    }

    private func toggle(_ workspaceId: WorkspaceID) {
        guard DrawerContent.searchNeedle(query) == nil else { return }
        var updated = collapsed
        if updated.remove(workspaceId) == nil {
            updated.insert(workspaceId)
        }
        withAnimation(.smooth(duration: 0.2)) {
            storedCollapsed = DrawerContent.storedValue(forCollapsed: updated)
        }
    }

    private func createAgentTab(in workspaceId: WorkspaceID) {
        guard creatingTabs.insert(workspaceId).inserted else { return }
        Task {
            do {
                let reply = try await session.request(.newAgentTab(workspaceId: workspaceId))
                guard case .ack(let agentId?) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                creatingTabs.remove(workspaceId)
                session.openChat(.agent(agentId))
            } catch {
                creatingTabs.remove(workspaceId)
                show(hint: (error as? AppSessionError ?? .notConnected).message)
            }
        }
    }

    #if DEBUG
    private func runDebugLaunch() async {
        guard session.connectionState == .connected else { return }
        let options = DrawerDebugOptions.current()
        guard let workspaceId = options.newTabWorkspaceId, DrawerDebugLaunch.consume(DrawerDebugOptions.newTabKey) else { return }
        try? await Task.sleep(for: options.newTabDelay)
        guard !Task.isCancelled else { return }
        createAgentTab(in: workspaceId)
        if let reopenAfter = options.reopenAfter {
            Task {
                try? await Task.sleep(for: reopenAfter)
                session.openDrawer()
            }
        }
    }
    #endif

    private func isVisible(_ agentId: AgentID) -> Bool {
        session.visibleChat?.target == .agent(agentId)
    }

    private func show(hint text: String) {
        withAnimation(.smooth(duration: 0.2)) { hint = text }
        AccessibilityNotification.Announcement(text).post()
    }
}

enum DrawerPreferences {
    static let modeKey = "drawer.mode"
    static let collapsedKey = "drawer.collapsedWorkspaces"
}
