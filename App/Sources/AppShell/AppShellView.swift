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
            UsagePanelLayer(session: session)
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
        .sheet(isPresented: $session.isInboxOpen) {
            InboxSheet(session: session)
                .presentationDetents([InboxSheet.detent])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.drawerBg)
                .presentationCornerRadius(Metrics.sheetCornerRadius)
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
            get: { session.sheet == .usage ? nil : session.sheet },
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
        case .usage:
            EmptyView()
        case .newSession:
            NewSessionSheet(session: session, initialKind: launchNewSessionKind)
                .onDisappear { launchNewSessionKind = nil }
        case .webServers:
            WebServersSheet(session: session)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.drawerBg)
                .presentationCornerRadius(Metrics.sheetCornerRadius)
        case .settings:
            SettingsScreen(session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Palette.black)
                .presentationCornerRadius(Metrics.sheetCornerRadius)
        }
    }
}

private struct UsagePanelLayer: View {
    @Bindable var session: AppSession
    @State private var dragOffset: CGFloat = 0

    private static let height: CGFloat = 473
    private static let cornerRadius: CGFloat = 30
    private static let closeThreshold: CGFloat = 0.25

    private var isPresented: Bool { session.sheet == .usage }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                UsageSheet(session: session)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.height, alignment: .top)
                    .background(
                        Palette.drawerBg,
                        in: UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius)
                    )
                    .offset(y: dragOffset)
                    .gesture(closeDrag)
                    .accessibilityAction(.escape) { session.dismissSheet() }
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.smooth(duration: 0.3), value: isPresented)
        .onChange(of: isPresented) {
            dragOffset = 0
        }
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.predictedEndTranslation.height > Self.height * Self.closeThreshold {
                    session.dismissSheet()
                } else {
                    withAnimation(.smooth(duration: 0.2)) { dragOffset = 0 }
                }
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
