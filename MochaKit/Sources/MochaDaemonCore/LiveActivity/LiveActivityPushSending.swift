import MochaProtocol

public enum LiveActivityDelivery: Sendable, Equatable {
    case delivered
    case invalidToken
    case failed(retryable: Bool)
}

public protocol LiveActivityPushSending: Sendable {
    func sendLiveActivity(
        _ push: LiveActivityPush,
        to token: String,
        environment: ApnsEnvironment,
        priority: ApnsPriority
    ) async -> LiveActivityDelivery
}
