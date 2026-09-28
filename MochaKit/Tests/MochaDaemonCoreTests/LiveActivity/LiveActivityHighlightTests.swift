import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityHighlightTests {
    private static let bash = ToolActivity(toolName: "Bash", summary: "npm run build", status: .running)

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func agent(
        _ id: AgentID = "w1:p1",
        _ status: AgentStatus = .working,
        model: String? = "claude-opus-4-1",
        contextLeftPercent: Int? = 42,
        preview: String? = "**Pronto**: rodei os `testes`.",
        tool: ToolActivity? = bash
    ) -> AgentSummary {
        var agent = LiveActivitySample.agent(id, status)
        agent.model = model
        agent.contextLeftPercent = contextLeftPercent
        agent.preview = preview.map { MessagePreview(author: .assistant, text: $0) }
        agent.activity = tool
        return agent
    }

    private func tab(_ title: String, _ agents: [AgentSummary], id: TabID = "w1:t1") -> TabNode {
        TabNode(id: id, title: title, agents: agents)
    }

    private func snapshots(_ input: LiveActivityInput, at date: Date = Sample.start) -> [AgentID: AgentActivitySnapshot] {
        var tracker = AgentActivityTracker()
        return tracker.snapshots(of: input, at: date, titleLimit: LiveActivityConfiguration().titleLimit)
    }

    private func highlight(
        _ tree: [WorkspaceNode],
        pending: [PendingRequest] = [],
        prompts: [AgentID: String] = ["w1:p1": "Roda os testes"],
        of agentId: AgentID = "w1:p1"
    ) -> LiveActivityContentState.Highlight? {
        snapshots(LiveActivitySample.input(tree, pending: pending, prompts: prompts))[agentId]?.agent
    }

    private func encodedHighlight(_ highlight: LiveActivityContentState.Highlight) throws -> [String: Any] {
        try PushTestData.jsonObject(try ApnsPayloadEncoding.encoder.encode(highlight))
    }

    @Test func theHighlightIsFilledFromTheAgentAndItsPrompt() throws {
        #expect(highlight(LiveActivitySample.tree([tab("parser", [agent()])])) == LiveActivityContentState.Highlight(
            agentId: "w1:p1",
            title: "Refatorar o parser",
            workspaceLabel: "demo-app",
            status: "working",
            since: Sample.start,
            model: "claude-opus-4-1",
            contextLeftPercent: 42,
            preview: "Pronto: rodei os testes.",
            activity: "Bash: npm run build",
            prompt: "Roda os testes"
        ))
        let tree = LiveActivitySample.tree([tab("parser", [agent(), agent("w1:p2")])])
        #expect(highlight(tree, prompts: ["w1:p2": "Outro pedido"], of: "w1:p2")?.prompt == "Outro pedido")
        #expect(highlight(tree, prompts: ["w1:p2": "Outro pedido"])?.prompt == nil)
    }

    @Test func withoutAPromptAPreviewOrMetadataThoseFieldsAreOmitted() throws {
        let bare = agent(model: nil, contextLeftPercent: nil, preview: nil, tool: nil)
        let expected = LiveActivityContentState.Highlight(
            agentId: "w1:p1",
            title: "Refatorar o parser",
            workspaceLabel: "demo-app",
            status: "working",
            since: Sample.start
        )
        #expect(highlight(LiveActivitySample.tree([tab("parser", [bare])]), prompts: [:]) == expected)
        #expect(highlight(LiveActivitySample.tree([tab("parser", [bare])]), prompts: ["w1:p1": " \n "]) == expected)
        #expect(snapshots(LiveActivityInput(agents: [bare]))["w1:p1"]?.agent == expected)
        #expect(highlight(LiveActivitySample.tree([tab("parser", [agent(preview: "  \n\n ")])]))?.preview == nil)
        #expect(highlight(LiveActivitySample.tree([tab("parser", [agent(preview: "```\n```")])]))?.preview == nil)
        #expect(Set(try encodedHighlight(expected).keys) == ["agentId", "title", "workspaceLabel", "status", "since"])
    }

    @Test func onlyAnAssistantMessageBecomesThePreview() {
        #expect(LiveActivityContentState.Highlight.preview(of: MessagePreview(author: .user, text: "Roda os testes")) == nil)
        #expect(LiveActivityContentState.Highlight.preview(of: MessagePreview(author: .assistant, text: "**Rodando** os testes")) == "Rodando os testes")
        #expect(LiveActivityContentState.Highlight.preview(of: nil) == nil)
    }

    @Test func onlyARunningToolBecomesTheActivity() throws {
        func activity(_ tool: ToolActivity?) -> String? {
            highlight(LiveActivitySample.tree([tab("parser", [agent(tool: tool)])]))?.activity
        }
        #expect(activity(Self.bash) == "Bash: npm run build")
        #expect(activity(ToolActivity(toolName: "Bash", summary: "npm run build", status: .succeeded)) == nil)
        #expect(activity(ToolActivity(toolName: "Bash", summary: "npm run build", status: .failed)) == nil)
        #expect(activity(nil) == nil)
        #expect(activity(ToolActivity(toolName: "TodoWrite", summary: " ", status: .running)) == "TodoWrite")

        let long = try #require(activity(ToolActivity(toolName: "Bash", summary: String(repeating: "ç😀", count: 200), status: .running)))
        #expect(long.count == 120)
        #expect(long.hasPrefix("Bash: ç😀"))
    }

    @Test func textsAreCutAtTheirLimits() throws {
        let title = String(repeating: "Título 😀 ", count: 20)
        let preview = String(repeating: "**Olá** ação 👍🏽 ", count: 40)
        let prompt = String(repeating: "Pedido 😀 ", count: 20)
        var titled = agent(preview: preview)
        titled.title = title
        let summary = highlight(LiveActivitySample.tree([tab("parser", [titled])]), prompts: ["w1:p1": prompt])
        #expect(summary?.title == String(title.prefix(60)))
        #expect(summary?.prompt == String(prompt.prefix(120)))
        let cut = try #require(summary?.preview)
        #expect(cut == PlainText.preview(fromMarkdown: preview, limit: 180))
        #expect((170...180).contains(cut.count))
        #expect(cut.hasPrefix("Olá ação 👍🏽 Olá"))
    }

    @Test func aPendingRequestOmitsThePreviewTheActivityAndThePromptOfItsAgentOnly() throws {
        let tree = LiveActivitySample.tree([tab("parser", [agent("w1:p1", .blocked), agent("w1:p2")])])
        let request = LiveActivitySample.permission("req-1", agent: "w1:p1")
        let prompts: [AgentID: String] = ["w1:p1": "Roda os testes", "w1:p2": "Outro pedido"]
        let snapshots = snapshots(LiveActivitySample.input(tree, pending: [request], prompts: prompts))
        let snapshot = try #require(snapshots["w1:p1"])
        let highlight = snapshot.agent
        #expect(snapshot.pending?.requestId == "req-1")
        #expect(highlight.agentId == "w1:p1")
        #expect(highlight.model == "claude-opus-4-1")
        #expect(highlight.contextLeftPercent == 42)
        #expect(highlight.preview == nil)
        #expect(highlight.activity == nil)
        #expect(highlight.prompt == nil)
        let keys = Set(try encodedHighlight(highlight).keys)
        #expect(keys == ["agentId", "title", "workspaceLabel", "status", "since", "model", "contextLeftPercent"])

        #expect(snapshots["w1:p2"]?.pending == nil)
        #expect(snapshots["w1:p2"]?.agent.preview == "Pronto: rodei os testes.")
        #expect(snapshots["w1:p2"]?.agent.activity == "Bash: npm run build")
        #expect(snapshots["w1:p2"]?.agent.prompt == "Outro pedido")

        let withoutPending = self.snapshots(LiveActivitySample.input(tree, prompts: prompts))["w1:p1"]
        #expect(withoutPending?.agent.preview == "Pronto: rodei os testes.")
        #expect(withoutPending?.agent.activity == "Bash: npm run build")
        #expect(withoutPending?.agent.prompt == "Roda os testes")
    }

    @Test func theContentStateDecodesWithTheDefaultDecoderLikeTheApp() throws {
        let tree = LiveActivitySample.tree([tab("parser", [agent()])])
        let snapshot = try #require(snapshots(LiveActivitySample.input(tree, prompts: ["w1:p1": "Roda os testes"]))["w1:p1"])
        let push = snapshot.push({ _ in .update(alert: nil) }, at: at(5), staleDate: at(905))
        #expect(try LiveActivityAppContentState.decoding(push) == LiveActivityAppContentState(
            agentId: "w1:p1",
            status: "working",
            title: "Refatorar o parser",
            workspaceLabel: "demo-app",
            since: Sample.start,
            model: "claude-opus-4-1",
            contextLeftPercent: 42,
            preview: "Pronto: rodei os testes.",
            activity: "Bash: npm run build",
            prompt: "Roda os testes",
            pending: nil,
            updatedAt: at(5)
        ))
        let data = try ApnsPayloadEncoding.encoder.encode(push.contentState.agent)
        #expect(try JSONDecoder().decode(LiveActivityContentState.Highlight.self, from: data) == push.contentState.agent)

        let bare = AgentActivityContentState(
            agent: .init(agentId: "w1:p1", title: "Refatorar o parser", workspaceLabel: "demo-app", status: "working", since: Sample.start),
            pending: nil,
            updatedAt: at(5)
        )
        let decoded = try LiveActivityAppContentState.decoding(AgentActivityPush(agentId: "w1:p1", event: .update(alert: nil), contentState: bare, timestamp: at(5)))
        #expect(decoded == LiveActivityAppContentState(
            agentId: "w1:p1",
            status: "working",
            title: "Refatorar o parser",
            workspaceLabel: "demo-app",
            since: Sample.start,
            updatedAt: at(5)
        ))
    }

    @Test func onlyAStatusOrPendingChangeIsPriorityTen() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            var parser = agent()
            func send(_ agents: [AgentSummary], prompt: String = "Roda os testes", pending: [PendingRequest] = []) async throws {
                try await harness.tree(LiveActivitySample.tree([tab("parser", agents)]), pending: pending, prompts: ["w1:p1": prompt])
                try await harness.advance(10)
            }

            try await send([parser])
            parser.preview = MessagePreview(author: .assistant, text: "Rodando os testes")
            try await send([parser])
            parser.activity = ToolActivity(toolName: "Read", summary: "Package.swift", status: .running)
            try await send([parser])
            parser.contextLeftPercent = 30
            try await send([parser])
            parser.model = "claude-sonnet-4-5"
            try await send([parser])
            try await send([parser], prompt: "Faz dnv")
            parser.activity?.status = .succeeded
            try await send([parser], prompt: "Faz dnv")
            try await send([parser, LiveActivitySample.agent("w1:p2", .idle)], prompt: "Faz dnv")
            try await send([parser, LiveActivitySample.agent("w1:p2", .idle)], prompt: "Faz dnv")
            try await send([parser], prompt: "Faz dnv", pending: [LiveActivitySample.permission("req-1", agent: "w1:p1")])

            let sent = harness.sent(to: LiveActivitySample.updateToken)
            #expect(sent.map(\.priority) == [.high, .low, .low, .low, .low, .low, .low, .high])
            #expect(sent.allSatisfy { $0.push.agentId == "w1:p1" && $0.push.contentState.agent.agentId == "w1:p1" })
            let highlights = sent.map(\.push.contentState.agent)
            #expect(highlights.map(\.preview) == [
                "Pronto: rodei os testes.", "Rodando os testes", "Rodando os testes", "Rodando os testes", "Rodando os testes",
                "Rodando os testes", "Rodando os testes", nil,
            ])
            #expect(highlights.map(\.activity) == [
                "Bash: npm run build", "Bash: npm run build", "Read: Package.swift", "Read: Package.swift", "Read: Package.swift",
                "Read: Package.swift", nil, nil,
            ])
            #expect(highlights.map(\.contextLeftPercent) == [42, 42, 42, 30, 30, 30, 30, 30])
            #expect(highlights.map(\.model) == [
                "claude-opus-4-1", "claude-opus-4-1", "claude-opus-4-1", "claude-opus-4-1", "claude-sonnet-4-5",
                "claude-sonnet-4-5", "claude-sonnet-4-5", "claude-sonnet-4-5",
            ])
            #expect(highlights.map(\.prompt) == [
                "Roda os testes", "Roda os testes", "Roda os testes", "Roda os testes", "Roda os testes", "Faz dnv", "Faz dnv", nil,
            ])
            #expect(sent.last?.push.contentState.pending?.requestId == "req-1")
        }
    }

    @Test func aStreamingPreviewOnlyRidesTheNextAllowedUpdate() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            var parser = agent()
            try await harness.tree(LiveActivitySample.tree([tab("parser", [parser])]))
            for second in 1...25 {
                try await harness.advance(1)
                parser.preview = MessagePreview(author: .assistant, text: "Token \(second)")
                try await harness.tree(LiveActivitySample.tree([tab("parser", [parser])]))
            }
            try await harness.advance(5)
            #expect(harness.sent.map(\.push.timestamp) == [at(0), at(10), at(20), at(30)])
            #expect(harness.sent.map(\.priority) == [.high, .low, .low, .low])
            #expect(harness.sent.map(\.push.contentState.agent.preview) == ["Pronto: rodei os testes.", "Token 9", "Token 19", "Token 25"])

            try await harness.advance(599)
            #expect(harness.sent.count == 4)
            try await harness.advance(1)
            #expect(harness.sent.count == 5)
            #expect(try harness.last().priority == .low)
            #expect(try harness.last().push.timestamp == at(630))
            #expect(try harness.last().push.contentState.agent.preview == "Token 25")
        }
    }

    @Test func thePromptReachesTheServiceThroughTheInput() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            try await harness.tree(LiveActivitySample.tree([tab("parser", [agent()])]), prompts: ["w1:p1": "Roda os testes"])
            let start = try harness.last()
            #expect(start.push.event.name == "start")
            #expect(start.push.contentState.agent.prompt == "Roda os testes")
            #expect(start.push.contentState.agent.activity == "Bash: npm run build")
        }
    }

    @Test(arguments: ["ç", "😀", "👍🏽", "👨‍👩‍👧‍👦", "\"", "\u{1}"])
    func theWorstCasePayloadWithItsAlertFitsInFourKilobytes(unit: String) throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000.123456)
        var worst = agent(
            "w9999:p9999",
            .blocked,
            model: "claude-sonnet-4-5-20250929[1m]",
            contextLeftPercent: 100,
            preview: String(repeating: unit, count: 500),
            tool: ToolActivity(toolName: "mcp__claude_ai_Claude_Docs__batch", summary: String(repeating: unit, count: 300), status: .running)
        )
        worst.title = String(repeating: "😀", count: 200)
        worst.workspaceLabel = String(repeating: "😀", count: 60)
        let tree = LiveActivitySample.tree([tab("parser", [worst])])
        let prompts = ["w9999:p9999": String(repeating: unit, count: 200)]

        func pushes(_ snapshot: AgentActivitySnapshot) -> [AgentActivityPush] {
            let staleDate = now.addingTimeInterval(900)
            return [
                snapshot.push({ .start(alert: $0.startAlert) }, at: now, staleDate: staleDate),
                snapshot.push({ .update(alert: $0.alertContent(.needsInput)) }, at: now, staleDate: staleDate),
                snapshot.push({ .update(alert: $0.alertContent(.turnDone)) }, at: now, staleDate: staleDate),
                snapshot.push({ _ in .update(alert: nil) }, at: now, staleDate: staleDate),
                snapshot.push({ _ in .end(dismissalDate: now) }, at: now, staleDate: nil),
            ]
        }

        let free = try #require(snapshots(LiveActivitySample.input(tree, prompts: prompts), at: now)["w9999:p9999"])
        #expect(free.pending == nil)
        #expect(free.agent.preview?.count == 180)
        #expect(free.agent.activity?.count == 120)
        #expect(free.agent.prompt?.count == 120)
        for push in pushes(free) {
            #expect(try push.payload().count <= ApnsRequest.maxPayloadBytes)
        }

        let requestId = UUID().uuidString.lowercased()
        let text = maximalInlineQuestion(requestId: requestId)
        let request = LiveActivitySample.question(
            requestId,
            agent: "w9999:p9999",
            questions: [LiveActivitySample.singleQuestion(text, labels: Array(repeating: String(repeating: "😀", count: 60), count: 4))]
        )
        let held = try #require(snapshots(LiveActivitySample.input(tree, pending: [request], prompts: prompts), at: now)["w9999:p9999"])
        #expect(held.pending?.options.count == 4)
        #expect(held.agent.preview == nil)
        #expect(held.agent.activity == nil)
        for push in pushes(held) {
            #expect(try push.payload().count <= ApnsRequest.maxPayloadBytes)
            #expect(push.contentState.pending?.requestId == requestId)
        }
    }

    private func maximalInlineQuestion(requestId: RequestID) -> String {
        let labels = Array(repeating: String(repeating: "😀", count: 60), count: 4)
        var best = ""
        var bestSize = 0
        for escaped in stride(from: 0, through: 200, by: 1) {
            let text = String(repeating: "\u{1}", count: escaped) + String(repeating: "\"", count: 1_000 - escaped)
            let pending = LiveActivityContentState.Pending(
                LiveActivitySample.question(requestId, agent: "w9999:p9999", questions: [LiveActivitySample.singleQuestion(text, labels: labels)])
            )
            guard !pending.options.isEmpty, let size = try? ApnsPayloadEncoding.encoder.encode(pending).count else { break }
            if size > bestSize {
                best = text
                bestSize = size
            }
        }
        return best
    }
}
