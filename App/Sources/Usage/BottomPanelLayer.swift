import SwiftUI

struct BottomPanelLayer<Content: View>: View {
    let isPresented: Bool
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var dragOffset: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    private static var cornerRadius: CGFloat { 30 }
    private static var closeThreshold: CGFloat { 0.25 }
    private static var topGap: CGFloat { 40 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if isPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismiss)
                        .accessibilityHidden(true)
                    content()
                        .padding(.bottom, proxy.safeAreaInsets.bottom)
                        .frame(maxWidth: .infinity)
                        .background(
                            Palette.drawerBg,
                            in: UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius)
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                        .offset(y: dragOffset)
                        .gesture(closeDrag)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape, dismiss)
                        .padding(.top, Self.topGap)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
        }
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
                if value.predictedEndTranslation.height > panelHeight * Self.closeThreshold {
                    dismiss()
                } else {
                    withAnimation(.smooth(duration: 0.2)) { dragOffset = 0 }
                }
            }
    }
}
