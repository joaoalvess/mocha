import CryptoKit
import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaDaemonCore

final class FakePushAudience: PushAudience {
    private struct State {
        var agents: [AgentID: AgentSummary]
        var foreground: [AgentID: Set<DeviceID>] = [:]
    }

    private let state: Mutex<State>

    init(agents: [AgentSummary] = [Sample.agent("w1:p1", sessionId: Sample.sessionA)]) {
        state = Mutex(State(agents: Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })))
    }

    func agentSummary(_ id: AgentID) async -> AgentSummary? {
        state.withLock { $0.agents[id] }
    }

    func foregroundDevices(for agentId: AgentID) async -> Set<DeviceID> {
        state.withLock { $0.foreground[agentId] ?? [] }
    }

    func setForeground(_ devices: Set<DeviceID>, for agentId: AgentID) {
        state.withLock { $0.foreground[agentId] = devices }
    }
}

final class CredentialLoads: Sendable {
    private let count = Mutex(0)

    var value: Int {
        count.withLock { $0 }
    }

    func increment() {
        count.withLock { $0 += 1 }
    }
}

struct PushHarness {
    static let otherToken = String(repeating: "cd", count: 32)

    let service: PushService
    let transport: FakeApnsTransport
    let devices: DeviceStore
    let audience: FakePushAudience
    let clock: ManualClock
    let privateKey: P256.Signing.PrivateKey
    let loads: CredentialLoads

    @discardableResult
    func device(
        _ name: String = "iPhone",
        token: String = PushTestData.deviceToken,
        env: ApnsEnvironment = .sandbox,
        turnDoneAlerts: Bool = true
    ) async throws -> DeviceRecord {
        let record = try await devices.register(name: name, token: "device-\(name)", at: Sample.start, apns: ApnsRegistration(token: token, env: env))
        if !turnDoneAlerts {
            _ = try await devices.setPreferences(DevicePreferences(turnDoneAlerts: false), for: record.id)
        }
        return record
    }

    func deliver(_ event: HookEvent, agent: AgentID = "w1:p1") async {
        await service.handle(ReceivedHook(agentId: agent, receivedAt: clock.now(), event: event))
        await service.waitForDeliveries()
    }

    func payloads() throws -> [[String: Any]] {
        try transport.requests.map { try PushTestData.jsonObject(try #require($0.httpBody)) }
    }

    func settleBlockedChecks() async throws {
        _ = try await eventually { await service.pendingBlockedChecks == 0 ? true : nil }
        await service.waitForDeliveries()
    }
}

enum PushHooks {
    static func stop(_ message: String? = "pronto") -> HookEvent {
        .stop(StopHook(context: HookContext(sessionId: Sample.sessionA), lastAssistantMessage: message))
    }

    static func notification(_ kind: NotificationKind = .permissionPrompt) -> HookEvent {
        .notification(NotificationHook(context: HookContext(sessionId: Sample.sessionA), message: "Claude needs your permission", kind: kind))
    }

    static func fixture(_ name: HookEventName, _ file: String) throws -> HookEvent {
        try HookEvent.decode(name, from: Fixtures.data("hooks/\(file)"))
    }
}

func withPush(
    responses: [ApnsResponse] = [],
    audience: FakePushAudience = FakePushAudience(),
    configuration: PushServiceConfiguration = PushServiceConfiguration(),
    credentialsError: ApnsError? = nil,
    _ body: (PushHarness) async throws -> Void
) async throws {
    let directory = try PushTestData.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let privateKey = P256.Signing.PrivateKey()
    let key = try PushTestData.signingKey(privateKey)
    let loads = CredentialLoads()
    let transport = FakeApnsTransport(responses: responses)
    let clock = ManualClock(origin: Sample.start)
    let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
    let service = PushService(
        devices: devices,
        audience: audience,
        credentials: {
            loads.increment()
            if let credentialsError {
                throw credentialsError
            }
            return ApnsCredentials(config: ApnsConfig(teamId: PushTestData.teamId, keyId: PushTestData.keyId), key: key)
        },
        transport: transport,
        clock: clock,
        configuration: configuration
    )
    let harness = PushHarness(
        service: service,
        transport: transport,
        devices: devices,
        audience: audience,
        clock: clock,
        privateKey: privateKey,
        loads: loads
    )
    do {
        try await body(harness)
    } catch {
        await service.shutdown()
        throw error
    }
    await service.shutdown()
}
