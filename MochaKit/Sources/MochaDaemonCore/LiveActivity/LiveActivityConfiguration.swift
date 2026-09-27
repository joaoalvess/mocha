import Foundation

public struct LiveActivityConfiguration: Sendable {
    public var updateInterval: TimeInterval
    public var idleTimeout: TimeInterval
    public var renewalAge: TimeInterval
    public var staleInterval: TimeInterval
    public var dismissalDelay: TimeInterval
    public var refreshInterval: TimeInterval
    public var pushToStartLimit: Int
    public var pushToStartWindow: TimeInterval
    public var retryDelay: TimeInterval
    public var configurationRetryDelay: TimeInterval
    public var titleLimit: Int

    public init(
        updateInterval: TimeInterval = 10,
        idleTimeout: TimeInterval = 30 * 60,
        renewalAge: TimeInterval = 7 * 3600 + 50 * 60,
        staleInterval: TimeInterval = 15 * 60,
        dismissalDelay: TimeInterval = 0,
        refreshInterval: TimeInterval = 10 * 60,
        pushToStartLimit: Int = 10,
        pushToStartWindow: TimeInterval = 3600,
        retryDelay: TimeInterval = 10,
        configurationRetryDelay: TimeInterval = 5 * 60,
        titleLimit: Int = 60
    ) {
        self.updateInterval = updateInterval
        self.idleTimeout = idleTimeout
        self.renewalAge = renewalAge
        self.staleInterval = staleInterval
        self.dismissalDelay = dismissalDelay
        self.refreshInterval = refreshInterval
        self.pushToStartLimit = pushToStartLimit
        self.pushToStartWindow = pushToStartWindow
        self.retryDelay = retryDelay
        self.configurationRetryDelay = configurationRetryDelay
        self.titleLimit = titleLimit
    }
}
