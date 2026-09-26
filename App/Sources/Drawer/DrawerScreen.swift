import MochaProtocol
import SwiftUI

struct DrawerScreen: View {
    @Bindable var session: AppSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("WORKSPACES")
                    .font(Typography.drawerSectionHeader)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.contentMargin)
                    .padding(.vertical, 8)
                ForEach(session.workspaces) { workspace in
                    DrawerPlaceholderWorkspace(workspace: workspace, depth: 0, session: session)
                }
            }
            .padding(.top, 8)
        }
        .background(Palette.drawerBg.ignoresSafeArea())
    }
}

private struct DrawerPlaceholderWorkspace: View {
    let workspace: WorkspaceNode
    let depth: Int
    let session: AppSession

    var body: some View {
        Text(workspace.label)
            .font(Typography.drawerWorkspace)
            .foregroundStyle(Palette.textPrimary)
            .padding(.leading, Metrics.contentMargin + CGFloat(depth) * 16)
            .padding(.vertical, 8)
        ForEach(workspace.tabs) { tab in
            if tab.agents.isEmpty {
                row(title: ">_ " + tab.title, isSelected: false, action: nil)
            } else {
                ForEach(tab.agents) { agent in
                    row(
                        title: agent.title,
                        isSelected: session.visibleChat?.agentId == agent.id,
                        action: agent.kind == "claude" ? { session.openChat(agent.id) } : nil
                    )
                }
            }
        }
        ForEach(workspace.children) { child in
            DrawerPlaceholderWorkspace(workspace: child, depth: depth + 1, session: session)
        }
    }

    private func row(title: String, isSelected: Bool, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            Text(title)
                .font(Typography.drawerRow)
                .foregroundStyle(action == nil ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Metrics.contentMargin + CGFloat(depth + 1) * 16)
                .padding(.vertical, 10)
                .background(isSelected ? Palette.selectedRow : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
