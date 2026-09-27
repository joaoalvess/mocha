import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

struct LiveActivityPendingTests {
    private let sentAt = Date(timeIntervalSince1970: 1_790_000_000.25)

    private func fromHook(_ file: String) throws -> LiveActivityContentState.Pending {
        let (hook, request) = try PendingSample.permissionHook(file)
        let pending = PendingRequest(id: "req-1", agentId: hook.agentId, createdAt: hook.receivedAt, kind: PendingRequestFactory.kind(for: request))
        return LiveActivityContentState.Pending(pending)
    }

    private func pending(_ questions: [PendingQuestion]) -> LiveActivityContentState.Pending {
        LiveActivityContentState.Pending(LiveActivitySample.question("req-1", agent: "w1:p1", questions: questions))
    }

    private func preview(_ text: String) -> LiveActivityContentState.Pending {
        LiveActivityContentState.Pending(
            requestId: "req-1",
            agentId: "w1:p1",
            kind: .question,
            toolName: nil,
            text: PlainText.preview(fromMarkdown: text, limit: 180),
            options: []
        )
    }

    private func state(_ pending: LiveActivityContentState.Pending?) -> LiveActivityContentState {
        LiveActivityContentState(
            working: 1,
            waiting: 1,
            highlight: .init(agentId: "w1:p1", title: "Refatorar o parser", workspaceLabel: "demo-app", status: "blocked", since: sentAt),
            pending: pending,
            updatedAt: sentAt
        )
    }

    private func contentState(of push: LiveActivityPush) throws -> [String: Any] {
        let aps = try #require(try PushTestData.jsonObject(try push.payload())["aps"] as? [String: Any])
        return try #require(aps["content-state"] as? [String: Any])
    }

    private func encodedPending(_ pending: LiveActivityContentState.Pending) throws -> [String: Any] {
        let push = LiveActivityPush(event: .update, contentState: state(pending), timestamp: sentAt, staleDate: sentAt.addingTimeInterval(900))
        return try #require(try contentState(of: push)["pending"] as? [String: Any])
    }

