import Foundation
import MochaProtocol
import Observation
import UserNotifications

@MainActor
@Observable
final class UsageResetReminder {
    static let shared = UsageResetReminder()

    private(set) var armedResets: [AgentProvider: Date]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        armedResets = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            AgentProvider(rawValue: key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
    }

    func isArmed(_ provider: AgentProvider, now: Date = Date()) -> Bool {
        guard let resetsAt = armedResets[provider] else { return false }
        return resetsAt > now
    }

    func toggle(_ provider: AgentProvider, resetsAt: Date) {
        if isArmed(provider) {
            disarm(provider)
        } else {
            arm(provider, resetsAt: resetsAt)
        }
    }

    func usageChanged(_ snapshot: UsageSnapshot, now: Date = Date()) {
        guard let armed = armedResets[snapshot.provider] else { return }
        guard armed > now else {
            armedResets[snapshot.provider] = nil
            persist()
            return
        }
        guard let resetsAt = Self.fiveHourReset(of: snapshot), resetsAt > now, resetsAt != armed else { return }
        arm(snapshot.provider, resetsAt: resetsAt)
    }

    static func fiveHourReset(of snapshot: UsageSnapshot) -> Date? {
        snapshot.windows.first { $0.kind == .fiveHour }?.resetsAt
    }

    private func arm(_ provider: AgentProvider, resetsAt: Date) {
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return }
        armedResets[provider] = resetsAt
        persist()
        let content = UNMutableNotificationContent()
        content.title = "Janela de 5h zerada"
        content.body = "O limite de 5h do \(Self.name(of: provider)) renovou."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: provider),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        Task {
            await PushRegistration.shared.requestAuthorizationIfNeeded()
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func disarm(_ provider: AgentProvider) {
        armedResets[provider] = nil
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: provider)])
    }

    private func persist() {
        let stored = Dictionary(uniqueKeysWithValues: armedResets.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    private static func name(of provider: AgentProvider) -> String {
        provider == .codex ? "Codex" : "Claude Code"
    }

    private static func identifier(for provider: AgentProvider) -> String {
        "usage-reset-\(provider.rawValue)"
    }

    private static let defaultsKey = "usage.resetReminders"
}
