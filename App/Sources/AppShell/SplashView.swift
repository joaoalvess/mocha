import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Mocha")
                .font(.system(.largeTitle, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}