    @Test func aPermissionCarriesTheToolAndTheSummaryWithoutOptions() throws {
        #expect(try fromHook("PermissionRequest.bash.json") == LiveActivityContentState.Pending(
            requestId: "req-1",
            agentId: PendingSample.agent,
            kind: .permission,
            toolName: "Bash",
            text: "touch f.txt",
            options: []
        ))
        let write = try fromHook("PermissionRequest.write.json")
        #expect(write.toolName == "Write")
        #expect(write.text == "notas.md")

        let long = LiveActivityContentState.Pending(
            LiveActivitySample.permission("req-2", agent: "w1:p1", summary: String(repeating: "ç", count: 300))
        )
        #expect(long.text == String(repeating: "ç", count: 120))
        #expect(long.options.isEmpty)
    }

    @Test func aSingleShortQuestionIsInlineWithTheExactTextAndLabels() throws {
        #expect(try fromHook("PermissionRequest.AskUserQuestion.single.json") == LiveActivityContentState.Pending(
            requestId: "req-1",
            agentId: PendingSample.agent,
            kind: .question,
            toolName: nil,
            text: "Qual banco?",
            options: ["Postgres", "SQLite", "MySQL"]
        ))

        let head = "**Qual banco** usar em `prod`?\n\n"
        let padding = 1_000 - head.utf8.count
        let text = head + String(repeating: "é", count: padding / 2) + String(repeating: "a", count: padding % 2)
        let labels = ["  **Sim**, com _migração_  ", String(repeating: "👍🏽", count: 60), "Não", String(repeating: "x", count: 60)]
        #expect(text.utf8.count == 1_000)
        #expect(labels[1].count == 60 && labels[1].utf8.count == 480)

        let inline = pending([LiveActivitySample.singleQuestion(text, labels: labels)])
        #expect(inline.kind == .question)
        #expect(inline.toolName == nil)
        #expect(inline.text == text)
        #expect(inline.options == labels)
        #expect(pending([LiveActivitySample.singleQuestion("Seguir?", labels: ["Sim"])]).options == ["Sim"])
    }

    @Test func otherQuestionsCarryTheMarkdownFreePreviewWithoutOptions() throws {
        let multi = try fromHook("PermissionRequest.AskUserQuestion.multi.json")
        #expect(multi.kind == .question)
        #expect(multi.text == "Qual editor?")
        #expect(multi.options.isEmpty)

        let markdown = "**Qual** `banco` usar?"
        let labels = ["Postgres", "SQLite"]
        #expect(pending([LiveActivitySample.singleQuestion(markdown, labels: labels, multiSelect: true)]) == preview(markdown))
        #expect(preview(markdown).text == "Qual banco usar?")

        let twoQuestions = [
            LiveActivitySample.singleQuestion(markdown, labels: labels),
            LiveActivitySample.singleQuestion("Qual tema?", labels: ["Claro", "Escuro"]),
        ]
        #expect(pending(twoQuestions) == preview(markdown))

        let large = String(repeating: "é", count: 500) + "a"
        #expect(large.utf8.count == 1_001)
        let largePreview = pending([LiveActivitySample.singleQuestion(large, labels: labels)])
        #expect(largePreview == preview(large))
        #expect(largePreview.text.count == 180)

        let longLabel = String(repeating: "x", count: 61)
        #expect(pending([LiveActivitySample.singleQuestion(markdown, labels: ["Sim", longLabel])]) == preview(markdown))
        #expect(pending([LiveActivitySample.singleQuestion(markdown, labels: ["A", "B", "C", "D", "E"])]) == preview(markdown))
        #expect(pending([LiveActivitySample.singleQuestion(markdown, labels: [])]) == preview(markdown))
        #expect(pending([]).text.isEmpty)
    }

    @Test func optionsAreAlwaysEncodedAndAbsentFieldsAreOmitted() throws {
        let permission = try encodedPending(try fromHook("PermissionRequest.bash.json"))
        #expect(permission["options"] as? [String] == [])
        #expect(permission["toolName"] as? String == "Bash")
        #expect(permission["kind"] as? String == "permission")
        #expect(permission["requestId"] as? String == "req-1")
        #expect(permission["agentId"] as? String == PendingSample.agent)

        let multi = try encodedPending(try fromHook("PermissionRequest.AskUserQuestion.multi.json"))
        #expect(multi["options"] as? [String] == [])
        #expect(multi["toolName"] == nil)
        #expect(multi["kind"] as? String == "question")

        let single = try encodedPending(try fromHook("PermissionRequest.AskUserQuestion.single.json"))
        #expect(single["options"] as? [String] == ["Postgres", "SQLite", "MySQL"])

        let withoutPending = LiveActivityPush(event: .update, contentState: state(nil), timestamp: sentAt)
        #expect(try contentState(of: withoutPending)["pending"] == nil)
    }

    @Test func theContentStateDecodesWithTheDefaultDecoderLikeTheApp() throws {
        for file in ["PermissionRequest.bash.json", "PermissionRequest.AskUserQuestion.single.json", "PermissionRequest.AskUserQuestion.multi.json"] {
            let pending = try fromHook(file)
            let push = LiveActivityPush(event: .update, contentState: state(pending), timestamp: sentAt, staleDate: sentAt.addingTimeInterval(900))
            let data = try JSONSerialization.data(withJSONObject: try contentState(of: push))
            let decoded = try JSONDecoder().decode(LiveActivityAppContentState.self, from: data)
            #expect(decoded == LiveActivityAppContentState(
                working: 1,
                waiting: 1,
                highlight: .init(agentId: "w1:p1", title: "Refatorar o parser", workspaceLabel: "demo-app", status: "blocked", since: sentAt),
                pending: .init(
                    requestId: pending.requestId,
                    agentId: pending.agentId,
                    kind: pending.kind == .permission ? .permission : .question,
                    toolName: pending.toolName,
                    text: pending.text,
                    options: pending.options
                ),
                updatedAt: sentAt
            ))
            #expect(try JSONDecoder().decode(LiveActivityContentState.self, from: data) == state(pending))
        }
        let data = try JSONSerialization.data(withJSONObject: try contentState(of: LiveActivityPush(event: .update, contentState: state(nil), timestamp: sentAt)))
        #expect(try JSONDecoder().decode(LiveActivityAppContentState.self, from: data).pending == nil)
    }

    @Test func anInlineUpdateInTheWorstCaseFitsInFourKilobytes() throws {
        let text = String(repeating: "\"", count: 1_000)
        let labels = Array(repeating: String(repeating: "😀", count: 60), count: 4)
        let request = LiveActivitySample.question(
            UUID().uuidString.lowercased(),
            agent: "w9999:p9999",
            questions: [LiveActivitySample.singleQuestion(text, labels: labels)]
        )
        let pending = LiveActivityContentState.Pending(request)
        #expect(pending.text == text)
        #expect(pending.options == labels)
        let state = LiveActivityContentState(
            working: 99,
            waiting: 99,
            highlight: .init(
                agentId: "w9999:p9999",
                title: String(repeating: "😀", count: 60),
                workspaceLabel: String(repeating: "😀", count: 60),
                status: "blocked",
                since: sentAt
            ),
            pending: pending,
            updatedAt: sentAt
        )
        let update = LiveActivityPush(event: .update, contentState: state, timestamp: sentAt, staleDate: sentAt.addingTimeInterval(900))
        #expect(try update.payload().count <= ApnsRequest.maxPayloadBytes)
        let start = LiveActivityPush(event: .start(alert: .init(title: "Mocha", body: "99 trabalhando · 99 esperando você")), contentState: state, timestamp: sentAt)
        #expect(try start.payload().count <= ApnsRequest.maxPayloadBytes)
    }

    @Test func anInlineQuestionOverTheEncodedBudgetFallsBackToThePreview() throws {
        let wideLabels = Array(repeating: String(repeating: "👍🏽", count: 60), count: 4)
        let wide = pending([LiveActivitySample.singleQuestion(String(repeating: "\"", count: 1_000), labels: wideLabels)])
        #expect(wide == preview(String(repeating: "\"", count: 1_000)))

        let control = String(repeating: "\u{1}", count: 1_000)
        let escaped = pending([LiveActivitySample.singleQuestion(control, labels: ["Sim", "Não"])])
        #expect(escaped.options.isEmpty)
        #expect(escaped.fitsEncodedBudget)
    }
}
