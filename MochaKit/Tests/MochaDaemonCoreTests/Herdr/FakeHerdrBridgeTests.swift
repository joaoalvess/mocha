import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct FakeHerdrBridgeTests {
    private let tree = [
        WorkspaceNode(
            id: "w1",
            label: "demo-app",
            number: 1,
            isDirty: false,
            agentStatus: .idle,
            tabs: [TabNode(id: "w1:t1", title: "Claude", agents: [AgentSummary(id: "w1:p1", kind: "claude", status: .idle, title: "Claude Code", workspaceLabel: "demo-app")])]
        ),
    ]

    private let agent = HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: "s1")

    @Test func everySubscriberStartsWithTheCurrentState() async throws {
        let bridge = FakeHerdrBridge(tree: tree, agents: [agent])
        var first = bridge.events().makeAsyncIterator()
        var second = bridge.events().makeAsyncIterator()
        #expect(await first.next() == .snapshot(tree: tree, available: true))
        #expect(await second.next() == .snapshot(tree: tree, available: true))
        #expect(bridge.subscriberCount == 2)
        let updated = [WorkspaceNode(id: "w2", label: "notes", number: 2, isDirty: true, agentStatus: .unknown, tabs: [])]
        bridge.setTree(updated)
        #expect(await first.next() == .treeChanged(updated))
        #expect(await second.next() == .treeChanged(updated))
        #expect(await bridge.tree() == updated)
        var late = bridge.events().makeAsyncIterator()
        #expect(await late.next() == .snapshot(tree: updated, available: true))
    }

    @Test func emitsEveryBridgeEvent() async throws {
        let bridge = FakeHerdrBridge(tree: tree)
        var events = bridge.events().makeAsyncIterator()
        _ = await events.next()
        let emitted: [HerdrBridgeEvent] = [
            .agentStatus("w1:p1", .working, title: "Tarefa"),
            .sessionChanged("w1:p1", sessionId: "s2"),
            .treeChanged([]),
            .availability(false),
            .paneMoved(from: "w1:p1", to: "w2:p1"),
        ]
        for event in emitted {
            bridge.emit(event)
        }
        for event in emitted {
            #expect(await events.next() == event)
        }
        #expect(await bridge.tree() == [])
        #expect(await bridge.isAvailable == false)
    }

    @Test func unavailabilityRejectsCommandsButCountsThem() async throws {
        let bridge = FakeHerdrBridge(tree: tree, agents: [agent])
        var events = bridge.events().makeAsyncIterator()
        _ = await events.next()
        bridge.setAvailable(false)
        #expect(await events.next() == .availability(false))
        await expectHerdrBridgeError(.unavailable) { try await bridge.prompt("w1:p1", text: "oi") }
        await expectHerdrBridgeError(.unavailable) { try await bridge.interrupt("w1:p1") }
        #expect(bridge.promptCalls == [FakeHerdrPromptCall(agentId: "w1:p1", text: "oi")])
        #expect(bridge.interruptCalls == ["w1:p1"])
        bridge.setAvailable(true)
        #expect(await events.next() == .availability(true))
        try await bridge.prompt("w1:p1", text: "de novo")
        #expect(bridge.promptCalls.count == 2)
    }

    @Test func configuredErrorsAreThrown() async throws {
        let bridge = FakeHerdrBridge(tree: tree, agents: [agent])
        bridge.setPromptError(.agentBlocked)
        bridge.setInterruptError(.herdr(code: "invalid_key", message: "unsupported key"))
        await expectHerdrBridgeError(.agentBlocked) { try await bridge.prompt("w1:p1", text: "oi") }
        await expectHerdrBridgeError(.herdr(code: "invalid_key", message: "unsupported key")) { try await bridge.interrupt("w1:p1") }
        bridge.setPromptError(.agentNotFound)
        await expectHerdrBridgeError(.agentNotFound) { try await bridge.prompt("w9:p9", text: "oi") }
        bridge.setPromptError(nil)
        try await bridge.prompt("w1:p1", text: "ok")
        #expect(bridge.promptCalls.map(\.text) == ["oi", "oi", "ok"])
    }

    @Test func countsOpenChatsAndResolvesMovedPanes() async throws {
        let bridge = FakeHerdrBridge(tree: tree, agents: [agent])
        var events = bridge.events().makeAsyncIterator()
        _ = await events.next()
        await bridge.setOpenChats(["w1:p1"])
        await bridge.setOpenChats([])
        #expect(bridge.openChatsCalls == [["w1:p1"], []])
        bridge.movePane(from: "w1:p1", to: "w2:p1")
        bridge.movePane(from: "w2:p1", to: "w3:p1")
        #expect(await events.next() == .paneMoved(from: "w1:p1", to: "w2:p1"))
        #expect(await events.next() == .paneMoved(from: "w2:p1", to: "w3:p1"))
        #expect(await bridge.resolve("w1:p1") == "w3:p1")
        #expect(await bridge.resolve("w2:p1") == "w3:p1")
        #expect(await bridge.resolve("w9:p9") == "w9:p9")
        #expect(bridge.resolveCalls == ["w1:p1", "w2:p1", "w9:p9"])
        #expect(await bridge.agent("w3:p1")?.sessionId == "s1")
        #expect(await bridge.agent("w1:p1") == nil)
    }

    @Test func agentsAndServerInfoAreControlledByTheTest() async throws {
        let bridge = FakeHerdrBridge()
        #expect(await bridge.serverInfo == FakeHerdrBridge.defaultServerInfo)
        #expect(await bridge.agent("w1:p1") == nil)
        bridge.setAgent(agent)
        #expect(await bridge.agent("w1:p1") == agent)
        bridge.removeAgent("w1:p1")
        #expect(await bridge.agent("w1:p1") == nil)
        bridge.setServerInfo(HerdrServerInfo(version: "0.10.0", protocolVersion: 23))
        #expect(await bridge.serverInfo?.protocolWarning != nil)
    }

    @Test func slowSubscriberKeepsTheNewestEventsWithoutBlockingOthers() async throws {
        let hub = HerdrBridgeEventHub(tree: [], available: true)
        let slow = hub.subscribe()
        var fast = hub.subscribe().makeAsyncIterator()
        _ = await fast.next()
        let total = HerdrBridgeEventHub.subscriberBufferSize + 44
        for index in 0..<total {
            hub.publish(.sessionChanged("w1:p1", sessionId: "s\(index)"))
            #expect(await fast.next() == .sessionChanged("w1:p1", sessionId: "s\(index)"))
        }
        hub.finish()
        var received: [HerdrBridgeEvent] = []
        for await event in slow {
            received.append(event)
        }
        #expect(received.count == HerdrBridgeEventHub.subscriberBufferSize)
        #expect(received.last == .sessionChanged("w1:p1", sessionId: "s\(total - 1)"))
        #expect(hub.subscriberCount == 0)
    }

    @Test func cancelledSubscriberIsRemoved() async throws {
        let bridge = FakeHerdrBridge()
        let task = Task {
            for await _ in bridge.events() {}
        }
        #expect(await HerdrWait.until { bridge.subscriberCount == 1 })
        task.cancel()
        #expect(await HerdrWait.until { bridge.subscriberCount == 0 })
    }
}
