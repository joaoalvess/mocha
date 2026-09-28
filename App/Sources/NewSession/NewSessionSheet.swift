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
    private static let bottomSpace: CGFloat = 79
    private static let pickHeight: CGFloat = 78
    private static let pickSpacing: CGFloat = 10
    private static let workspaceRowHeight: CGFloat = 66
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
        .overlay(alignment: .top) { SheetGrabber() }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.drawerBg)
        .presentationCornerRadius(Metrics.sheetCornerRadius)
        .animation(.smooth(duration: 0.25), value: kind)
        .onAppear { kind = initialKind }
    }

    private var detentHeight: CGFloat {
        let content: CGFloat
        if kind == nil {
            content = Self.pickHeight * 3 + Self.pickSpacing * 2
        } else {
            content = Self.workspaceRowHeight * CGFloat(max(1, workspaces.count))
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
        if workspaces.isEmpty {
            Text("Nenhum workspace aberto no Herdr")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Self.workspaceRowHeight)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                    if index > 0 {
                        Palette.divider.frame(height: 1)
                    }
                    WorkspacePickRow(workspace: workspace, isCreating: creating == workspace.id) {
                        create(in: workspace.id)
                    }
                    .disabled(creating != nil)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.toolCard))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var workspaces: [WorkspaceNode] {
        NewSessionWorkspaces.flattened(session.workspaces)
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

enum NewSessionWorkspaces {
    static func flattened(_ workspaces: [WorkspaceNode]) -> [WorkspaceNode] {
        workspaces.flatMap { [$0] + flattened($0.children) }
    }
}

private enum PickTile {
    case claude
    case codex
    case shell

    var background: Color {
        switch self {
        case .claude: Palette.claudeTile
        case .codex: Color(hex: 0x26282B)
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
    let workspace: WorkspaceNode
    let isCreating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(hex: 0x15251A))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "folder")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.statusOk)
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(workspace.label)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if workspace.branch != nil || workspace.isDirty {
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
                        .accessibilityLabel("Abrindo tab em \(workspace.label)")
                } else {
                    LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.4, color: Palette.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}
