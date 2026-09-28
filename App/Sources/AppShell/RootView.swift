import SwiftUI

struct RootView: View {
    let launch: LaunchConfiguration
    let startup: AppStartup

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
        case .demoUnavailable:
            SplashView(message: "Não foi possível abrir o modo demo.")
        }
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
