import Foundation
import MochaTestSupport
import Testing
@testable import MochaHerdr

@Suite(.timeLimit(.minutes(1)))
struct FakeHerdrServerTests {
    private func open(_ server: FakeHerdrServer) async throws -> HerdrSocketConnection {
        try await HerdrSocketConnection.open(path: server.socketPath, queue: DispatchQueue(label: "com.joaoalves.mocha.tests.raw-herdr"))
    }

    private func response(_ line: Data?) throws -> NSDictionary {
        try jsonObject(try #require(line))
    }

    @Test func answersOneRequestPerConnectionAndCloses() async throws {
        try await withFakeHerdr { server, _ in
            let connection = try await open(server)
            try await connection.write(Data((#"{"id":"r1","method":"ping","params":{}}"# + "\n" + #"{"id":"r2","method":"ping","params":{}}"# + "\n").utf8))
            let first = try response(await connection.readLine())
            #expect(first["id"] as? String == "r1")
            #expect((first["result"] as? NSDictionary)?["type"] as? String == "pong")
            #expect(await connection.readLine() == nil)
            #expect(await server.requests.map(\.id) == ["r1"])
            connection.close()
        }
    }

    @Test func invalidRequestsAnswerWithEmptyId() async throws {
        try await withFakeHerdr { server, _ in
            let lines = [
                #"{"id":"r1","method":"ping""#,
                #"{"id":"r2","method":"nope.nope","params":{}}"#,
                #"{"id":"r3","method":"agent.get","params":{}}"#,
                #"{"id":7,"method":"ping","params":{}}"#,
                #"{"id":"r5","method":"ping"}"#,
            ]
            for line in lines {
                let connection = try await open(server)
                try await connection.write(Data((line + "\n").utf8))
                let answer = try response(await connection.readLine())
                #expect(answer["id"] as? String == "", "\(line)")
                #expect((answer["error"] as? NSDictionary)?["code"] as? String == "invalid_request", "\(line)")
                #expect(await connection.readLine() == nil)
                connection.close()
            }
            let echoed = try await open(server)
            try await echoed.write(Data((#"{"id":"e4","method":"pane.get","params":{"pane_id":"w99:p99"}}"# + "\n").utf8))
            let notFound = try response(await echoed.readLine())
            #expect(notFound["id"] as? String == "e4")
            #expect((notFound["error"] as? NSDictionary)?["code"] as? String == "pane_not_found")
            echoed.close()
        }
    }

    @Test func requestWithoutNewlineGetsNoAnswer() async throws {
        try await withFakeHerdr { server, _ in
            let connection = try await open(server)
            try await connection.write(Data(#"{"id":"r1","method":"ping","params":{}}"#.utf8))
            try await Task.sleep(for: .milliseconds(150))
            #expect(await server.requests.isEmpty)
            connection.close()
        }
    }

    @Test func writingAfterTheAckClosesTheSubscription() async throws {
        try await withFakeHerdr { server, _ in
            let connection = try await open(server)
            try await connection.write(Data((#"{"id":"sub1","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.updated"}]}}"# + "\n").utf8))
            let ack = try response(await connection.readLine())
            #expect((ack["result"] as? NSDictionary)?["type"] as? String == "subscription_started")
            #expect(await server.globalSubscriptionCount == 1)
            try await connection.write(Data((#"{"id":"r2","method":"ping","params":{}}"# + "\n").utf8))
            #expect(await connection.readLine() == nil)
            #expect(await server.writesAfterAck == 1)
            #expect(await server.globalSubscriptionCount == 0)
            connection.close()
        }
    }

    @Test func subscriptionItemsAreValidatedLikeTheHerdr() async throws {
        try await withFakeHerdr { server, _ in
            let missingPane = try await open(server)
            try await missingPane.write(Data((#"{"id":"x1","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.agent_status_changed"}]}}"# + "\n").utf8))
            let missing = try response(await missingPane.readLine())
            #expect(missing["id"] as? String == "")
            missingPane.close()
            let unknownPane = try await open(server)
            try await unknownPane.write(
                Data((#"{"id":"x2","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.updated"},{"type":"pane.agent_status_changed","pane_id":"w99:p99"}]}}"# + "\n").utf8)
            )
            let unknown = try response(await unknownPane.readLine())
            #expect(unknown["id"] as? String == "x2:sub:1:probe")
            #expect((unknown["error"] as? NSDictionary)?["code"] as? String == "pane_not_found")
            #expect(await unknownPane.readLine() == nil)
            unknownPane.close()
        }
    }

    @Test func playsTheRecordedStreams() async throws {
        try await withFakeHerdr { server, client in
            await server.movePane(from: "w1A:p2", to: "w1A:p3", tabId: "w1A:t2", workspaceId: "w1A", tabLabel: "start")
            let global = try await client.subscribe(HerdrSubscription.globalLifecycle)
            let first = try await client.subscribe([.agentStatusChanged(paneId: "w1A:p1")])
            let third = try await client.subscribe([.agentStatusChanged(paneId: "w1A:p3")])
            try await server.play(stream: "stream.global.lab-lifecycle.jsonl")
            let lifecycle = try HerdrFixtures.lines("stream.global.lab-lifecycle.jsonl")
            let unsubscribed = ["layout_updated", "workspace_metadata_updated"]
            let expected = lifecycle.filter { line in !unsubscribed.contains { String(decoding: line, as: UTF8.self).contains("\"event\":\"\($0)\"") } }.count - 1
            let globalEvents = try await collect(expected, from: global)
            #expect(globalEvents.count == 75)
            #expect(globalEvents.first == .structural("workspace_created"))
            #expect(globalEvents.last == .structural("workspace_closed"))
            for stream in ["stream.status.turn.jsonl", "stream.status.turn-interrupted.jsonl", "stream.status.turn-with-permission.jsonl", "stream.status.startup-trust-dialog.jsonl"] {
                try await server.play(stream: stream)
            }
            try await server.play(stream: "stream.status.agent-exit.jsonl")
            let firstEvents = try await collect(2 + 2 + 4 + 2, from: first)
            #expect(firstEvents.allSatisfy { if case .agentStatusChanged("w1A:p1", _, _, _) = $0 { true } else { false } })
            let exitEvents = try await collect(3, from: third)
            #expect(exitEvents.last == .agentStatusChanged(paneId: "w1A:p3", workspaceId: "w1A", status: .unknown, agent: nil))
            global.cancel()
            first.cancel()
            third.cancel()
        }
    }
}
