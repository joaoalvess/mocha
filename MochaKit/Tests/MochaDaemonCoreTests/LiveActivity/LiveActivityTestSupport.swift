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

    static func token(_ index: Int) -> String {
        String(repeating: String(format: "%02x", index), count: 40)
    }

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

    static func tree(_ tabs: [TabNode], children: [WorkspaceNode] = []) -> [WorkspaceNode] {
        [WorkspaceNode(id: "w1", label: "demo-app", number: 1, isDirty: false, agentStatus: .working, tabs: tabs, children: children)]
    }

    static func input(_ tree: [WorkspaceNode], pending: [PendingRequest] = [], prompts: [AgentID: String] = [:]) -> LiveActivityInput {
        LiveActivityInput(agents: TreeComposer.agents(in: tree), pending: pending, prompts: prompts)
    }
}

struct LiveActivityAppContentState: Decodable, Equatable {
    struct Pending: Decodable, Equatable {
        enum Kind: String, Decodable, Equatable {
            case permission
            case question
        }

        var requestId: String
        var kind: Kind
        var toolName: String?
        var text: String
        var options: [String]
    }

    var agentId: String
    var status: String
    var title: String
    var workspaceLabel: String
    var since: Date
    var model: String?
    var contextLeftPercent: Int?
    var preview: String?
    var activity: String?
    var prompt: String?
    var pending: Pending?
    var updatedAt: Date

    static func decoding(_ push: AgentActivityPush) throws -> LiveActivityAppContentState {
        let aps = try #require(try PushTestData.jsonObject(try push.payload())["aps"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: try #require(aps["content-state"] as? [String: Any]))
        return try JSONDecoder().decode(LiveActivityAppContentState.self, from: data)
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

    func agents(
        _ agents: [AgentSummary],
        pending: [PendingRequest] = [],
        foreground: Set<DeviceID> = [],
        foregroundAgents: [DeviceID: AgentID] = [:]
    ) async throws {
        await service.apply(LiveActivityInput(agents: agents, pending: pending, foregroundDevices: foreground, foregroundAgents: foregroundAgents))
        try await settle()
    }

    func tree(_ tree: [WorkspaceNode], pending: [PendingRequest] = [], prompts: [AgentID: String] = [:]) async throws {
        await service.apply(LiveActivitySample.input(tree, pending: pending, prompts: prompts))
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

    func storedPushToStart(_ device: DeviceID) async throws -> LiveActivityRegistration? {
        try await devices.devices().first { $0.id == device }?.liveActivity
    }

    func storedCard(_ device: DeviceID) async throws -> LiveActivityRegistration? {
        try await devices.devices().first { $0.id == device }?.feedActivity
    }

    func sent(to token: String) -> [FakeLiveActivitySender.Sent] {
        sender.sent.filter { $0.token == token }
    }
}

extension LiveActivityConfiguration {
    static let withoutHolds = LiveActivityConfiguration(turnDoneCooldown: 0, blockedGrace: 0, blockedAlertWindow: 0)
}

actor FakeAlertHandoff: LiveActivityAlertHandoff {
    struct Handed: Equatable {
        let alerts: [LiveActivityLostAlert]
        let device: DeviceID
    }

    private(set) var handed: [Handed] = []

    func cardLost(_ alerts: [LiveActivityLostAlert], on device: DeviceID) {
        handed.append(Handed(alerts: alerts, device: device))
    }
}

func withLiveActivity(
    configuration: LiveActivityConfiguration = .withoutHolds,
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
