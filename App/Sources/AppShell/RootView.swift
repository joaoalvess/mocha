import MochaClient
import MochaProtocol
import SwiftUI

struct RootView: View {
    let launch: LaunchConfiguration
    let startup: AppStartup
    @State private var webPreview = WebPreviewOpener.shared
    @State private var presentedWebPreview: WebPreviewPage?

    private static let sheetDismissDelay: Duration = .milliseconds(450)

    var body: some View {
        #if DEBUG
        if let preview = launch.preview {
            switch preview {
            case .designSystem:
                DesignSystemPreviewScreen()
            case .markdown:
                MarkdownPreviewScreen()
            }
        } else {
            content
        }
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch startup {
        case .session(let session):
            AppShellView(
                session: session,
                launchURL: launchURL,
                opensDrawerAtLaunch: opensDrawerAtLaunch,
                opensSettingsAtLaunch: opensSettingsAtLaunch,
                opensHistoryAtLaunch: opensHistoryAtLaunch,
                opensWebServersAtLaunch: opensWebServersAtLaunch,
                opensNewSessionAtLaunch: newSessionLaunch != nil,
                newSessionKindAtLaunch: newSessionLaunch == .workspace ? .claude : nil
            )
                .onOpenURL { session.handle($0) }
                .onChange(of: webPreview.page) { _, page in
                    Task { await presentWebPreview(page, over: session) }
                }
                .fullScreenCover(item: $presentedWebPreview, onDismiss: WebPreviewOpener.close) { page in
                    BrowserScreen(
                        model: BrowserModel(server: page.server) { [isDemo] in
                            try await session.browserTunnel(for: page.server, isDemo: isDemo)
                        },
                        subtitle: WebServerGrouping.subtitle(for: page.server, workspaces: session.workspaces),
                        onClose: WebPreviewOpener.close,
                        onOpenSettings: session.showSettings
                    )
                }
                .task { await openWebPreviewAtLaunch(session) }
        case .demoUnavailable:
            SplashView(message: "Não foi possível abrir o modo demo.")
        }
    }

    private func presentWebPreview(_ page: WebPreviewPage?, over session: AppSession) async {
        guard let page else {
            presentedWebPreview = nil
            return
        }
        if session.sheet != nil {
            session.dismissSheet()
            try? await Task.sleep(for: Self.sheetDismissDelay)
        }
        guard webPreview.page == page else { return }
        presentedWebPreview = page
    }

    private var isDemo: Bool {
        launch.demoOptions != nil
    }

    private func openWebPreviewAtLaunch(_ session: AppSession) async {
        #if DEBUG
        guard let port = launch.webPreviewPort else { return }
        for _ in 0..<50 where session.connectionState != .connected {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await session.reloadWebServers()
        for _ in 0..<50 where session.webServers == .loading {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let servers: [WebServer]
        if case .loaded(let sections) = session.webServers {
            servers = sections.flatMap(\.servers)
        } else {
            servers = []
        }
        let server = servers.first { $0.port == port }
            ?? WebServer(pid: 0, process: "—", port: port, title: nil, directory: nil)
        WebPreviewOpener.open(server)
        #endif
    }

    private var launchURL: URL? {
        #if DEBUG
        launch.openURL
        #else
        nil
        #endif
    }

    private var opensDrawerAtLaunch: Bool {
        #if DEBUG
        launch.opensDrawer
        #else
        false
        #endif
    }

    private var opensSettingsAtLaunch: Bool {
        #if DEBUG
        launch.opensSettings
        #else
        false
        #endif
    }

    private var opensHistoryAtLaunch: Bool {
        #if DEBUG
        launch.opensHistory
        #else
        false
        #endif
    }

    private var opensWebServersAtLaunch: Bool {
        #if DEBUG
        launch.opensWebServers
        #else
        false
        #endif
    }

    private var newSessionLaunch: NewSessionLaunch? {
        #if DEBUG
        launch.newSession
        #else
        nil
        #endif
    }
}
