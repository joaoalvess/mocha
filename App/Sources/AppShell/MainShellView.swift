import SwiftUI

struct MainShellView: View {
    @Bindable var session: AppSession
    @State private var dragTranslation: CGFloat = 0

    private static let scrimOpacity = 0.5
    private static let edgeActivationWidth: CGFloat = 24
    private static let toggleThreshold: CGFloat = 0.35

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = proxy.size.width * Metrics.drawerWidthFraction
            let progress = drawerProgress(width: drawerWidth)
            ZStack(alignment: .leading) {
                chatLayer
                Color.black
                    .opacity(Self.scrimOpacity * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(session.isDrawerOpen)
                    .onTapGesture { session.isDrawerOpen = false }
                    .accessibilityHidden(true)
                DrawerScreen(session: session)
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    .offset(x: (progress - 1) * drawerWidth)
                    .accessibilityHidden(!session.isDrawerOpen)
            }
            .simultaneousGesture(drawerDrag(width: drawerWidth))
            .animation(.smooth(duration: 0.28), value: session.isDrawerOpen)
        }
        .background(Palette.bg.ignoresSafeArea())
        .task { session.start() }
    }

    @ViewBuilder
    private var chatLayer: some View {
        if let agentId = session.visibleChat?.agentId {
            ChatScreen(session: session, agentId: agentId)
        } else {
            NoChatView(session: session)
        }
    }

    private func drawerProgress(width: CGFloat) -> CGFloat {
        let base: CGFloat = session.isDrawerOpen ? 1 : 0
        return min(1, max(0, base + dragTranslation / width))
    }

    private func drawerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if session.isDrawerOpen {
                    dragTranslation = min(0, value.translation.width)
                } else if value.startLocation.x <= Self.edgeActivationWidth {
                    dragTranslation = max(0, value.translation.width)
                }
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                withAnimation(.smooth(duration: 0.28)) {
                    if session.isDrawerOpen, dragTranslation < 0 {
                        session.isDrawerOpen = -predicted < width * Self.toggleThreshold
                    } else if !session.isDrawerOpen, dragTranslation > 0 {
                        session.isDrawerOpen = predicted > width * Self.toggleThreshold
                    }
                    dragTranslation = 0
                }
            }
    }
}

struct NoChatView: View {
    @Bindable var session: AppSession

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                StatusDot(indicator: session.connectionState == .connected ? .agent(.idle) : .disconnected)
                Text(headline)
                    .font(Typography.chatBody)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                if session.connectionState == .connected {
                    DrawerButton { session.isDrawerOpen = true }
                }
            }
            .padding(Metrics.contentMargin)
        }
    }

    private var headline: String {
        guard session.connectionState == .connected else { return session.connectionState.statusText }
        return "Escolha um agente na gaveta"
    }
}
