import MochaProtocol
import SwiftUI

struct PairingScreen: View {
    @Bindable var session: AppSession

    var body: some View {
        ZStack {
            HomeBackground()
            VStack(spacing: 12) {
                ClaudeMark(size: 36)
                Text("Parear com o Mac")
                    .systemText(.sheetTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .systemText(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Metrics.contentMargin)
        }
    }

    private var message: String {
        switch session.connectionState {
        case .pairingRequired(let problem?), .failed(let problem):
            return problem.message
        case .idle, .connecting, .connected, .waitingToRetry, .pairingRequired(.none):
            if let host = session.pairingLink?.url.host(), session.connectionState != .connected {
                return "Conectando ao \(host)…"
            }
            return "Rode mochad pair no Mac e leia o QR."
        }
    }
}
