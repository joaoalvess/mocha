#if DEBUG
import SwiftUI

struct GatewayProbeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = GatewayProbeModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statistics
            controls
            Divider()
            log
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal)
        .onAppear { model.pinProbe() }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            model.scenePhaseChanged(newPhase)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sonda do gateway (S5)")
                .font(.system(.headline, design: .monospaced))
            Text(model.url?.absoluteString ?? "URL inválida")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 10, height: 10)
                Text(phaseText)
                Spacer()
                Text("rede: \(model.network)")
            }
        }
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("último eco: \(model.lastRoundTripMs.map { String(format: "%.1f ms", $0) } ?? "-")")
            ForEach(model.roundTripsByNetwork.keys.sorted(), id: \.self) { network in
                Text(Self.summary(of: model.roundTripsByNetwork[network] ?? [], network: network))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(model.wantsConnection ? "Desconectar" : "Conectar") { model.toggleConnection() }
                Button("Enviar eco") { model.sendEcho() }
                    .disabled(model.phase != .connected)
                Button("Health") { Task { await model.checkHealth() } }
            }
            HStack {
                Button("POST 1 MB") { Task { await model.postBody() } }
                Button("Limpar") { model.clearLog() }
                Button("Desafixar") { model.unpinProbe() }
            }
            Toggle("Eco automático a cada 2 s", isOn: $model.autoEcho)
        }
        .buttonStyle(.bordered)
    }

    private var log: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(model.entries) { entry in
                    Text("\(entry.date.formatted(GatewayProbeModel.timeFormat)) \(entry.text)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var phaseText: String {
        switch model.phase {
        case .stopped: "parado"
        case .connecting(let attempt): "conectando (tentativa \(attempt))"
        case .connected: "conectado"
        case .waiting(let attempt, let delay): String(format: "tentativa %d em %.2f s", attempt, delay)
        case .background: "em background (fechado)"
        }
    }

    private var phaseColor: Color {
        switch model.phase {
        case .connected: .green
        case .connecting, .waiting: .orange
        case .stopped, .background: .gray
        }
    }

    private static func summary(of values: [Double], network: String) -> String {
        guard !values.isEmpty else { return "\(network): sem amostras" }
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        return "\(network): " + String(
            format: "mediana %.1f · p90 %.1f · mín %.1f · máx %.1f ms (n=%d)",
            median, p90, sorted.first ?? 0, sorted.last ?? 0, sorted.count
        )
    }
}
#endif
