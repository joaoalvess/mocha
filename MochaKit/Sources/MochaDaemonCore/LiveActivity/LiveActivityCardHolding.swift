import MochaProtocol

public protocol LiveActivityCardHolding: Sendable {
    func cardDevices() async -> Set<DeviceID>
    func attachAlertHandoff(_ handoff: any LiveActivityAlertHandoff) async
}

public struct LiveActivityLostAlert: Sendable, Equatable {
    public let agentId: AgentID
    public let kind: PushAlertKind
    public let requestId: RequestID?
    public let title: String
    public let body: String

    public init(agentId: AgentID, kind: PushAlertKind, requestId: RequestID?, title: String, body: String) {
        self.agentId = agentId
        self.kind = kind
        self.requestId = requestId
        self.title = title
        self.body = body
    }
}

public protocol LiveActivityAlertHandoff: Sendable {
    func cardLost(_ alerts: [LiveActivityLostAlert], on device: DeviceID) async
}
