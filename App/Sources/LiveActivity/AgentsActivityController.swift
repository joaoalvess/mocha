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
        let live = Activity<MochaAgentAttributes>.activities.filter { Self.isLive($0.activityState) }
        tokens = AgentsActivityTokenSync(
            environment: PushRegistration.shared.environment.environment,
            liveActivityIds: Set(live.map(\.id)),
            gateway: GatewayAgentsActivityRegistrar(tokenStore: KeychainTokenStore())
        )
        deliver { await $0.deliverPending() }
        for activity in live {
            observe(activity)
        }
        let newest = Dictionary(live.map { ($0.attributes.agentId, $0.id) }) { _, last in last }
        Task {
            for (agentId, keptId) in newest {
                await Self.endActivities(of: agentId, except: keptId)
            }
            await Self.endAggregatedActivities()
        }
        Task { [weak self] in
            for await activity in Activity<MochaAgentAttributes>.activityUpdates {
                self?.adopt(activity)
            }
        }
        Task { [weak self] in
            for await token in Activity<MochaAgentAttributes>.pushToStartTokenUpdates {
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
        let isForeground = UIApplication.shared.applicationState == .active
        for agentId in becameBusy.sorted() {
            guard AgentsActivityStartPolicy.shouldStart(
                isForeground: isForeground,
                hasActivityForAgent: Self.hasLiveActivity(for: agentId),
                activitiesEnabled: authorization.areActivitiesEnabled
            ), let content = tracker.content(for: agentId, at: now) else { continue }
            start(content, agentId: agentId)
        }
    }

    nonisolated static func clearPending(_ requestId: String) async {
        for activity in Activity<MochaAgentAttributes>.activities where isLive(activity.activityState) {
            let current = activity.content
            guard let cleared = AgentsActivityContent(current.state).clearingPending(requestId) else { continue }
            await activity.update(
                ActivityContent(state: cleared.attributesState, staleDate: current.staleDate),
                alertConfiguration: nil,
                timestamp: current.state.updatedAt
            )
        }
    }

    private func start(_ content: AgentsActivityContent, agentId: String) {
        do {
            let activity = try Activity.request(
                attributes: MochaAgentAttributes(agentId: agentId),
                content: ActivityContent(state: content.attributesState, staleDate: content.updatedAt.addingTimeInterval(Self.staleInterval)),
                pushType: .token
            )
            Self.logger.info("started the live activity of \(agentId, privacy: .public) locally")
            adopt(activity)
        } catch {
            Self.logger.error("failed to start the live activity of \(agentId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func adopt(_ activity: Activity<MochaAgentAttributes>) {
        observe(activity)
        Task { await Self.endActivities(of: activity.attributes.agentId, except: activity.id) }
    }

    private func observe(_ activity: Activity<MochaAgentAttributes>) {
        let id = activity.id
        let agentId = activity.attributes.agentId
        guard observedIds.insert(id).inserted else { return }
        if let token = activity.pushToken {
            receiveUpdateToken(token, activityId: id, agentId: agentId)
        }
        Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                self?.receiveUpdateToken(token, activityId: id, agentId: agentId)
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

    private func receiveUpdateToken(_ data: Data, activityId: String, agentId: String) {
        let token = Self.hex(data)
        deliver { await $0.recordUpdateToken(token, activityId: activityId, agentId: agentId) }
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

    private nonisolated static func endActivities(of agentId: String, except keptId: String) async {
        for activity in Activity<MochaAgentAttributes>.activities where activity.attributes.agentId == agentId && activity.id != keptId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func endAggregatedActivities() async {
        for activity in Activity<MochaAgentsAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func hasLiveActivity(for agentId: String) -> Bool {
        Activity<MochaAgentAttributes>.activities.contains { $0.attributes.agentId == agentId && isLive($0.activityState) }
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
