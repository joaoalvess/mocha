import MochaClient
import MochaProtocol
import SwiftUI

struct WebServersSheet: View {
    @Bindable var session: AppSession

    static let emptyMessage = "Nenhum servidor web rodando no Mac"
    static let workspaceEmptyMessage = "Nenhum servidor web neste workspace"

    private static let titleTop: CGFloat = 46
    private static let titleSide: CGFloat = 21
    private static let listSide: CGFloat = 20
    private static let listTop: CGFloat = 24
    private static let listBottom: CGFloat = 24
    private static let messageVertical: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                SheetGrabber()
                header
                    .padding(.horizontal, Self.titleSide)
                    .padding(.top, Self.titleTop)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.25), value: session.webServers)
        .onChange(of: session.connectionState) { previous, state in
            guard state == .connected, previous != .connected else { return }
            Task { await session.reloadWebServers() }
        }
    }

    private var header: some View {
        Text("Servidores web")
            .font(.system(size: 22, weight: .bold))
            .systemLinePitch(28, size: 22)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var content: some View {
        if let offlineMessage {
            message(offlineMessage)
        } else {
            switch session.webServers {
            case .loading:
                ProgressView()
                    .tint(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Self.messageVertical)
            case .failed(let text):
                message(text)
            case .loaded(let sections) where sections.allSatisfy(\.servers.isEmpty):
                message(session.webServersScope == nil ? Self.emptyMessage : Self.workspaceEmptyMessage)
            case .loaded(let sections):
                list(sections)
            }
        }
    }

    private var offlineMessage: String? {
        guard session.connectionState != .connected else { return nil }
        return HomeSections.offlineProblem(for: session.connectionState, previous: nil)?.message ?? ConnectionProblem.unreachable.message
    }

    private func list(_ sections: [WebServerGroup]) -> some View {
        FittingScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections.filter { !$0.servers.isEmpty }) { section in
                    WebServersSectionView(section: section)
                }
            }
            .padding(.horizontal, Self.listSide)
            .padding(.top, Self.listTop)
            .padding(.bottom, Self.listBottom)
        }
        .scrollIndicators(.hidden)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Self.listSide)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.messageVertical)
    }
}

private struct WebServersSectionView: View {
    let section: WebServerGroup

    private static let headerSide: CGFloat = 4.5
    private static let headerBottom: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title.uppercased())
                .systemText(.sectionHeader)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Self.headerSide)
                .padding(.bottom, Self.headerBottom)
                .accessibilityAddTraits(.isHeader)
            SheetListCard {
                ForEach(section.servers, id: \.port) { server in
                    WebServerRow(server: server)
                }
            }
        }
    }
}

private struct WebServerRow: View {
    let server: WebServer

    private static let height: CGFloat = 66
    private static let iconWidth: CGFloat = 23

    var body: some View {
        Button {
            WebPreviewOpener.open(server)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Self.iconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(server.detailLine)
                        .monoText(13, relativeTo: .subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre o navegador")
    }
}
