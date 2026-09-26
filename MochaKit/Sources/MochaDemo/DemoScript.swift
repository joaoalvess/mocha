import Foundation
import MochaProtocol

enum DemoScriptEvent: Sendable, Equatable {
    case addWorktree
    case startTurn
    case appendThinking
    case appendPlan
    case appendRead
    case appendRunningTool
    case finishRunningTool
    case renameChat
    case finishTurn
    case switchSession
    case moveAgent
    case dropConnection
    case retryConnection
    case completeReconnection
}

struct DemoScriptStep: Sendable {
    var delay: Duration
    var event: DemoScriptEvent
}

enum DemoScript {
    static let steps = [
        DemoScriptStep(delay: .seconds(3), event: .addWorktree),
        DemoScriptStep(delay: .seconds(2), event: .startTurn),
        DemoScriptStep(delay: .seconds(1), event: .appendThinking),
        DemoScriptStep(delay: .seconds(1), event: .appendPlan),
        DemoScriptStep(delay: .seconds(1), event: .appendRead),
        DemoScriptStep(delay: .seconds(1), event: .appendRunningTool),
        DemoScriptStep(delay: .seconds(2), event: .finishRunningTool),
        DemoScriptStep(delay: .seconds(1), event: .renameChat),
        DemoScriptStep(delay: .seconds(1), event: .finishTurn),
        DemoScriptStep(delay: .seconds(4), event: .switchSession),
        DemoScriptStep(delay: .seconds(4), event: .moveAgent),
        DemoScriptStep(delay: .seconds(4), event: .dropConnection),
        DemoScriptStep(delay: .seconds(2), event: .retryConnection),
        DemoScriptStep(delay: .milliseconds(500), event: .completeReconnection),
    ]

    static let worktreeParentId: WorkspaceID = "w2"
    static let worktreeId: WorkspaceID = "w6"
    static let worktreeAgentId: AgentID = "w6:p1"
    static let worktreeSessionId = "5c1e9a7b-4d2f-4b8a-9e3c-6f0a2d8b1c47"
    static let clearedSessionId = "e7a3c9f1-5b2d-4f8e-a1c6-3d9b0f7e2a54"
    static let turnAgentId: AgentID = "w1:p1"
    static let renamedTitle = "Testes do cálculo de frete"
    static let runningToolItemId = "script-turn-bash"
    static let movedAgentId: AgentID = "w5:p1"
    static let movedAgentNewId: AgentID = "w5:p2"

    private static let worktreeLabel = "feed-rss"
    private static let worktreeBranch = "feat/feed-rss"
    private static let worktreeTitle = "Feed RSS paginado"
    private static let model = "claude-opus-5-5"

    static func worktree(at date: Date) -> WorkspaceNode {
        WorkspaceNode(
            id: worktreeId,
            label: worktreeLabel,
            number: 6,
            repoName: "site-pessoal",
            branch: worktreeBranch,
            isDirty: false,
            agentStatus: .idle,
            tabs: [
                TabNode(
                    id: "w6:t1",
                    title: "Claude",
                    agents: [
                        AgentSummary(
                            id: worktreeAgentId,
                            kind: "claude",
                            status: .idle,
                            title: worktreeTitle,
                            workspaceLabel: worktreeLabel,
                            model: model,
                            branch: worktreeBranch,
                            sessionId: worktreeSessionId,
                            lastActivityAt: date
                        ),
                    ]
                ),
            ]
        )
    }

    static func worktreeChat(at date: Date) -> DemoChat {
        DemoChat(
            agentId: worktreeAgentId,
            meta: ChatMeta(
                title: worktreeTitle,
                workspaceLabel: worktreeLabel,
                model: model,
                branch: worktreeBranch,
                status: .idle,
                permissionMode: "default"
            ),
            items: [
                ChatItem(
                    id: "script-worktree-prompt",
                    at: date.addingTimeInterval(-40),
                    kind: .userPrompt(text: "Continua o feed RSS neste worktree, começando pela paginação.", imageCount: 0)
                ),
                ChatItem(
                    id: "script-worktree-status",
                    at: date.addingTimeInterval(-32),
                    kind: .toolCall(
                        ToolCall(
                            toolUseId: "toolu_script_worktree",
                            name: "Bash",
                            summary: "git status --short",
                            inputJSON: #"{"command":"git status --short"}"#,
                            status: .succeeded
                        )
                    )
                ),
                ChatItem(
                    id: "script-worktree-answer",
                    at: date.addingTimeInterval(-2),
                    kind: .assistantText(markdown: "Worktree `feat/feed-rss` limpo. Vou começar por `src/feed/rss.ts`.")
                ),
                ChatItem(id: "script-worktree-footer", at: date, kind: .turnFooter(durationMs: 40_000)),
            ]
        )
    }

    static func clearCommand(at date: Date) -> ChatItem {
        ChatItem(id: "script-clear", at: date, kind: .slashCommand(name: "/clear", args: "", output: nil))
    }

    static func prompt(at date: Date) -> ChatItem {
        ChatItem(
            id: "script-turn-prompt",
            at: date,
            kind: .userPrompt(text: "Adiciona testes para o cálculo de frete e roda a suíte inteira.", imageCount: 0)
        )
    }

    static func thinking(at date: Date) -> ChatItem {
        ChatItem(id: "script-turn-thinking", at: date, kind: .thinking(text: nil))
    }

    static func plan(at date: Date) -> ChatItem {
        ChatItem(
            id: "script-turn-plan",
            at: date,
            kind: .assistantText(markdown: "Vou ler o `FreightCalculator.swift` e os testes que já existem antes de mexer.")
        )
    }

    static func read(at date: Date) -> ChatItem {
        ChatItem(
            id: "script-turn-read",
            at: date,
            kind: .toolCall(
                ToolCall(
                    toolUseId: "toolu_script_read",
                    name: "Read",
                    summary: "Sources/Checkout/FreightCalculator.swift",
                    inputJSON: #"{"file_path":"/Users/dev/projects/demo-app/Sources/Checkout/FreightCalculator.swift"}"#,
                    status: .succeeded,
                    resultPreview: "142 linhas"
                )
            )
        )
    }

    static func testRun(at date: Date, status: ToolStatus) -> ChatItem {
        ChatItem(
            id: runningToolItemId,
            at: date,
            kind: .toolCall(
                ToolCall(
                    toolUseId: "toolu_script_bash",
                    name: "Bash",
                    summary: "scripts/test.sh",
                    inputJSON: #"{"command":"scripts/test.sh","description":"Roda a suíte de testes"}"#,
                    status: status,
                    resultPreview: status == .running ? nil : "Executed 48 tests, with 0 failures (0 unexpected) in 3.412 seconds"
                )
            )
        )
    }

    static func finalAnswer(at date: Date, durationMs: Int) -> [ChatItem] {
        [
            ChatItem(
                id: "script-turn-answer",
                at: date,
                kind: .assistantText(
                    markdown: """
                    Pronto. Adicionei **6 testes** em `FreightCalculatorTests.swift`:

                    - frete grátis acima de R$ 200;
                    - CEP inválido;
                    - peso acima do limite da transportadora.

                    A suíte inteira passou (48 testes).
                    """
                )
            ),
            ChatItem(id: "script-turn-footer", at: date, kind: .turnFooter(durationMs: durationMs)),
        ]
    }
}
