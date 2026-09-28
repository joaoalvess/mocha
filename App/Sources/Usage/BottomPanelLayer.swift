import SwiftUI

enum BottomPanelHeight {
    case fixed(CGFloat)
    case screenFraction(CGFloat)

    func resolved(in proxy: GeometryProxy) -> CGFloat {
        switch self {
        case .fixed(let height):
            height
        case .screenFraction(let fraction):
            (proxy.size.height + proxy.safeAreaInsets.top) * fraction
        }
    }
}

struct BottomPanelLayer<Content: View>: View {
    @Bindable var session: AppSession
    let sheet: AppSheet
    let height: BottomPanelHeight
    @ViewBuilder let content: () -> Content
    @State private var dragOffset: CGFloat = 0

    private static var cornerRadius: CGFloat { 30 }
    private static var closeThreshold: CGFloat { 0.25 }

    private var isPresented: Bool { session.sheet == sheet }

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = height.resolved(in: proxy)
            ZStack(alignment: .bottom) {
                if isPresented {
                    content()
                        .frame(maxWidth: .infinity)
                        .frame(height: panelHeight, alignment: .top)
                        .background(
                            Palette.drawerBg,
                            in: UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius)
                        )
                        .offset(y: dragOffset)
                        .gesture(closeDrag(panelHeight: panelHeight))
                        .accessibilityAction(.escape) { session.dismissSheet() }
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.smooth(duration: 0.3), value: isPresented)
        .onChange(of: isPresented) {
            dragOffset = 0
        }
    }

    private func closeDrag(panelHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.predictedEndTranslation.height > panelHeight * Self.closeThreshold {
                    session.dismissSheet()
                } else {
                    withAnimation(.smooth(duration: 0.2)) { dragOffset = 0 }
                }
            }
    }
}
