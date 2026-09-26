#if DEBUG
import ActivityKit
import Foundation
import MochaProtocol
import Observation
import UIKit
import UserNotifications

struct PushProbeEntry: Identifiable, Sendable {
    let id: Int
    let date: Date
    let text: String
}

@MainActor
@Observable
final class PushProbeModel {
    static let maxEntries = 300
    static let timeFormat = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
        .secondFraction(.fractional(3))

    let push = PushRegistration.shared
    let activities = AgentsActivityController.shared
    private(set) var entries: [PushProbeEntry] = []
    private(set) var delivered: [String] = []

    @ObservationIgnored private let files = PushProbeFiles()
    @ObservationIgnored private var entryCounter = 0
    @ObservationIgnored private var didAppear = false
    @ObservationIgnored private var notificationDelegate: PushProbeNotificationDelegate?

    func appear() async {
        guard !didAppear else { return }
        didAppear = true
        UserDefaults.standard.set("push", forKey: "probe")
        let delegate = PushProbeNotificationDelegate { [weak self] received in
            self?.notificationArrived(received)
        }
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        activities.onEvent = { [weak self] event in
            self?.activityEvent(event)
        }
        activities.startObserving()
        record("sonda aberta · env \(push.environment.environment.rawValue) (\(push.environment.source))", kind: "probe")
        await push.refreshAuthorization()
        UIApplication.shared.registerForRemoteNotifications()
        saveSnapshot()
        await runLaunchAction()
    }

    func requestPermission() async {
        await push.requestAuthorizationAndRegister()
        record("permissão: \(Self.describe(push.authorization))", kind: "permission")
        saveSnapshot()
    }

    func deviceTokenChanged() {
        guard let token = push.deviceTokenHex else { return }
        record("token APNs recebido: \(token.prefix(8))…", kind: "token")
        saveSnapshot()
    }

    func startActivity() {
        let now = Date()
        let state = MochaAgentsAttributes.ContentState(
            working: 1,
            waiting: 0,
            highlight: .init(
                agentId: "w1:p1",
                title: "Iniciada pelo app",
                workspaceLabel: "demo-app",
                status: "working",
                since: now
            ),
            updatedAt: now
        )
        if let id = activities.start(state: state) {
            record("Live Activity iniciada pelo app: \(id.prefix(8))", kind: "activityStart")
        } else {
            record("falha ao iniciar: \(activities.lastError ?? "?")", kind: "activityStart")
        }
        saveSnapshot()
    }

    func endActivities() async {
        await activities.endAll()
        record("Live Activities encerradas pelo app", kind: "activityEnd")
        saveSnapshot()
    }

    func copy(_ value: String?, label: String) {
        guard let value else { return }
        UIPasteboard.general.string = value
        record("\(label) copiado", kind: "copy")
    }

    func refreshDelivered() async {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        delivered = notifications.map { notification in
            "\(notification.date.formatted(Self.timeFormat)) [\(notification.request.identifier.prefix(24))] \(notification.request.content.title)"
        }
        record("entregues na Central: \(notifications.count)", kind: "delivered")
    }

    func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        delivered = []
    }

    func unpin() {
        UserDefaults.standard.removeObject(forKey: "probe")
        record("sonda desafixada: o próximo launch sem -probe abre o app normal", kind: "probe")
    }

    private func runLaunchAction() async {
        switch UserDefaults.standard.string(forKey: "probeAction") {
        case "startActivity":
            startActivity()
        case "endActivities":
            await endActivities()
        case "requestPermission":
            await requestPermission()
        default:
            break
        }
    }

    private func notificationArrived(_ received: PushProbeReceivedNotification) {
        let sentAt = received.sentAtMilliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
        let delay = sentAt.map { received.receivedAt.timeIntervalSince($0) * 1000 }
        let delayText = delay.map { String(format: "%.0f ms", $0) } ?? "sem sentAt"
        record(
            "alerta recebido em primeiro plano (\(received.interruptionLevel)) [\(received.identifier.prefix(24))] \(received.title): atraso \(delayText)",
            kind: "alert",
            sentAt: sentAt,
            delayMs: delay,
            at: received.receivedAt
        )
    }

    private func activityEvent(_ event: AgentsActivityEvent) {
        switch event {
        case .discovered(let id, let state):
            record("atividade \(id.prefix(8)) observada (\(Self.describe(state)))", kind: "activityDiscovered")
        case .pushToStartToken(let token):
            record("token de push-to-start: \(token.prefix(8))…", kind: "token")
        case .updateToken(let id, let token):
            record("token de update da atividade \(id.prefix(8)): \(token.prefix(8))…", kind: "token")
        case .content(let id, let state, _, true):
            record(
                "estado atual da atividade \(id.prefix(8)): \(state.working) trabalhando, \(state.waiting) esperando",
                kind: "activityInitialContent"
            )
        case .content(let id, let state, let receivedAt, false):
            let delay = receivedAt.timeIntervalSince(state.updatedAt) * 1000
            record(
                String(format: "update da atividade %@: %d trabalhando, %d esperando · atraso %.0f ms", String(id.prefix(8)), state.working, state.waiting, delay),
                kind: "activityContent",
                sentAt: state.updatedAt,
                delayMs: delay,
                at: receivedAt
            )
        case .activityState(let id, let state):
            record("atividade \(id.prefix(8)): \(Self.describe(state))", kind: "activityState")
        }
        saveSnapshot()
    }

    private func record(_ text: String, kind: String, sentAt: Date? = nil, delayMs: Double? = nil, at date: Date = Date()) {
        entryCounter += 1
        entries.insert(PushProbeEntry(id: entryCounter, date: date, text: text), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        try? files.append(PushProbeEvent(at: date, kind: kind, detail: text, sentAt: sentAt, delayMs: delayMs))
    }

    private func saveSnapshot() {
        let snapshot = PushProbeSnapshot(
            writtenAt: Date(),
            apnsToken: push.deviceTokenHex,
            env: push.environment.environment.rawValue,
            envSource: push.environment.source,
            authorization: Self.describe(push.authorization),
            pushToStartToken: activities.pushToStartToken,
            activities: activities.activities.map {
                PushProbeSnapshot.Activity(id: $0.id, state: Self.describe($0.state), updateToken: $0.updateToken)
            }
        )
        try? files.write(snapshot)
    }

    static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "não pedida"
        case .denied: "negada"
        case .authorized: "autorizada"
        case .provisional: "provisória"
        case .ephemeral: "efêmera"
        @unknown default: "desconhecida"
        }
    }

    static func describe(_ state: ActivityState) -> String {
        switch state {
        case .pending: "pendente"
        case .active: "ativa"
        case .ended: "encerrada"
        case .dismissed: "removida"
        case .stale: "desatualizada"
        @unknown default: "desconhecida"
        }
    }
}
#endif
