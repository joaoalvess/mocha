import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

enum LiveActivitySample {
    static let pushToStartToken = String(repeating: "a1", count: 40)
    static let updateToken = String(repeating: "b2", count: 40)
    static let otherUpdateToken = String(repeating: "c3", count: 40)
    static let activityId = "B4F1C2D3-9E8A-4B7C-A6D5-E4F3A2B1C0D9"

    static func agent(
        _ id: AgentID,
        _ status: AgentStatus,
        title: String = "Refatorar o parser",
        workspaceLabel: String = "demo-app",
        pendingCount: Int = 0,
        kind: String = "claude"
    ) -> AgentSummary {
        AgentSummary(id: id, kind: kind, status: status, title: title, workspaceLabel: workspaceLabel, pendingCount: pendingCount)
    }

    static func permission(
        _ id: RequestID,
        agent: AgentID,
        createdAt: Date = Sample.start,
        toolName: String = "Bash",
        summary: String = "rm -rf build"
    ) -> PendingRequest {
        PendingRequest(
            id: id,
            agentId: agent,
            createdAt: createdAt,
            kind: .permission(toolName: toolName, summary: summary, inputJSON: "{\"command\":\"\(summary)\"}")
        )
    }

    static func question(_ id: RequestID, agent: AgentID, createdAt: Date = Sample.start, questions: [PendingQuestion]) -> PendingRequest {
        PendingRequest(id: id, agentId: agent, createdAt: createdAt, kind: .question(questions: questions))
    }

    static func singleQuestion(_ text: String, labels: [String], multiSelect: Bool = false) -> PendingQuestion {
        PendingQuestion(header: "Pergunta", question: text, options: labels.map { PendingOption(label: $0) }, multiSelect: multiSelect)
    }
}

struct LiveActivityHarness {
    let service: LiveActivityService
    let sender: FakeLiveActivitySender
    let devices: DeviceStore
    let clock: ManualClock

    func pair(_ name: String = "iPhone") async throws -> DeviceID {
        try await devices.register(name: name, token: "device-\(name)", at: Sample.start).id
    }

    func pairWithPushToStart(_ name: String = "iPhone") async throws -> DeviceID {
        let device = try await pair(name)
        try await service.register(LiveActivityRegistration(pushToStartToken: LiveActivitySample.pushToStartToken, env: .sandbox), from: device)
        return device
    }

    func registerUpdateToken(
        _ token: String = LiveActivitySample.updateToken,
        activityId: String = LiveActivitySample.activityId,
        for device: DeviceID
    ) async throws {
        try await service.register(
            LiveActivityRegistration(
                pushToStartToken: LiveActivitySample.pushToStartToken,
                activityId: activityId,
                updateToken: token,
                env: .sandbox
            ),
            from: device
        )
        try await settle()
    }

    func agents(_ agents: [AgentSummary], pending: [PendingRequest] = [], foreground: Set<DeviceID> = []) async throws {
        await service.apply(LiveActivityInput(agents: agents, pending: pending, foregroundDevices: foreground))
        try await settle()
    }

    func advance(_ seconds: TimeInterval) async throws {
        try await settle()
        if await service.nextWake != nil {
            try await clock.waitForSleepers(1)
        }
        clock.advance(by: .milliseconds(Int64((seconds * 1000).rounded())))
        try await settle()
    }

    func settle() async throws {
        _ = try await eventually { () async -> Bool? in
            await service.waitForSends()
            guard let wake = await service.nextWake else { return true }
            return wake.timeIntervalSince(clock.now()) > 0.001 ? true : nil
        }
        await service.waitForSends()
    }

    var sent: [FakeLiveActivitySender.Sent] {
        sender.sent
    }

    func last() throws -> FakeLiveActivitySender.Sent {
        try #require(sender.sent.last)
    }

    func aps(_ sent: FakeLiveActivitySender.Sent) throws -> [String: Any] {
        try #require(try PushTestData.jsonObject(try sent.push.payload())["aps"] as? [String: Any])
    }

    func storedRegistration(_ device: DeviceID) async throws -> LiveActivityRegistration? {
        try await devices.devices().first { $0.id == device }?.liveActivity
    }
}

func withLiveActivity(
    configuration: LiveActivityConfiguration = LiveActivityConfiguration(),
    _ body: (LiveActivityHarness) async throws -> Void
) async throws {
    let directory = try PushTestData.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
    let clock = ManualClock(origin: Sample.start)
    let sender = FakeLiveActivitySender()
    let service = LiveActivityService(devices: devices, sender: sender, clock: clock, configuration: configuration)
    let harness = LiveActivityHarness(service: service, sender: sender, devices: devices, clock: clock)
    do {
        try await body(harness)
    } catch {
        await service.shutdown()
        throw error
    }
    await service.shutdown()
}
