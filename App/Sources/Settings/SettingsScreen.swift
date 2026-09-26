import SwiftUI

struct SettingsScreen: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .black) {
                    session.dismissSheet()
                }
                Spacer()
            }
            Text("Ajustes")
                .systemText(.sheetTitle)
                .foregroundStyle(Palette.textPrimary)
            SheetListCard {
                SheetListRow(label: "Mac", value: session.host?.hostName ?? "—")
                SheetListRow(label: "Conexão", value: session.connectionState.statusText)
                SheetListRow(label: "Herdr", value: herdrText)
                SheetListRow(label: "Versão do daemon", value: session.host?.daemonVersion ?? "—", valueStyle: .mono)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.contentMargin)
        .padding(.top, Metrics.contentMargin)
    }

    private var herdrText: String {
        switch session.herdrConnected {
        case true?: "conectado ao mochad"
        case false?: "desconectado"
        case nil: "—"
        }
    }
}
