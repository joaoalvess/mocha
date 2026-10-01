import Foundation
import MochaProtocol

enum DemoCodex {
    static let workspaceId: WorkspaceID = "w3"
    static let workspaceLabel = "receitas-api"
    static let branch = "development"
    static let planAgentId: AgentID = "w3:p5"
    static let workingAgentId: AgentID = "w3:p6"
    static let planThreadId = "7d3c2b1a-4e5f-4a6b-9c8d-0e1f2a3b4c5d"
    static let workingThreadId = "8e4d3c2b-5f6a-4b7c-8d9e-1f2a3b4c5d6e"
    static let workingChildThreadId = "9f5e4d3c-6a7b-4c8d-9e0f-2a3b4c5d6e7f"
    static let archivedThreadId = "a06f5e4d-7b8c-4d9e-8f0a-3b4c5d6e7f80"
    static let archivedChildThreadId = "b1706f5e-8c9d-4e0f-9a1b-4c5d6e7f8091"
    static let planItemId = "codex-plan-text"
    static let tabTitle = "Codex"
    static let newThreadTitle = "Codex CLI"
    static let compactedNotice = "Contexto compactado"
    static let modelsOnlyForCodexMessage = "Lista de modelos só para Codex"
    static let modeUnavailableMessage = "Modo indisponível no Codex"
    static let commandUnavailableMessage = "Comando indisponível no Codex"
    static let compactCommand = "/compact"
    static let modes: Set<PermissionModeTarget> = [.default, .plan]

    static let models = [
        ModelOption(
            id: "gpt-6.1-sol",
            displayName: "GPT-6.1-Sol",
            isDefault: true,
            defaultEffort: "low",
            efforts: [
                EffortOption(level: "low", description: "Rápido, com pouco raciocínio"),
                EffortOption(level: "medium"),
                EffortOption(level: "high"),
                EffortOption(level: "xhigh"),
                EffortOption(level: "max"),
                EffortOption(level: "ultra"),
            ]
        ),
        ModelOption(
            id: "gpt-6-luna",
            displayName: "GPT-6-Luna",
            isDefault: false,
            defaultEffort: "medium",
            efforts: ["low", "medium", "high", "xhigh", "max"].map { EffortOption(level: $0) }
        ),
    ]

    static func model(withId id: String) -> ModelOption? {
        models.first { $0.id == id }
    }

    static func paneId(replacing agentId: AgentID, in workspaces: [WorkspaceNode], taken: Set<AgentID>) -> AgentID? {
        guard let separator = agentId.range(of: ":p", options: .backwards) else { return nil }
        let workspaceId = String(agentId[..<separator.lowerBound])
        let panePrefix = String(agentId[..<separator.upperBound])
        let tabPrefix = workspaceId + ":t"
        let tabNumbers = workspaces.workspace(withId: workspaceId)?.tabs.compactMap { number(in: $0.id, after: tabPrefix) } ?? []
        let paneNumbers = taken.compactMap { number(in: $0, after: panePrefix) }
        return panePrefix + String(((tabNumbers + paneNumbers).max() ?? 0) + 1)
    }

    private static func number(in id: String, after prefix: String) -> Int? {
        guard id.hasPrefix(prefix) else { return nil }
        return Int(id.dropFirst(prefix.count))
    }

