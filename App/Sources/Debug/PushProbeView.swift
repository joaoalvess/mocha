#if DEBUG
import SwiftUI

struct PushProbeView: View {
    @State private var model = PushProbeModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sonda de push (S4)")
                    .font(.system(.headline, design: .monospaced))
                notifications
                Divider()
                liveActivities
                Divider()
                deliveredList
                Divider()
                log
            }
            .padding(.horizontal)
        }
        .font(.system(.caption, design: .monospaced))
        .buttonStyle(.bordered)
        .task { await model.appear() }
        .onChange(of: model.push.deviceTokenHex) { _, _ in
            model.deviceTokenChanged()
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alertas").font(.system(.subheadline, design: .monospaced).bold())
            Text("permissão: \(PushProbeModel.describe(model.push.authorization))")
            Text("env: \(model.push.environment.environment.rawValue) · \(model.push.environment.source)")
            tokenRow("token APNs", model.push.deviceTokenHex)
            if let error = model.push.lastError {
                Text("erro: \(error)").foregroundStyle(.red)
            }
            Button("Pedir permissão e registrar") {
                Task { await model.requestPermission() }
            }
        }
    }

    private var liveActivities: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Activity").font(.system(.subheadline, design: .monospaced).bold())
            Text("ativadas: \(model.activities.areActivitiesEnabled ? "sim" : "não") · pushes frequentes: \(model.activities.frequentPushesEnabled ? "sim" : "não")")
            tokenRow("push-to-start", model.activities.pushToStartToken)
            ForEach(model.activities.activities) { activity in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(activity.id.prefix(8)) · \(PushProbeModel.describe(activity.state)) · \(activity.content.working) trabalhando, \(activity.content.waiting) esperando")
                    tokenRow("update", activity.updateToken)
                }
            }
            if let error = model.activities.lastError {
                Text("erro: \(error)").foregroundStyle(.red)
            }
            HStack {
                Button("Iniciar Live Activity") { model.startActivity() }
                Button("Encerrar") { Task { await model.endActivities() } }
            }
        }
    }

    private var deliveredList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Entregues") { Task { await model.refreshDelivered() } }
                Button("Limpar Central") { model.clearDelivered() }
                Button("Desafixar") { model.unpin() }
            }
            ForEach(model.delivered, id: \.self) { line in
                Text(line)
            }
        }
    }

    private var log: some View {
        LazyVStack(alignment: .leading, spacing: 3) {
            ForEach(model.entries) { entry in
                Text("\(entry.date.formatted(PushProbeModel.timeFormat)) \(entry.text)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func tokenRow(_ label: String, _ token: String?) -> some View {
        HStack {
            Text("\(label): \(token.map { "\($0.prefix(8))… (\($0.count / 2) bytes)" } ?? "-")")
            Spacer()
            Button("Copiar") { model.copy(token, label: label) }
                .disabled(token == nil)
        }
    }
}
#endif
