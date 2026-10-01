import MochaClient
import MochaProtocol
import SwiftUI

struct NewSessionSheet: View {
    @Bindable var session: AppSession
    var initialKind: AgentProvider?
    @State private var kind: AgentProvider?
    @State private var creating: WorkspaceID?
    @State private var errorText: String?

    private static let titleTop: CGFloat = 34
    private static let titleHeight: CGFloat = 25
    private static let titleGap: CGFloat = 36
    private static let bottomSpace: CGFloat = 24
    private static let pickHeight: CGFloat = 78
    private static let pickSpacing: CGFloat = 10
    private static let workspaceRowHeight: CGFloat = 66
    private static let workspaceGroupSpacing: CGFloat = 10
    private static let footerHeight: CGFloat = 31
    private static let maxHeight: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            Text(kind == nil ? "O que você quer abrir no Herdr?" : "Escolha o workspace do Herdr")
                .font(.system(size: 19, weight: .semibold))
                .systemLinePitch(25, size: 19)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, Self.titleTop)
                .padding(.bottom, Self.titleGap)
            ScrollView {
                if kind == nil {
                    agentPicks
                } else {
                    workspaceList
                }
                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .systemLinePitch(17, size: 12)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Metrics.contentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(height: contentHeight)
        .overlay(alignment: .top) { SheetGrabber() }
        .animation(.smooth(duration: 0.25), value: kind)
        .onAppear { kind = initialKind }
    }

    private var contentHeight: CGFloat {
        let content: CGFloat
        if kind == nil {
            content = Self.pickHeight * 3 + Self.pickSpacing * 2
        } else {
            let rows = workspaceGroups.reduce(0) { $0 + $1.count }
            let gaps = Self.workspaceGroupSpacing * CGFloat(max(0, workspaceGroups.count - 1))
            content = Self.workspaceRowHeight * CGFloat(max(1, rows)) + gaps
        }
        let footer = errorText == nil ? 0 : Self.footerHeight
        return min(Self.maxHeight, Self.titleTop + Self.titleHeight + Self.titleGap + content + footer + Self.bottomSpace)
    }

    private var agentPicks: some View {
        VStack(spacing: Self.pickSpacing) {
            AgentPickCard(tile: .claude, title: "Claude", detail: "Claude Code numa tab nova") { kind = .claude }
            AgentPickCard(tile: .codex, title: "Codex", detail: "Codex CLI ligado ao Mocha") { kind = .codex }
            AgentPickCard(tile: .shell, title: "Shell", detail: "Terminal fish", isEnabled: false) {}
        }
    }

    @ViewBuilder
    private var workspaceList: some View {
        if workspaceGroups.isEmpty {
            Text("Nenhum workspace aberto no Herdr")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Self.workspaceRowHeight)
        } else {
            VStack(spacing: Self.workspaceGroupSpacing) {
                ForEach(workspaceGroups, id: \.first?.id) { group in
                    VStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Palette.divider.frame(height: 1)
                            }
                            WorkspacePickRow(item: item, isCreating: creating == item.id) {
                                create(in: item.id)
                            }
                            .disabled(creating != nil)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.toolCard))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private var workspaceGroups: [[WorkspacePickItem]] {
        NewSessionWorkspaces.groups(session.workspaces)
    }

    private func create(in workspaceId: WorkspaceID) {
        guard creating == nil, let kind else { return }
        creating = workspaceId
        errorText = nil
        Task {
            do {
                let reply = try await session.request(.newAgentTab(workspaceId: workspaceId, kind: kind))
                guard case .ack(let agentId?) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                creating = nil
                session.openChat(.agent(agentId))
            } catch {
                creating = nil
                errorText = (error as? AppSessionError ?? .notConnected).message
            }
        }
    }
}

struct WorkspacePickItem: Identifiable {
    let workspace: WorkspaceNode
    let isWorktree: Bool
    let title: String
    let showsBranch: Bool

    var id: WorkspaceID { workspace.id }

    var agentCount: Int {
        workspace.tabs.reduce(0) { $0 + $1.agents.count }
    }
}

enum NewSessionWorkspaces {
    static func groups(_ workspaces: [WorkspaceNode]) -> [[WorkspacePickItem]] {
        workspaces.map { root in
            let rootItem = WorkspacePickItem(workspace: root, isWorktree: false, title: root.label, showsBranch: true)
            let worktreeItems = root.children.flattenedWorkspaces.map { worktree in
                let title = worktree.label == root.label ? (worktree.branch ?? worktree.label) : worktree.label
                return WorkspacePickItem(
                    workspace: worktree,
                    isWorktree: true,
                    title: title,
                    showsBranch: title != worktree.branch
                )
            }
            return [rootItem] + worktreeItems
        }
    }
}

private enum PickTile {
    case claude
    case codex
    case shell

    var background: Color {
        switch self {
        case .claude: Palette.claudeTile
        case .codex: Palette.codexTile
        case .shell: Color(hex: 0x1D1F21)
        }
    }
}

private struct AgentPickCard: View {
    let tile: PickTile
    let title: String
    let detail: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tile.background)
                    .frame(width: 48, height: 48)
                    .overlay { glyph }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isEnabled {
                    LineIconView(icon: .chevronRight, size: 13, strokeWidth: 2.4, color: Palette.textSecondary)
                } else {
                    Text("FASE 2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.controlBg))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 78)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.toolCard)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var glyph: some View {
        switch tile {
        case .claude:
            ProviderMark(provider: .claude, size: 27)
        case .codex:
            ProviderMark(provider: .codex, size: 24)
                .foregroundStyle(Color(hex: 0xE8E8EA))
        case .shell:
            LineIconView(icon: .prompt, size: 27, strokeWidth: 1.9, color: Color(hex: 0x6A6E74))
        }
    }
}

private struct WorkspacePickRow: View {
    let item: WorkspacePickItem
    let isCreating: Bool
    let action: () -> Void

    private var workspace: WorkspaceNode { item.workspace }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(hex: 0x15251A))
                    .frame(width: 38, height: 38)
                    .overlay {
                        if item.isWorktree {
                            LineIconView(icon: .branch, size: 17, strokeWidth: 1.9, color: Palette.statusOk)
                        } else {
                            Image(systemName: "folder")
                                .font(.system(size: 17))
                                .foregroundStyle(Palette.statusOk)
                        }
                    }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if workspace.isDirty && !item.showsBranch {
                            Text(verbatim: "*")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.dirty)
                        }
                    }
                    if item.showsBranch && (workspace.branch != nil || workspace.isDirty) {
                        HStack(spacing: 4) {
                            if let branch = workspace.branch {
                                LineIconView(icon: .branch, size: 12, strokeWidth: 1.9, color: Palette.textSecondary)
                                Text(branch)
                                    .lineLimit(1)
                            }
                            if workspace.isDirty {
                                Text(verbatim: "*")
                                    .foregroundStyle(Palette.dirty)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCreating {
                    ProgressView()
                        .tint(Palette.statusOk)
                        .accessibilityLabel("Abrindo tab em \(item.title)")
                } else {
                    if item.agentCount > 0 {
                        HStack(spacing: 12) {
                            StatusDot(indicator: .agent(workspace.agentStatus))
                            Text(item.agentCount == 1 ? "1 agente" : "\(item.agentCount) agentes")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.4, color: Palette.textSecondary)
                }
            }
            .padding(.leading, item.isWorktree ? 30 : 16)
            .padding(.trailing, 16)
            .frame(height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}
