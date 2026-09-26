import MochaProtocol
import SwiftUI

struct DrawerScreen: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Gaveta")
                    .systemText(.sheetTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    session.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.controlBg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes")
            }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.top, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Workspaces")
                    ForEach(session.workspaces) { workspace in
                        DrawerPlaceholderWorkspace(workspace: workspace, depth: 0, session: session)
                    }
                }
            }
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
            .systemText(.body)
            .fontWeight(.medium)
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
                        isSelected: session.visibleChat?.target == .agent(agent.id),
                        action: agent.kind == AgentKind.claude ? { session.openChat(.agent(agent.id)) } : nil
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
                .systemText(.body)
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
