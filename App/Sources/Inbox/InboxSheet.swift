import MochaClient
import MochaProtocol
import SwiftUI

struct InboxSheet: View {
    @Bindable var session: AppSession

    static let detent = PresentationDetent.height(712)

    private static let titleTop: CGFloat = 46
    private static let titleSide: CGFloat = 21
    private static let listTop: CGFloat = 16
    private static let listBottom: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                SheetGrabber()
                header
                    .padding(.horizontal, Self.titleSide)
                    .padding(.top, Self.titleTop)
            }
            if requests.isEmpty {
                Text(PendingText.emptyInbox)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Metrics.listItemSpacing) {
                        ForEach(requests) { request in
                            card(for: request)
                        }
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                    .padding(.top, Self.listTop)
                    .padding(.bottom, Self.listBottom)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.25), value: requests.map(\.id))
    }

    private var requests: [PendingRequest] {
        session.pending.visible
    }

    private var header: some View {
        let count = Text(PendingText.inboxCount(requests.count))
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Palette.textSecondary)
        return Text("\(Text(PendingText.inboxTitle)) \(count)")
            .systemText(.sheetTitle)
            .systemLinePitch(22, size: 17)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func card(for request: PendingRequest) -> some View {
        let agent = session.workspaces.agent(withId: request.agentId)
        let name = agent.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? PendingText.unknownAgent
        let title = agent?.kind == AgentKind.codex ? "Codex · \(name)" : name
        return PendingRequestCard(
            request: request,
            heading: .inbox(agentTitle: title, workspace: agent?.workspaceLabel) {
                session.openChat(.agent(request.agentId))
            },
            isSending: session.pending.isSending(request.id),
            failure: session.pending.failure(for: request.id)
        ) { response in
            session.respond(to: request.id, with: response)
        }
    }
}
