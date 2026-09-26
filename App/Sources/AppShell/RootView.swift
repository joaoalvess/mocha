import SwiftUI

struct RootView: View {
    let launch: LaunchConfiguration
    let startup: AppStartup

    var body: some View {
        #if DEBUG
        if let probe = launch.probe {
            switch probe {
            case .push:
                PushProbeView()
            case .gateway:
                GatewayProbeView()
            }
        } else if let preview = launch.preview {
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
            AppShellView(session: session, launchURL: launchURL)
                .onOpenURL { session.handle($0) }
        case .demoUnavailable:
            SplashView(message: "Não foi possível abrir o modo demo.")
        case .awaitingConnection:
            SplashView(message: nil)
        }
    }

    private var launchURL: URL? {
        #if DEBUG
        launch.openURL
        #else
        nil
        #endif
    }
}
