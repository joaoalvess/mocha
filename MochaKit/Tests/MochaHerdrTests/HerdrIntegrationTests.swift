import Foundation
import Testing
@testable import MochaHerdr

@Suite(.tags(.integration), .enabled(if: HerdrTestEnvironment.integrationEnabled), .timeLimit(.minutes(1)))
struct HerdrIntegrationTests {
    @Test func readsTheRealHerdrWithoutSendingInput() async throws {
        let client = HerdrClient(configuration: HerdrClientConfiguration(socketPath: HerdrSocketPath.resolve()))
        let pong = try await client.ping()
        #expect(pong.protocolVersion == HerdrProtocol.supportedVersion)
        let snapshot = try await client.sessionSnapshot()
        #expect(!snapshot.workspaces.isEmpty)
        let paneIds = Set(snapshot.panes.map(\.paneId))
        let tabIds = Set(snapshot.tabs.map(\.tabId))
        #expect(snapshot.panes.allSatisfy { tabIds.contains($0.tabId) })
        let agents = try await client.agentList()
        #expect(Set(agents.map(\.paneId)).isSubset(of: paneIds))
        let subscription = try await client.subscribe(HerdrSubscription.globalLifecycle)
        subscription.cancel()
    }
}
