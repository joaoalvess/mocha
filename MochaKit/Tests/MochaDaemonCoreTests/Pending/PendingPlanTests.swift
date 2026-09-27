import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PendingPlanTests {
    static let subagent = "acc551560c5341f92"

    static func body(_ file: String, subagent: String? = nil) throws -> Data {
        var json = try PendingSample.json(file)
        if let subagent {
            json = json.setting("agent_id", to: .string(subagent)).setting("agent_type", to: .string("Explore"))
        }
        return Data(json.compactSerialized().utf8)
    }

    static func send(_ body: Data, to harness: PendingHarness) async throws -> HeldHook {
        let known = Set(await harness.store.requests.map(\.id))
        let server = harness.server
        let request = PendingSample.hookRequest(.permissionRequest, body: body)
        let task = Task { await server.respond(to: request, as: .permissionRequest) }
        let requestId = try await eventually { await harness.store.requests.map(\.id).first { !known.contains($0) } }
        return HeldHook(requestId: requestId, task: task)
    }

    @Test func approvingAPlanEchoesTheInputAndSwitchesToAutoMode() throws {
        let (_, request) = try PendingSample.permissionHook("PermissionRequest.ExitPlanMode.json")
        let kind = PendingRequestFactory.kind(for: request)
        let reply = try PendingHookReply.reply(to: .allow, kind: kind, toolInput: request.toolInput)
        let fixture = try PendingSample.fixture("response.PermissionRequest.ExitPlanMode.allow.json")
        #expect(reply == (try OrderedJSON.parse(fixture)))
        #expect(Data(reply.prettyPrinted().utf8) == PendingSample.withoutTrailingNewline(fixture))
        #expect(reply["hookSpecificOutput"]?["decision"]?["updatedInput"] == request.toolInput)
        #expect(try PendingHookReply.reply(to: .deny(reason: nil), kind: kind, toolInput: request.toolInput) == PendingHookReply.deny(nil))
    }

    @Test func thePlanSummaryIsItsFirstLineWithoutMarkdown() throws {
        let (_, request) = try PendingSample.permissionHook("PermissionRequest.ExitPlanMode.json")
        guard case .permission(let toolName, let summary, _) = PendingRequestFactory.kind(for: request) else {
            throw PendingTestError.notAPermissionRequest
        }
        #expect(toolName == "ExitPlanMode")
        #expect(summary == "Criar o arquivo f.txt")
        #expect(PushAlertText.pendingCategory(request) == PushAlertText.planCategory)
    }

    @Test func thePhoneApprovalReachesTheHeldPlan() async throws {
        try await withPendingStore { harness in
            let plan = try await Self.send(Self.body("PermissionRequest.ExitPlanMode.json"), to: harness)

            try await harness.store.respond(to: plan.requestId, with: .allow)

            #expect(try OrderedJSON.parse(await plan.response().body) == (try PendingSample.json("response.PermissionRequest.ExitPlanMode.allow.json")))
            #expect(try await harness.resolution(of: plan.requestId).reason == .phone)
        }
    }

    @Test func aSubagentRequestKeepsTheMainPlanOpen() async throws {
        try await withPendingStore { harness in
            let plan = try await Self.send(Self.body("PermissionRequest.ExitPlanMode.json"), to: harness)

            let subagent = try await Self.send(Self.body("PermissionRequest.bash.json", subagent: Self.subagent), to: harness)

            #expect(Set(await harness.store.requests.map(\.id)) == [plan.requestId, subagent.requestId])
            try await harness.store.respond(to: plan.requestId, with: .allow)
            #expect(try OrderedJSON.parse(await plan.response().body) == (try PendingSample.json("response.PermissionRequest.ExitPlanMode.allow.json")))
            #expect(await harness.store.contains(subagent.requestId))
            try await harness.closeAndWait(subagent)
        }
    }

    @Test func aRequestReplacesOnlyTheOneOfTheSameSubagent() async throws {
        try await withPendingStore { harness in
            let main = try await Self.send(Self.body("PermissionRequest.write.json"), to: harness)
            let first = try await Self.send(Self.body("PermissionRequest.bash.json", subagent: Self.subagent), to: harness)
            let other = try await Self.send(Self.body("PermissionRequest.bash.json", subagent: "a0123456789abcdef"), to: harness)

            let second = try await Self.send(Self.body("PermissionRequest.write.json", subagent: Self.subagent), to: harness)

            #expect(String(decoding: await first.response().body, as: UTF8.self) == "{}")
            #expect(try await harness.resolution(of: first.requestId).reason == .sessionHook(.permissionRequest))
            #expect(Set(await harness.store.requests.map(\.id)) == [main.requestId, other.requestId, second.requestId])

            let replacement = try await Self.send(Self.body("PermissionRequest.ExitPlanMode.json"), to: harness)

            #expect(try await harness.resolution(of: main.requestId).reason == .sessionHook(.permissionRequest))
            #expect(Set(await harness.store.requests.map(\.id)) == [other.requestId, second.requestId, replacement.requestId])
            for held in [other, second, replacement] {
                try await harness.closeAndWait(held)
            }
        }
    }

    @Test func thePaneLeavingBlockedStillEndsTheMainPlan() async throws {
        try await withPendingStore { harness in
            let plan = try await Self.send(Self.body("PermissionRequest.ExitPlanMode.json"), to: harness)

            try await harness.emitStatus(.blocked)
            try await harness.emitStatus(.working)

            #expect(try await harness.resolution(of: plan.requestId).reason == .terminalStatus)
            #expect(String(decoding: await plan.response().body, as: UTF8.self) == "{}")
        }
    }
}
