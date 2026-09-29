import Foundation
import Synchronization
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct ModelSwitchHookTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    final class Now: Sendable {
        private let value = Mutex(ModelSwitchHookTests.start)

        func callAsFunction() -> Date {
            value.withLock { $0 }
        }

        func advance(by seconds: TimeInterval) {
            value.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
    }

    static func request(_ file: String, pane: String = HookServerTests.pane) throws -> HttpRequest {
        var headers = HttpHeaders()
        for (name, value) in HookServerTests.headers(pane: pane) {
            headers.add(name, value)
        }
        return HttpRequest(method: .post, path: HookEventName.preModelSwitch.path, headers: headers, body: try Fixtures.data("hooks/\(file)"))
    }

    static func body(_ response: HttpResponse) throws -> OrderedJSON {
        try OrderedJSON.parse(response.body)
    }

    @Test func stopCarriesEffortAndPermissionModeAndHaikuHasNoEffort() throws {
        guard case .stop(let sonnet) = try HookEvent.decode(.stop, from: Fixtures.data("hooks/Stop.effort.json")),
              case .stop(let haiku) = try HookEvent.decode(.stop, from: Fixtures.data("hooks/Stop.json")),
              case .userPromptSubmit(let prompt) = try HookEvent.decode(.userPromptSubmit, from: Fixtures.data("hooks/UserPromptSubmit.json"))
        else {
            Issue.record("Stop ou UserPromptSubmit não decodificou")
            return
        }
        #expect(sonnet.context.effort == "medium")
        #expect(sonnet.context.permissionMode == "default")
        #expect(haiku.context.effort == nil)
        #expect(prompt.context.permissionMode == "default")
        #expect(prompt.context.effort == nil)
    }

    @Test func modelSwitchHooksDecodeTheS8Samples() throws {
        guard case .preModelSwitch(let pre) = try HookEvent.decode(.preModelSwitch, from: Fixtures.data("hooks/PreModelSwitch.command.json")),
              case .postModelSwitch(let picker) = try HookEvent.decode(.postModelSwitch, from: Fixtures.data("hooks/PostModelSwitch.picker.json")),
              case .postModelSwitch(let automatic) = try HookEvent.decode(.postModelSwitch, from: Fixtures.data("hooks/PostModelSwitch.auto.json"))
        else {
            Issue.record("os hooks de troca de modelo não decodificaram")
            return
        }
        #expect(pre == ModelSwitchHook(
            context: pre.context,
            fromModel: "claude-haiku-4-5-20251001",
            toModel: "claude-sonnet-5-5",
            requestedModel: "sonnet",
            source: "command"
        ))
        #expect(pre.context.permissionMode == nil)
        #expect(picker.toModel == "claude-sonnet-5-5")
        #expect(picker.source == "picker")
        #expect(!picker.isAutomatic)
        #expect(automatic.isAutomatic)
        #expect(automatic.requestedModel == nil)
        #expect(automatic.context.promptId == nil)
        #expect(throws: HookPayloadError.missingField("to_model")) {
            try HookEvent.decode(.postModelSwitch, from: HookFixtures.body("PostModelSwitch.picker.json", removing: ["to_model"]))
        }
    }

    @Test func preModelSwitchAllowsOnlyWithAPendingSetModelOfThePaneForFiveSeconds() async throws {
        let now = Now()
        let gate = ModelSwitchGate(now: { now() })
        let events = HookEventHub()
        let received = events.events()
        let server = HookServer(
            secrets: HookSecretVerifier(secret: HookServerTests.secret),
            events: events,
            modelSwitches: gate,
            now: { now() }
        )
        let empty = try OrderedJSON.parse(Fixtures.data("hooks/response.empty.json"))
        let allow = try OrderedJSON.parse(Fixtures.data("hooks/response.PreModelSwitch.allow.json"))
        let request = try Self.request("PreModelSwitch.command.json")

        #expect(try Self.body(await server.respond(to: request, as: .preModelSwitch)) == empty)

        await gate.begin("w9Z:p9")
        #expect(try Self.body(await server.respond(to: request, as: .preModelSwitch)) == empty)

        await gate.begin(HookServerTests.pane)
        let allowed = await server.respond(to: request, as: .preModelSwitch)
        #expect(allowed.status == .ok)
        #expect(allowed.headers["Content-Type"] == "application/json")
        #expect(try Self.body(allowed) == allow)

        now.advance(by: 5)
        #expect(try Self.body(await server.respond(to: request, as: .preModelSwitch)) == allow)
        now.advance(by: 0.5)
        #expect(try Self.body(await server.respond(to: request, as: .preModelSwitch)) == empty)

        await gate.begin(HookServerTests.pane)
        await gate.end(HookServerTests.pane)
        #expect(try Self.body(await server.respond(to: request, as: .preModelSwitch)) == empty)

        var iterator = received.makeAsyncIterator()
        for _ in 0..<6 {
            #expect(await iterator.next()?.event.name == .preModelSwitch)
        }
    }

    @Test func preModelSwitchWithoutTheSecretIsRejected() async throws {
        let gate = ModelSwitchGate()
        await gate.begin(HookServerTests.pane)
        let server = HookServer(secrets: HookSecretVerifier(secret: "outro"), events: HookEventHub(), modelSwitches: gate)

        #expect(await server.respond(to: try Self.request("PreModelSwitch.command.json"), as: .preModelSwitch).status == .unauthorized)
    }

    @Test func installEntriesMakePreModelSwitchSynchronousAndPostModelSwitchAsync() {
        let pre = ClaudeHookEntries.hook(for: .preModelSwitch, port: 47420, secret: "test-secret")
        let post = ClaudeHookEntries.hook(for: .postModelSwitch, port: 47420, secret: "test-secret")

        #expect(pre["async"] == nil)
        #expect(pre["timeout"] == .number("5"))
        #expect(pre["command"]?.stringValue?.contains("-o /dev/null") == false)
        #expect(pre["command"]?.stringValue?.hasSuffix("http://127.0.0.1:47420/hooks/PreModelSwitch || echo '{}'") == true)
        #expect(post["async"] == .bool(true))
        #expect(post["command"]?.stringValue?.contains("-o /dev/null") == true)
        #expect(post["command"]?.stringValue?.hasSuffix("/hooks/PostModelSwitch || true") == true)
    }
}
