import MochaClient
import MochaProtocol
import SwiftUI

struct AgentDetailSheet: View {
    @Bindable var session: AppSession
    let target: ChatTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .hero) {
                    session.dismissSheet()
                }
                Spacer()
            }
            Text("Detalhe do agente")
                .systemText(.sheetTitle)
                .foregroundStyle(Palette.textPrimary)
            SheetListCard {
                SheetListRow(label: "Título", value: title, isCompact: true)
                SheetListRow(label: "Workspace do Herdr", value: workspace, valueStyle: .mono, isCompact: true)
                SheetListRow(label: "Sessão", value: sessionId, valueStyle: .mono, isCompact: true)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.contentMargin)
        .padding(.top, Metrics.contentMargin)
    }

    private var agent: AgentSummary? {
        guard case .agent(let agentId) = target else { return nil }
        return session.workspaces.agent(withId: agentId)
    }

    private var archived: ArchivedSession? {
        guard case .session(let sessionId) = target else { return nil }
        return session.archivedSessions.first { $0.id == sessionId }
    }

    private var title: String {
        agent?.title ?? archived?.title ?? "—"
    }

    private var workspace: String {
        agent?.workspaceLabel ?? archived?.workspaceLabel ?? "—"
    }

    private var sessionId: String {
        switch target {
        case .agent: agent?.sessionId ?? "—"
        case .session(let sessionId): sessionId
        }
    }
}
