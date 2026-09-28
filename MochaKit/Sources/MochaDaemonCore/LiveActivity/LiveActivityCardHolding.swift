import MochaProtocol

public protocol LiveActivityCardHolding: Sendable {
    func cardHolder() async -> AgentID?
    func attachAlertFallback(_ fallback: any LiveActivityAlertFallback) async
}

public protocol LiveActivityAlertFallback: Sendable {
    func cardAlert(_ kind: PushAlertKind, of agentId: AgentID, on device: DeviceID, wasShown: Bool) async
}
