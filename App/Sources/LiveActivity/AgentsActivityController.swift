import ActivityKit
import Foundation
import MochaClient
import MochaProtocol
import os
import UIKit

@MainActor
final class AgentsActivityController {
    static let shared = AgentsActivityController()

    private static let logger = Logger(subsystem: "com.joaoalves.mocha", category: "liveactivity")
    private static let staleInterval: TimeInterval = 15 * 60

    private let authorization = ActivityAuthorizationInfo()
    private var tokens: AgentsActivityTokenSync?
    private var tracker = AgentsActivityTracker()
    private var observedIds: Set<String> = []

    private var isEnabled: Bool {
        !ProcessInfo.processInfo.arguments.contains(LaunchConfiguration.demoFlag)
    }

    func startObserving() {
        guard isEnabled, tokens == nil else { return }
        let newest = Self.newestLiveActivity()
        tokens = AgentsActivityTokenSync(
            environment: PushRegistration.shared.environment.environment,
            liveActivityIds: Set(newest.map { [$0.id] } ?? []),
            gateway: GatewayAgentsActivityRegistrar(tokenStore: KeychainTokenStore())
        )
        deliver { await $0.deliverPending() }
        if let newest {
            observe(newest)
        }
        Task {
            await Self.endFeedActivities(except: newest?.id)
            await Self.endLegacyActivities()
        }
        Task { [weak self] in
            for await activity in Activity<MochaFeedAttributes>.activityUpdates {
                self?.adopt(activity)
            }
        }
        Task { [weak self] in
            for await token in Activity<MochaFeedAttributes>.pushToStartTokenUpdates {
                self?.receivePushToStartToken(token)
            }
        }
    }

    func socketOpened(send: @escaping @Sendable (LiveActivityRegistration) async -> Bool) {
        let registrar = SocketAgentsActivityRegistrar(send: send)
        deliver { await $0.socketOpened(registrar) }
    }

    func socketClosed() {
        deliver { await $0.socketClosed() }
    }

    func agentsChanged(_ agents: [AgentSummary]) {
        guard isEnabled else { return }
        let now = Date()
        let becameBusy = tracker.update(agents, at: now)
        guard AgentsActivityStartPolicy.shouldStart(
            becameBusy: !becameBusy.isEmpty,
            isForeground: UIApplication.shared.applicationState == .active,
            hasActivity: Self.hasLiveActivity(),
            activitiesEnabled: authorization.areActivitiesEnabled
        ), let focus = tracker.focus, let content = tracker.content(for: focus, at: now) else { return }
        start(content)
    }

    nonisolated static func clearPending(_ requestId: String) async {
        for activity in Activity<MochaFeedAttributes>.activities where isLive(activity.activityState) {
            let current = activity.content
            guard let cleared = AgentsActivityContent(current.state).clearingPending(requestId) else { continue }
            await activity.update(
                ActivityContent(state: cleared.attributesState, staleDate: current.staleDate),
                alertConfiguration: nil,
                timestamp: current.state.updatedAt
            )
        }
    }

    private func start(_ content: AgentsActivityContent) {
        let agentId = content.agentId
        do {
            let activity = try Activity.request(
                attributes: MochaFeedAttributes(),
                content: ActivityContent(state: content.attributesState, staleDate: content.updatedAt.addingTimeInterval(Self.staleInterval)),
                pushType: .token
            )
            Self.logger.info("started the live activity locally on \(agentId, privacy: .public)")
            adopt(activity)
        } catch {
            Self.logger.error("failed to start the live activity on \(agentId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func adopt(_ activity: Activity<MochaFeedAttributes>) {
        observe(activity)
        Task { await Self.endFeedActivities(except: activity.id) }
    }

    private func observe(_ activity: Activity<MochaFeedAttributes>) {
        let id = activity.id
        guard observedIds.insert(id).inserted else { return }
        if let token = activity.pushToken {
            receiveUpdateToken(token, activityId: id)
        }
        Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                self?.receiveUpdateToken(token, activityId: id)
            }
        }
        Task { [weak self] in
            for await state in activity.activityStateUpdates where !Self.isLive(state) {
                self?.forget(activityId: id)
            }
        }
    }

    private func receivePushToStartToken(_ data: Data) {
        let token = Self.hex(data)
        deliver { await $0.recordPushToStartToken(token) }
    }

    private func receiveUpdateToken(_ data: Data, activityId: String) {
        let token = Self.hex(data)
        deliver { await $0.recordUpdateToken(token, activityId: activityId) }
    }

    private func forget(activityId: String) {
        deliver { await $0.forgetActivity(activityId) }
    }

    private func deliver(_ operation: @escaping @Sendable (AgentsActivityTokenSync) async -> Void) {
        guard let tokens else { return }
        let assertion = BackgroundAssertion(name: "live-activity-tokens")
        Task {
            await operation(tokens)
            assertion.end()
        }
    }

    private static func newestLiveActivity() -> Activity<MochaFeedAttributes>? {
        Activity<MochaFeedAttributes>.activities
            .filter { isLive($0.activityState) }
            .reversed()
            .max { $0.content.state.updatedAt < $1.content.state.updatedAt }
    }

    private nonisolated static func endFeedActivities(except keptId: String?) async {
        for activity in Activity<MochaFeedAttributes>.activities where activity.id != keptId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func endLegacyActivities() async {
        for activity in Activity<MochaAgentAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<MochaAgentsAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func hasLiveActivity() -> Bool {
        Activity<MochaFeedAttributes>.activities.contains { isLive($0.activityState) }
    }

    private nonisolated static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class BackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
