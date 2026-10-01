import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexServiceRequestTests {
    private func withBoundService(_ body: (CodexServiceHarness, CodexService, CodexUpdateRecorder) async throws -> Void) async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            let updates = await harness.start(service)
            try await harness.bind(service)
            do {
                try await body(harness, service, updates)
            } catch {
                await service.stop()
                throw error
            }
            await service.stop()
        }
    }

    private func fresh(_ name: String) throws -> OrderedJSON {
        let params = try CodexSample.params(name)
        guard params["startedAtMs"] != nil else { return params }
        return CodexSample.setting(params, ["startedAtMs": CodexSample.nowMs()])
    }

    @Test func aCommandApprovalBecomesABashPermissionWrittenFromCommandActions() async throws {
        try await withBoundService { harness, _, updates in
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 0, params: try fresh("command-execution-request-approval.json"))

            let request = try await eventually { updates.pending.first }
            #expect(request.id == "codex:\(CodexSample.threadId):exec-e1e5e97c-f52c-4f69-beaf-f75504587451")
            guard case .permission(let toolName, let summary, let inputJSON) = request.kind else {
                Issue.record("expected a permission")
                return
            }
            #expect(toolName == "Bash")
            #expect(summary == "printf 'x' > /Users/dev/Developer/mocha-lab/S9/fora.txt")
            let input = try OrderedJSON.parse(Data(inputJSON.utf8))
            #expect(input["command"] == .string(summary))
            #expect(input["cwd"] == .string(CodexSample.cwd))
            #expect(input["reason"]?.stringValue?.hasPrefix("Você autoriza") == true)
            _ = try await eventually { updates.alerts.first }
            #expect(updates.alerts == [.needsInput(request)])
        }
    }

    @Test func aFileChangeApprovalListsThePathsOfItsItem() async throws {
        try await withBoundService { harness, _, updates in
            await harness.server.notify("item/started", params: try CodexSample.params("item-started.file-change.json"))
            await harness.server.serverRequest("item/fileChange/requestApproval", id: 3, params: try fresh("file-change-request-approval.json"))

            let request = try await eventually { updates.pending.first }
            #expect(request.id == "codex:\(CodexSample.threadId):call_patch_7f3a")
            guard case .permission(let toolName, let summary, let inputJSON) = request.kind else {
                Issue.record("expected a permission")
                return
            }
            #expect(toolName == "Edit")
            #expect(summary == "README.md, notas.txt")
            let input = try OrderedJSON.parse(Data(inputJSON.utf8))
            #expect(input["file_path"] == .string(CodexSample.cwd + "/README.md"))
            #expect(input["paths"]?.arrayValue?.count == 2)
        }
    }

    @Test func aFileChangeWithoutItsItemFallsBackToTheReason() async throws {
        try await withBoundService { harness, _, updates in
            await harness.server.serverRequest("item/fileChange/requestApproval", id: 3, params: try fresh("file-change-request-approval.json"))

            let request = try await eventually { updates.pending.first }
            guard case .permission(_, let summary, _) = request.kind else {
                Issue.record("expected a permission")
                return
            }
            #expect(summary == "Editar README.md e criar notas.txt")
        }
    }

    @Test func aUserInputRequestBecomesAQuestionWithItsId() async throws {
        try await withBoundService { harness, _, updates in
            await harness.server.serverRequest("item/tool/requestUserInput", id: 4, params: try fresh("tool-request-user-input.json"))

            let request = try await eventually { updates.pending.first }
            #expect(request.id == "codex:\(CodexSample.threadId):call_input_91c2")
            #expect(request.kind == .question(questions: [
                PendingQuestion(
                    header: "Banco",
                    question: "Qual banco de dados usar?",
                    options: [PendingOption(label: "SQLite", description: "Arquivo local"), PendingOption(label: "Postgres", description: "Servidor")],
                    multiSelect: false,
                    id: "banco"
                ),
            ]))
            _ = try await eventually { updates.panes[CodexSample.pane]?.status == .blocked ? true : nil }
        }
    }

    @Test(arguments: [
        ("item/permissions/requestApproval", "permissions-request-approval.json", "Acesso à rede para baixar dependências"),
        ("mcpServer/elicitation/request", "mcp-server-elicitation-request.json", "github: Qual repositório abrir?"),
    ])
    func unanswerableRequestsAlertWithoutActionsAndBlockThePane(method: String, file: String, body: String) async throws {
        try await withBoundService { harness, _, updates in
            let params = try fresh(file)
            await harness.server.serverRequest(method, id: 5, params: params)

            let alert = try await eventually { updates.alerts.first }
            #expect(alert == .needsInputWithoutActions(CodexSample.pane, body: body))
            _ = try await eventually { updates.panes[CodexSample.pane]?.status == .blocked ? true : nil }
            #expect(updates.pending.isEmpty)

            await harness.server.serverRequest(method, id: 9, params: params)
            await harness.server.notify("serverRequest/resolved", params: .object([
                .init("threadId", .string(CodexSample.threadId)), .init("requestId", .number("9")),
            ]))
            _ = try await eventually { updates.panes[CodexSample.pane]?.status == .idle ? true : nil }
            #expect(updates.alerts.count == 1)
            #expect(await harness.server.clientResponses.isEmpty)
        }
    }

    @Test(arguments: ["item/tool/call", "account/chatgptAuthTokens/refresh", "attestation/generate", "applyPatchApproval", "execCommandApproval"])
    func otherServerRequestsAreLeftToTheTerminal(method: String) async throws {
        try await withBoundService { harness, _, updates in
            await harness.server.serverRequest(method, id: 6, params: .object([
                .init("threadId", .string(CodexSample.threadId)), .init("itemId", .string("call_x")), .init("callId", .string("call_x")),
            ]))
            try await Task.sleep(for: .milliseconds(150))
            #expect(updates.pending.isEmpty)
            #expect(updates.alerts.isEmpty)
            #expect(await harness.server.clientResponses.isEmpty)
        }
    }

    @Test func waitingWithoutARequestAlertsBlockedOnceUntilItClears() async throws {
        try await withBoundService { harness, _, updates in
            let waiting = try CodexSample.params("thread-status-waiting-on-user-input.json")
            await harness.server.notify("thread/status/changed", params: waiting)
            await harness.server.notify("thread/status/changed", params: try CodexSample.params("thread-status-waiting-on-approval.json"))

            _ = try await eventually { updates.panes[CodexSample.pane]?.status == .blocked ? true : nil }
            #expect(updates.alerts == [.blocked(CodexSample.pane)])

            await harness.server.notify("thread/status/changed", params: .object([
                .init("threadId", .string(CodexSample.threadId)), .init("status", .object([.init("type", .string("idle"))])),
            ]))
            _ = try await eventually { updates.panes[CodexSample.pane]?.status == .idle ? true : nil }
            await harness.server.notify("thread/status/changed", params: waiting)
            _ = try await eventually { updates.alerts.count == 2 ? true : nil }
        }
    }

    @Test func theAppServerResolvingARequestRemovesIt() async throws {
        try await withBoundService { harness, _, updates in
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 0, params: try fresh("command-execution-request-approval.json"))
            _ = try await eventually { updates.pending.count == 1 ? true : nil }

            await harness.server.notify("serverRequest/resolved", params: try CodexSample.params("server-request-resolved.json"))
            _ = try await eventually { updates.pending.isEmpty ? true : nil }
            _ = try await eventually { updates.panes[CodexSample.pane]?.status == .idle ? true : nil }
        }
    }

    @Test(arguments: [
        (PendingResponse.allow, "accept", PendingOutcome.allowed),
        (PendingResponse.deny(reason: "não"), "decline", PendingOutcome.denied),
    ])
    func permissionsAnswerWithTheDecisionAndRecordTheOutcome(response: PendingResponse, decision: String, outcome: PendingOutcome) async throws {
        try await withBoundService { harness, service, updates in
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 0, params: try fresh("command-execution-request-approval.json"))
            let request = try await eventually { updates.pending.first }

            try await service.respond(to: request.id, with: response)
            let answer = try await eventually { await harness.server.clientResponses.first }
            #expect(answer.result == .object([.init("decision", .string(decision))]))
            _ = try await eventually { updates.decisions[CodexSample.pane] == PendingDecision(requestId: request.id, outcome: outcome) ? true : nil }
            #expect(updates.pending.isEmpty)
            await #expect(throws: CodexServiceError.requestNotFound) {
                try await service.respond(to: request.id, with: response)
            }
        }
    }

    @Test(arguments: ["banco", "Qual banco de dados usar?"])
    func aQuestionIsAnsweredByIdOrByItsText(key: String) async throws {
        try await withBoundService { harness, service, updates in
            await harness.server.serverRequest("item/tool/requestUserInput", id: 4, params: try fresh("tool-request-user-input.json"))
            let request = try await eventually { updates.pending.first }

            try await service.respond(to: request.id, with: .answers([key: ["SQLite"]]))
            let answer = try await eventually { await harness.server.clientResponses.first }
            #expect(answer.id == .number("4"))
            #expect(answer.result == .object([
                .init("answers", .object([.init("banco", .object([.init("answers", .array([.string("SQLite")]))]))])),
            ]))
            _ = try await eventually { updates.decisions[CodexSample.pane]?.outcome == .answered ? true : nil }
        }
    }

    @Test func invalidAnswersKeepTheRequest() async throws {
        try await withBoundService { harness, service, updates in
            await harness.server.serverRequest("item/tool/requestUserInput", id: 4, params: try fresh("tool-request-user-input.json"))
            let question = try await eventually { updates.pending.first }
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 5, params: try fresh("command-execution-request-approval.json"))
            _ = try await eventually { updates.pending.count == 2 ? true : nil }
            let permission = try #require(updates.pending.first { $0.id != question.id })

            for response in [PendingResponse.allow, .answers(["Outra pergunta?": ["SQLite"]]), .answers([:])] {
                await #expect(throws: CodexServiceError.invalidResponse) {
                    try await service.respond(to: question.id, with: response)
                }
            }
            await #expect(throws: CodexServiceError.invalidResponse) {
                try await service.respond(to: permission.id, with: .answers(["x": ["y"]]))
            }
            await #expect(throws: CodexServiceError.requestNotFound) {
                try await service.respond(to: "codex:\(CodexSample.threadId):nada", with: .allow)
            }
            #expect(updates.pending.count == 2)
            #expect(await harness.server.clientResponses.isEmpty)
        }
    }

    @Test func answersAreTranslatedFromTextsToIds() {
        let questions = [
            PendingQuestion(header: "A", question: "Primeira?", options: [], multiSelect: false, id: "a"),
            PendingQuestion(header: "B", question: "Segunda?", options: [], multiSelect: false, id: "b"),
        ]
        #expect(CodexService.answersById(["Primeira?": ["1"], "b": ["2"]], questions: questions) == ["a": ["1"], "b": ["2"]])
        #expect(CodexService.answersById(["Primeira?": ["1"]], questions: questions) == nil)
        #expect(CodexService.answersById(["Primeira?": ["1"], "a": ["1"], "b": ["2"]], questions: questions) == nil)
        let repeated = questions.map { PendingQuestion(header: $0.header, question: "Igual?", options: [], multiSelect: false, id: $0.id) }
        #expect(CodexService.answersById(["Igual?": ["1"], "b": ["2"]], questions: repeated) == nil)
    }
}