    static func usage() -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            plan: "Pro",
            account: "d•••@e•••.com",
            windows: [
                UsageWindow(kind: .fiveHour, usedPercent: 27, resetsAt: at(2 * 3_600 + 20 * 60), windowDurationMins: 300),
                UsageWindow(kind: .weekly, usedPercent: 43, resetsAt: at(3 * 86_400 + 4 * 3_600), windowDurationMins: 10_080),
            ],
            fetchedAt: at(-90)
        )
    }

    static func tabs() -> [TabNode] {
        [
            TabNode(id: "w3:t5", title: tabTitle, agents: [planAgent()]),
            TabNode(id: "w3:t6", title: tabTitle, agents: [workingAgent()]),
        ]
    }

    static func chats() -> [DemoChat] {
        [
            DemoChat(agentId: planAgentId, meta: meta(of: planAgent()), items: planItems()),
            DemoChat(agentId: workingAgentId, meta: meta(of: workingAgent()), items: workingItems()),
        ]
    }

    static func archivedChat() -> DemoSessionChat {
        let items = archivedItems()
        let session = ArchivedSession(
            id: archivedThreadId,
            provider: .codex,
            agentId: planAgentId,
            title: "Contrato da API de receitas",
            workspaceLabel: workspaceLabel,
            model: "gpt-6.1-sol",
            branch: branch,
            preview: MessagePreview(author: .user, text: "documenta o contrato de /receitas em OpenAPI"),
            contextLeftPercent: 64,
            reason: .ended,
            endedAt: at(-2 * 86_400 + 3_600),
            sessionStartedAt: items.first?.at,
            lastActivityAt: items.last?.at
        )
        return DemoSessionChat(session: session, items: items)
    }

    static func subagents() -> [DemoSubagent] {
        [workingChild(), archivedChild()]
    }

    static func meta(of agent: AgentSummary) -> ChatMeta {
        ChatMeta(
            title: agent.title,
            workspaceLabel: agent.workspaceLabel,
            model: agent.model,
            branch: agent.branch,
            status: agent.status,
            permissionMode: agent.permissionMode,
            effort: agent.effort
        )
    }

    private static func planAgent() -> AgentSummary {
        var agent = AgentSummary(
            id: planAgentId,
            kind: AgentProvider.codex.rawValue,
            status: .idle,
            title: "Cache de /receitas",
            workspaceLabel: workspaceLabel,
            model: "gpt-6-luna",
            branch: branch,
            sessionId: planThreadId,
            contextLeftPercent: 76,
            controlAvailable: true,
            permissionMode: PermissionModeTarget.plan.rawValue,
            effort: "high",
            contextUsedTokens: 61_400
        )
        agent.refreshHomeFields(from: planItems())
        return agent
    }

    private static func workingAgent() -> AgentSummary {
        var agent = AgentSummary(
            id: workingAgentId,
            kind: AgentProvider.codex.rawValue,
            status: .working,
            title: "Migrations de índice",
            workspaceLabel: workspaceLabel,
            model: "gpt-6.1-sol",
            branch: branch,
            sessionId: workingThreadId,
            contextLeftPercent: 91,
            runningSubagents: 1,
            controlAvailable: true,
            permissionMode: PermissionModeTarget.default.rawValue,
            effort: "low",
            contextUsedTokens: 21_800
        )
        agent.refreshHomeFields(from: workingItems())
        return agent
    }

    private static func planItems() -> [ChatItem] {
        [
            ChatItem(
                id: "codex-plan-prompt",
                at: at(-420),
                kind: .userPrompt(text: "planeja o cache de /receitas com Redis antes de mexer no código", imageCount: 0)
            ),
            ChatItem(
                id: "codex-plan-search",
                at: at(-400),
                kind: .toolCall(ToolCall(
                    toolUseId: "codex-plan-search",
                    name: "Shell",
                    summary: "rg -n \"func (h *Handler) List\" internal/",
                    inputJSON: #"{"command":"rg -n \"func (h *Handler) List\" internal/"}"#,
                    status: .succeeded,
                    resultPreview: "internal/http/receitas.go:42"
                ))
            ),
            ChatItem(id: planItemId, at: at(-305), kind: .plan(markdown: planMarkdown)),
            ChatItem(id: "codex-plan-footer", at: at(-300), kind: .turnFooter(durationMs: 120_000)),
        ]
    }

    private static let planMarkdown = """
    ## Plano: cache de /receitas

    1. Criar `internal/cache` com um cliente Redis e TTL de 5 minutos.
    2. Envolver `Handler.List` com a leitura do cache pela chave `receitas:<cursor>`.
    3. Invalidar as chaves em `Create`, `Update` e `Delete`.
    4. Cobrir com testes usando o Redis em memória.

    Nada foi alterado ainda.
    """

    private static func workingItems() -> [ChatItem] {
        let child = workingChild()
        return [
            ChatItem(
                id: "codex-work-prompt",
                at: at(-150),
                kind: .userPrompt(text: "revisa as migrations de índice e roda os testes do repositório", imageCount: 0)
            ),
            ChatItem(id: child.cardId, at: child.startedAt, kind: .subagent(child.call)),
            ChatItem(
                id: "codex-work-test",
                at: at(-60),
                kind: .toolCall(ToolCall(
                    toolUseId: "codex-work-test",
                    name: "Shell",
                    summary: "go test ./internal/store/...",
                    inputJSON: #"{"command":"go test ./internal/store/..."}"#,
                    status: .running
                ))
            ),
        ]
    }

    private static func archivedItems() -> [ChatItem] {
        let child = archivedChild()
        let start = -2 * 86_400.0
        return [
            ChatItem(
                id: "codex-archived-prompt",
                at: at(start),
                kind: .userPrompt(text: "documenta o contrato de /receitas em OpenAPI", imageCount: 0)
            ),
            ChatItem(id: child.cardId, at: child.startedAt, kind: .subagent(child.call)),
            ChatItem(
                id: "codex-archived-answer",
                at: at(start + 120),
                kind: .assistantText(markdown: "Escrevi `docs/openapi.yaml` com `GET /receitas`, a paginação por cursor e os erros 400 e 404.")
            ),
            ChatItem(id: "codex-archived-footer", at: at(start + 125), kind: .turnFooter(durationMs: 125_000)),
        ]
    }

    private static func workingChild() -> DemoSubagent {
        DemoSubagent(
            sessionId: workingThreadId,
            agentId: workingChildThreadId,
            toolUseId: "codex-spawn-migrations",
            agentType: "explorer",
            description: "Revisar migrations de índice",
            status: .running,
            toolUses: 2,
            startedAt: at(-140),
            items: [
                ChatItem(
                    id: "codex-child-prompt",
                    at: at(-140),
                    kind: .userPrompt(text: "Revise as migrations de índice em db/migrations e aponte riscos.", imageCount: 0)
                ),
                ChatItem(
                    id: "codex-child-list",
                    at: at(-130),
                    kind: .toolCall(ToolCall(
                        toolUseId: "codex-child-list",
                        name: "Shell",
                        summary: "ls db/migrations",
                        inputJSON: #"{"command":"ls db/migrations"}"#,
                        status: .succeeded,
                        resultPreview: "0007_receitas_cursor.sql"
                    ))
                ),
                ChatItem(
                    id: "codex-child-grep",
                    at: at(-100),
                    kind: .toolCall(ToolCall(
                        toolUseId: "codex-child-grep",
                        name: "Shell",
                        summary: "rg -n \"CREATE INDEX\" db/migrations",
                        inputJSON: #"{"command":"rg -n \"CREATE INDEX\" db/migrations"}"#,
                        status: .running
                    ))
                ),
            ]
        )
    }

    private static func archivedChild() -> DemoSubagent {
        let start = -2 * 86_400.0 + 10
        return DemoSubagent(
            sessionId: archivedThreadId,
            agentId: archivedChildThreadId,
            toolUseId: "codex-spawn-fields",
            agentType: "explorer",
            description: "Levantar os campos de /receitas",
            status: .completed,
            toolUses: 1,
            startedAt: at(start),
            durationMs: 45_000,
            items: [
                ChatItem(
                    id: "codex-fields-prompt",
                    at: at(start),
                    kind: .userPrompt(text: "Liste os campos de /receitas a partir dos handlers.", imageCount: 0)
                ),
                ChatItem(
                    id: "codex-fields-read",
                    at: at(start + 15),
                    kind: .toolCall(ToolCall(
                        toolUseId: "codex-fields-read",
                        name: "Shell",
                        summary: "sed -n 1,80p internal/http/receitas.go",
                        inputJSON: #"{"command":"sed -n 1,80p internal/http/receitas.go"}"#,
                        status: .succeeded,
                        resultPreview: "type Receita struct {"
                    ))
                ),
                ChatItem(
                    id: "codex-fields-answer",
                    at: at(start + 45),
                    kind: .assistantText(markdown: "Campos: `id`, `titulo`, `ingredientes`, `tempoPreparo` e `criadaEm`.")
                ),
            ]
        )
    }

    private static func at(_ offset: TimeInterval) -> Date {
        DemoDataset.anchor.addingTimeInterval(offset)
    }
}
