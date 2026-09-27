import Foundation
import MochaProtocol

extension HubError {
    static let invalidLiveActivityToken = HubError(code: .invalidPayload, message: "Token de Live Activity inválido.")
    static let liveActivityUnavailable = HubError(code: .internal, message: "Live Activity indisponível no Mac.")
}

extension SessionHub {
    public func attachLiveActivity(_ registrar: any LiveActivityRegistering) {
        liveActivityRegistrar = registrar
    }

    public nonisolated var liveActivityUpdates: AsyncStream<LiveActivityInput> {
        liveActivityInputs
    }

    func publishLiveActivityInput(_ tree: [WorkspaceNode]? = nil) {
        guard !isShuttingDown else { return }
        let agents = TreeComposer.agents(in: tree ?? composedTree())
        liveActivityInputContinuation.yield(LiveActivityInput(agents: agents, foregroundDevices: activeDevices()))
    }

    func registerLiveActivity(_ registration: LiveActivityRegistration, id: String, clientId: UUID) async {
        guard let deviceId = clients[clientId]?.deviceId else { return }
        guard let registrar = liveActivityRegistrar else {
            send(.liveActivityUnavailable, id: id, to: clientId)
            return
        }
        do {
            try await registrar.register(registration, from: deviceId)
            send(.ack(), id: id, to: clientId)
        } catch LiveActivityRegistrationError.invalidToken {
            send(.invalidLiveActivityToken, id: id, to: clientId)
        } catch {
            gatewayLogger.error("failed to register a live activity: \(PushService.describe(error), privacy: .public)")
            send(.deviceStoreFailed, id: id, to: clientId)
        }
    }

    private func activeDevices() -> Set<DeviceID> {
        var devices: Set<DeviceID> = []
        for client in clients.values where !client.isClosing && client.foreground?.isActive == true {
            if let deviceId = client.deviceId {
                devices.insert(deviceId)
            }
        }
        return devices
    }
}
