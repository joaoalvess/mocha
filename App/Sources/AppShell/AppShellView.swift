import MochaProtocol
import SwiftUI

struct AppShellView: View {
    @Bindable var session: AppSession
    var launchURL: URL?
    var opensDrawerAtLaunch = false
    var opensSettingsAtLaunch = false
    var opensHistoryAtLaunch = false
    var opensWebServersAtLaunch = false
    var opensNewSessionAtLaunch = false
    var newSessionKindAtLaunch: AgentProvider?
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchNewSessionKind: AgentProvider?

    var body: some View {
        ZStack {
            NavigationStack(path: chatPath) {
                RootPager(session: session)
                    .toolbar(.hidden, for: .navigationBar)
                    .background(InteractivePopEnabler())
                    .navigationDestination(for: ChatTarget.self) { target in
                        ChatScreen(session: session, target: target)
                            .toolbar(.hidden, for: .navigationBar)
                    }
            }
            DrawerLayer(session: session)
            BottomPanelLayer(isPresented: session.sheet == .usage, dismiss: session.dismissSheet) {
                UsageSheet(session: session)
            }
            BottomPanelLayer(isPresented: session.sheet == .webServers, dismiss: session.dismissSheet) {
                WebServersSheet(session: session)
            }
            BottomPanelLayer(isPresented: session.sheet == .newSession, dismiss: session.dismissSheet) {
                NewSessionSheet(session: session, initialKind: launchNewSessionKind)
                    .onDisappear { launchNewSessionKind = nil }
            }
            BottomPanelLayer(isPresented: session.isInboxOpen, dismiss: { session.isInboxOpen = false }) {
                InboxSheet(session: session)
            }
            if session.showsPairing {
                PairingScreen(session: session)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.25), value: session.showsPairing)
        .sheet(item: systemSheet) { sheet in
            sheetContent(sheet)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            session.scenePhaseChanged(to: phase)
        }
        .onChange(of: session.foregroundAgentId) {
            session.sendForeground()
        }
        .task {
            session.start()
            if let launchURL {
                session.handle(launchURL)
            }
            if opensDrawerAtLaunch {
                session.openDrawer()
            }
            if opensSettingsAtLaunch {
                session.showSettings()
            }
            if opensHistoryAtLaunch {
                session.showHistory()
            }
            if opensWebServersAtLaunch {
                session.showWebServers()
            }
            if opensNewSessionAtLaunch {
                launchNewSessionKind = newSessionKindAtLaunch
                session.showNewSession()
            }
        }
    }

    private var chatPath: Binding<[ChatTarget]> {
        Binding(
            get: { session.chatPath },
            set: { session.setChatPath($0) }
        )
    }

    private var systemSheet: Binding<AppSheet?> {
        Binding(
            get: { session.sheet == .usage || session.sheet == .webServers || session.sheet == .newSession ? nil : session.sheet },
            set: { session.sheet = $0 }
        )
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .detail(let target):
            AgentDetailSheet(session: session, target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.black)
                .presentationCornerRadius(Metrics.sheetCornerRadius)
        case .usage, .webServers, .newSession:
            EmptyView()
        case .settings:
            SettingsScreen(session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.black)
                .presentationCornerRadius(Metrics.sheetCornerRadius)
        }
    }
}

private struct DrawerLayer: View {
    @Bindable var session: AppSession
    @State private var dragOffset: CGFloat = 0

    private static let widthFraction: CGFloat = 0.9
    private static let closeThreshold: CGFloat = 0.3

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * Self.widthFraction
            ZStack(alignment: .leading) {
                if session.isDrawerOpen {
                    Palette.glyphOnAccent
                        .opacity(0.5 * progress(width: width))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { session.closeDrawer() }
                        .accessibilityLabel("Fechar gaveta")
                        .accessibilityAddTraits(.isButton)
                        .transition(.opacity)
                    DrawerScreen(session: session)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .offset(x: dragOffset)
                        .transition(.move(edge: .leading))
                        .gesture(closeDrag(width: width))
                }
            }
        }
        .animation(.smooth(duration: 0.28), value: session.isDrawerOpen)
        .onChange(of: session.isDrawerOpen) {
            dragOffset = 0
            dismissKeyboard()
        }
    }

    private func progress(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return 1 + min(0, dragOffset) / width
    }

    private func closeDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                if -value.predictedEndTranslation.width > width * Self.closeThreshold {
                    session.closeDrawer()
                } else {
                    withAnimation(.smooth(duration: 0.2)) { dragOffset = 0 }
                }
            }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
