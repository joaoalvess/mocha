import Foundation
import MochaTestSupport
import Testing
@testable import MochaHerdr

extension Tag {
    @Tag static var integration: Self
}

enum HerdrTestEnvironment {
    static var integrationEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCHA_INTEGRATION"] == "1"
    }
}

struct HerdrTestTimeout: Error {}

func withFakeHerdr<Result>(
    snapshot: String = "session.snapshot.two-agents-one-tab.response.json",
    requestTimeout: Duration = .seconds(2),
    promptTimeout: Duration = .seconds(2),
    _ body: (FakeHerdrServer, HerdrClient) async throws -> Result
) async throws -> Result {
    let server = FakeHerdrServer()
    try await server.loadSnapshot(fixture: snapshot)
    try await server.start()
    let client = HerdrClient(
        configuration: HerdrClientConfiguration(
            socketPath: server.socketPath,
            requestTimeout: requestTimeout,
            promptTimeout: promptTimeout
        )
    )
    do {
        let result = try await body(server, client)
        await server.stop()
        return result
    } catch {
        await server.stop()
        throw error
    }
}

func collect(_ count: Int, from subscription: HerdrEventSubscription, timeout: Duration = .seconds(5)) async throws -> [HerdrEvent] {
    try await withThrowingTaskGroup(of: [HerdrEvent].self) { group in
        group.addTask {
            var events: [HerdrEvent] = []
            for await event in subscription.events {
                events.append(event)
                if events.count == count {
                    break
                }
            }
            return events
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw HerdrTestTimeout()
        }
        defer { group.cancelAll() }
        return try await group.next() ?? []
    }
}

func expectServerError(_ code: HerdrErrorCode, _ operation: () async throws -> Void) async -> HerdrServerError? {
    do {
        try await operation()
        Issue.record("expected Herdr error \(code.rawValue)")
        return nil
    } catch HerdrClientError.server(let error) {
        #expect(error.code == code)
        return error
    } catch {
        Issue.record("unexpected error \(error)")
        return nil
    }
}

func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}
