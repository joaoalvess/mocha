import Network

public struct NetworkPathUpdate: Sendable, Equatable {
    public var isSatisfied: Bool
    public var interfaces: [String]

    public init(isSatisfied: Bool, interfaces: [String]) {
        self.isSatisfied = isSatisfied
        self.interfaces = interfaces
    }
}

public protocol NetworkPathMonitoring: Sendable {
    func updates() -> AsyncStream<NetworkPathUpdate>
}

public struct SystemNetworkPathMonitor: NetworkPathMonitoring {
    public init() {}

    public func updates() -> AsyncStream<NetworkPathUpdate> {
        AsyncStream { continuation in
            let task = Task {
                for await path in NWPathMonitor() {
                    continuation.yield(NetworkPathUpdate(
                        isSatisfied: path.status == .satisfied,
                        interfaces: path.availableInterfaces.map(\.name)
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
