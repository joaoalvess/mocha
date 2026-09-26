import MochaClient
import MochaProtocol
import SwiftUI

struct HomeScreen: View {
    @Bindable var session: AppSession

    var body: some View {
        ZStack(alignment: .top) {
            HomeBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Home")
                        .systemText(.sheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Metrics.contentMargin)
                    Text(session.connectionState.statusText)
                        .systemText(.sheetNote)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.top, 2)
                    SectionHeader(title: "Agentes")
                    ForEach(session.claudeAgents) { agent in
                        row(title: agent.title, target: .agent(agent.id))
                    }
                    if !session.archivedSessions.isEmpty {
                        SectionHeader(title: "Arquivados")
                        ForEach(session.archivedSessions) { archived in
                            row(title: archived.title, target: .session(archived.id))
                        }
                    }
                    if session.usage != nil {
                        SectionHeader(title: "Uso")
                        Button("Ver uso do plano") { session.showUsage() }
                            .systemText(.body)
                            .foregroundStyle(Palette.link)
                            .padding(.horizontal, Metrics.contentMargin)
                    }
                }
                .padding(.top, Metrics.homeListTopInset)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            HStack {
                GlassRoundButton(icon: .sidebar, accessibilityLabel: "Abrir gaveta", style: .home) {
                    session.openDrawer()
                }
                Spacer()
                GlassRoundButton(systemImage: "gearshape", accessibilityLabel: "Ajustes", style: .home) {
                    session.showSettings()
                }
            }
            .padding(.horizontal, Metrics.homeButtonSide)
            .padding(.top, Metrics.homeButtonTopInset)
        }
    }

    private func row(title: String, target: ChatTarget) -> some View {
        Button {
            session.openChat(target)
        } label: {
            HomeCardTitle(text: title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.contentMargin)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.toolCard))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture().onEnded { _ in session.showDetail(target) })
        .padding(.horizontal, Metrics.contentMargin)
        .padding(.bottom, Metrics.homeCardSpacing)
    }
}
