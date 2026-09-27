import Foundation
import MochaProtocol

extension SessionHub: PushAudience {
    static let transcriptPathLimit = 256

    public func agentSummary(_ id: AgentID) -> AgentSummary? {
        composedAgent(id)
    }

    public func foregroundDevices(for agentId: AgentID) -> Set<DeviceID> {
        var devices: Set<DeviceID> = []
        for client in clients.values where !client.isClosing {
            guard let deviceId = client.deviceId, let foreground = client.foreground else { continue }
            if foreground.isActive, foreground.agentId == agentId {
                devices.insert(deviceId)
            }
        }
        return devices
    }

    public func hookReceived(_ hook: ReceivedHook) {
        let context = hook.event.context
        guard let path = context.transcriptPath, !path.isEmpty, transcriptPaths[context.sessionId] != path else { return }
        if transcriptPaths.updateValue(path, forKey: context.sessionId) == nil {
            transcriptPathOrder.append(context.sessionId)
        }
        while transcriptPathOrder.count > Self.transcriptPathLimit {
            transcriptPaths[transcriptPathOrder.removeFirst()] = nil
        }
    }

    func transcriptSession(_ sessionId: String) -> TranscriptSession {
        TranscriptSession(sessionId: sessionId, transcriptPath: transcriptPaths[sessionId])
    }

    func transcriptSession(_ sessionId: String, subagent: SubagentTranscript?) -> TranscriptSession {
        guard let subagent else { return transcriptSession(sessionId) }
        return TranscriptSession(sessionId: sessionId, subagent: subagent)
    }
}
