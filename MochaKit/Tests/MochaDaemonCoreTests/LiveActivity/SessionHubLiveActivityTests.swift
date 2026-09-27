import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

private final class LiveActivityInputRecorder: Sendable {
    private let latest = Mutex<LiveActivityInput?>(nil)

    var input: LiveActivityInput? {
        latest.withLock { $0 }
    }

    func record(_ input: LiveActivityInput) {
        latest.withLock { $0 = input }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SessionHubLiveActivityTests {
    private static let registration = LiveActivityRegistration(
        pushToStartToken: LiveActivitySample.pushToStartToken,
        activityId: LiveActivitySample.activityId,
        updateToken: LiveActivitySample.updateToken,
        agentId: "w1:p1",
        env: .sandbox
    )

    private func reply(_ socket: TestClientSocket, to message: ClientMessage, id: String) async throws -> ServerMessage {
        try socket.deliver(message, id: id)
        while true {
            let envelope = try await socket.next()
            if envelope.id == id {
                return envelope.message
            }
        }
    }

    @Test func registerLiveActivityIsAcknowledgedForTheConnectedDevice() async throws {
        try await withHub { harness in
            let registrar = FakeLiveActivityRegistrar()
            await harness.hub.attachLiveActivity(registrar)
            let (socket, helloOk) = try await harness.pairedClient()

            #expect(try await socket.reply(to: .registerLiveActivity(Self.registration), id: "c-1") == .ack())
            #expect(registrar.registered == [.init(registration: Self.registration, deviceId: helloOk.deviceId)])
        }
    }

    @Test func anInvalidTokenIsInvalidPayloadAndOtherFailuresAreInternal() async throws {
        try await withHub { harness in
            let registrar = FakeLiveActivityRegistrar()
            await harness.hub.attachLiveActivity(registrar)
            let (socket, _) = try await harness.pairedClient()

            registrar.fail(with: LiveActivityRegistrationError.invalidToken)
            let invalid = try await socket.reply(to: .registerLiveActivity(Self.registration), id: "c-1")
            #expect(invalid.errorCode == .invalidPayload)
            #expect(invalid.errorMessage == "Token de Live Activity inválido.")

            registrar.fail(with: CocoaError(.fileWriteUnknown))
            #expect(try await socket.reply(to: .registerLiveActivity(Self.registration), id: "c-2").errorCode == .internal)
            #expect(registrar.registered.isEmpty)
        }
    }

    @Test func theServiceSavesValidTokensAndRefusesInvalidOnes() async throws {
        try await withHub { harness in
            let service = LiveActivityService(devices: harness.devices, sender: FakeLiveActivitySender(), clock: harness.clock)
            await harness.hub.attachLiveActivity(service)
            let (socket, helloOk) = try await harness.pairedClient()

            let invalid = LiveActivityRegistration(pushToStartToken: "zz", env: .sandbox)
            #expect(try await socket.reply(to: .registerLiveActivity(invalid), id: "c-1").errorCode == .invalidPayload)
            #expect(try await harness.devices.devices().first?.liveActivity == nil)

            #expect(try await socket.reply(to: .registerLiveActivity(Self.registration), id: "c-2") == .ack())
            let record = try #require(try await harness.devices.devices().first { $0.id == helloOk.deviceId })
            #expect(record.liveActivity == LiveActivityRegistration(pushToStartToken: LiveActivitySample.pushToStartToken, env: .sandbox))
            #expect(record.agentActivities == [
                LiveActivityRegistration(activityId: LiveActivitySample.activityId, updateToken: LiveActivitySample.updateToken, agentId: "w1:p1", env: .sandbox),
            ])
            await service.shutdown()
        }
    }

    @Test func withoutTheServiceTheRequestIsAnInternalError() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(try await socket.reply(to: .registerLiveActivity(Self.registration), id: "c-1").errorCode == .internal)
        }
    }

    @Test func foregroundAndAgentStatusReachTheLiveActivityInputs() async throws {
        try await withHub { harness in
            let recorder = LiveActivityInputRecorder()
            let updates = harness.hub.liveActivityUpdates
            let collector = Task {
                for await input in updates {
                    recorder.record(input)
                }
            }
            defer { collector.cancel() }
            let (socket, helloOk) = try await harness.pairedClient()

            #expect(try await socket.reply(to: .setForeground(agentId: "w1:p1", isActive: true), id: "c-1") == .ack())
            _ = try await eventually { recorder.input?.foregroundDevices == [helloOk.deviceId] ? true : nil }

            harness.herdr.emit(.agentStatus("w1:p1", .working, title: nil))
            _ = try await socket.nextMessage { message in
                if case .agentStatus = message {
                    return true
                }
                return false
            }
            try await harness.advanceTreeDebounce()
            let working = try await eventually { () -> LiveActivityInput? in
                guard let input = recorder.input, input.agents.first(where: { $0.id == "w1:p1" })?.status == .working else { return nil }
                return input
            }
            #expect(working.foregroundDevices == [helloOk.deviceId])
            #expect(working.agents.map(\.id) == ["w1:p1", "w1:p2"])
            #expect(working.tabTitles == ["w1:p1": "Claude", "w1:p2": "Codex"])

            #expect(try await reply(socket, to: .setForeground(agentId: nil, isActive: false), id: "c-2") == .ack())
            _ = try await eventually { recorder.input?.foregroundDevices.isEmpty == true ? true : nil }

            #expect(try await reply(socket, to: .setForeground(agentId: nil, isActive: true), id: "c-3") == .ack())
            _ = try await eventually { recorder.input?.foregroundDevices == [helloOk.deviceId] ? true : nil }
            socket.disconnect()
            _ = try await eventually { recorder.input?.foregroundDevices.isEmpty == true ? true : nil }
        }
    }

    @Test func aPendingRequestReachesTheLiveActivityInputsWhenCreatedAndWhenResolved() async throws {
        try await withPendingHub { hub, pending in
            let recorder = LiveActivityInputRecorder()
            let updates = hub.hub.liveActivityUpdates
            let collector = Task {
                for await input in updates {
                    recorder.record(input)
                }
            }
            defer { collector.cancel() }

            let held = try await pending.hold("PermissionRequest.bash.json")
            let request = try #require(await pending.store.requests.first)
            _ = try await eventually { await hub.hub.pendingRequests == [request] ? true : nil }
            try await hub.advanceTreeDebounce()
            let created = try await eventually { () -> LiveActivityInput? in
                guard let input = recorder.input, input.pending == [request] else { return nil }
                return input
            }
            #expect(created.agents.first { $0.id == PendingSample.agent }?.pendingCount == 1)

            try await pending.store.respond(to: held.requestId, with: .allow)
            _ = try await eventually { await hub.hub.pendingRequests.isEmpty ? true : nil }
            try await hub.advanceTreeDebounce()
            let resolved = try await eventually { () -> LiveActivityInput? in
                guard let input = recorder.input, input.pending.isEmpty else { return nil }
                return input
            }
            #expect(resolved.agents.first { $0.id == PendingSample.agent }?.pendingCount == 0)
            #expect(try OrderedJSON.parse(await held.response().body) == PendingHookReply.allow())
        }
    }
}
