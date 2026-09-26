import SwiftUI

extension View {
    func mochaGlass(tint: Color = Palette.glass, interactive: Bool = false, in shape: some Shape) -> some View {
        glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
    }
}
