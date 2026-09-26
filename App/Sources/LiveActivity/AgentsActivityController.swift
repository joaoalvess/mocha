import ActivityKit
import Foundation
import MochaProtocol
import Observation
import UIKit

struct AgentsActivitySnapshot: Identifiable, Equatable {
    let id: String
    var state: ActivityState
    var content: MochaAgentsAttributes.ContentState
    var updateToken: String?
}

enum AgentsActivityEvent: Sendable {
    case discovered(activityId: String, state: ActivityState)
    case pushToStartToken(String)
    case updateToken(activityId: String, token: String)
    case content(activityId: String, state: MochaAgentsAttributes.ContentState, receivedAt: Date, isInitial: Bool)
    case activityState(activityId: String, state: ActivityState)
}

@MainActor
@Observable
final class AgentsActivityController {
    static let shared = AgentsActivityController()

    private(set) var activities: [AgentsActivitySnapshot] = []
    private(set) var pushToStartToken: String?
    private(set) var areActivitiesEnabled = false
    private(set) var frequentPushesEnabled = false
    private(set) var lastError: String?

    @ObservationIgnored var onEvent: ((AgentsActivityEvent) -> Void)?
    @ObservationIgnored private let authorization = ActivityAuthorizationInfo()
    @ObservationIgnored private let tokenStore = LiveActivityTokenStore()
    @ObservationIgnored private var tokens = LiveActivityTokens()
    @ObservationIgnored private var observedIds: Set<String> = []
    @ObservationIgnored private var contentSeenIds: Set<String> = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    func startObserving() {
        guard tasks.isEmpty else { return }
        tokens = tokenStore.load()
        pushToStartToken = tokens.pushToStartToken
        areActivitiesEnabled = authorization.areActivitiesEnabled
        frequentPushesEnabled = authorization.frequentPushesEnabled
        for activity in Activity<MochaAgentsAttributes>.activities {
            observe(activity)
        }
        tasks.append(Task { [weak self] in
            for await activity in Activity<MochaAgentsAttributes>.activityUpdates {
                self?.observe(activity)
            }
        })
        tasks.append(Task { [weak self] in
            for await token in Activity<MochaAgentsAttributes>.pushToStartTokenUpdates {
                self?.receivePushToStartToken(token)
            }
        })
        tasks.append(Task { [weak self, authorization] in
            for await enabled in authorization.activityEnablementUpdates {
                self?.areActivitiesEnabled = enabled
            }
        })
        tasks.append(Task { [weak self, authorization] in
            for await enabled in authorization.frequentPushEnablementUpdates {
                self?.frequentPushesEnabled = enabled
            }
        })
    }

    @discardableResult
    func start(state: MochaAgentsAttributes.ContentState) -> String? {
        do {
            let activity = try Activity.request(
                attributes: MochaAgentsAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .token
            )
            lastError = nil
            observe(activity)
            return activity.id
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    func endAll() async {
        let finalState = MochaAgentsAttributes.ContentState(working: 0, waiting: 0, highlight: nil, updatedAt: Date())
        await Self.endActivities(with: finalState)
    }

    private nonisolated static func endActivities(with finalState: MochaAgentsAttributes.ContentState) async {
        for activity in Activity<MochaAgentsAttributes>.activities {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private func observe(_ activity: Activity<MochaAgentsAttributes>) {
        let id = activity.id
        guard observedIds.insert(id).inserted else { return }
        upsert(AgentsActivitySnapshot(
            id: id,
            state: activity.activityState,
            content: activity.content.state,
            updateToken: activity.pushToken.map(Self.hex)
        ))
        onEvent?(.discovered(activityId: id, state: activity.activityState))
        if let token = activity.pushToken {
            receiveUpdateToken(token, activityId: id)
        }
        tasks.append(Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                self?.receiveUpdateToken(token, activityId: id)
            }
        })
        tasks.append(Task { [weak self] in
            for await content in activity.contentUpdates {
                self?.receiveContent(content.state, activityId: id)
            }
        })
        tasks.append(Task { [weak self] in
            for await state in activity.activityStateUpdates {
                self?.receiveState(state, activityId: id)
            }
        })
    }

    private func receivePushToStartToken(_ data: Data) {
        let token = Self.hex(data)
        pushToStartToken = token
        tokens.pushToStartToken = token
        tokens.pushToStartReceivedAt = Date()
        persist()
        onEvent?(.pushToStartToken(token))
    }

    private func receiveUpdateToken(_ data: Data, activityId: String) {
        let token = Self.hex(data)
        update(activityId) { $0.updateToken = token }
        guard tokens.activities[activityId]?.updateToken != token else { return }
        tokens.activities[activityId] = LiveActivityTokens.ActivityRecord(
            updateToken: token,
            receivedAt: Date(),
            appState: Self.describe(UIApplication.shared.applicationState)
        )
        persist()
        onEvent?(.updateToken(activityId: activityId, token: token))
    }

    private func receiveContent(_ state: MochaAgentsAttributes.ContentState, activityId: String) {
        update(activityId) { $0.content = state }
        let isInitial = contentSeenIds.insert(activityId).inserted
        onEvent?(.content(activityId: activityId, state: state, receivedAt: Date(), isInitial: isInitial))
    }

    private func receiveState(_ state: ActivityState, activityId: String) {
        update(activityId) { $0.state = state }
        onEvent?(.activityState(activityId: activityId, state: state))
    }

    private func upsert(_ snapshot: AgentsActivitySnapshot) {
        if let index = activities.firstIndex(where: { $0.id == snapshot.id }) {
            activities[index] = snapshot
        } else {
            activities.append(snapshot)
        }
    }

    private func update(_ activityId: String, _ change: (inout AgentsActivitySnapshot) -> Void) {
        guard let index = activities.firstIndex(where: { $0.id == activityId }) else { return }
        change(&activities[index])
    }

    private func persist() {
        do {
            try tokenStore.save(tokens)
        } catch {
            lastError = String(describing: error)
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
