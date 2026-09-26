import SwiftUI

struct HomeBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Palette.black
                glow(radiusX: 260, radiusY: 330, opacity: 0.078)
                    .position(x: proxy.size.width / 2, y: 40)
                glow(radiusX: 250, radiusY: 240, opacity: 0.115)
                    .position(x: proxy.size.width, y: proxy.size.height)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(radiusX: CGFloat, radiusY: CGFloat, opacity: Double) -> some View {
        EllipticalGradient(
            colors: [Palette.statusOk.opacity(opacity), Palette.statusOk.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
        .frame(width: radiusX * 2, height: radiusY * 2)
    }
}
