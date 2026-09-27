import Foundation
import MochaProtocol

struct DemoSubagent: Sendable, Equatable {
    var sessionId: String
    var agentId: String
    var parentAgentId: String?
    var toolUseId: String?
    var agentType: String
    var description: String
    var status: SubagentStatus
    var toolUses: Int
    var startedAt: Date
    var durationMs: Int?
    var failureReason: String?
    var items: [ChatItem]

    var isWorkflowAgent: Bool {
        toolUseId == nil
    }

    var cardId: String {
        DemoSubagents.cardPrefix + agentId
    }

    var endedAt: Date? {
        durationMs.map { startedAt.addingTimeInterval(TimeInterval($0) / 1_000) }
    }

    var activity: ToolActivity? {
        guard status == .running else { return nil }
        guard let toolCall = items.lazy.reversed().compactMap(\.toolCallValue).first(where: { $0.status == .running }) else {
            return nil
        }
        return ToolActivity(toolName: toolCall.name, summary: toolCall.summary, status: toolCall.status)
    }

    var call: SubagentCall {
        SubagentCall(
            toolUseId: toolUseId ?? "",
            agentId: agentId,
            agentType: agentType,
            description: description,
            status: status,
            activity: activity,
            toolUses: toolUses,
            startedAt: startedAt,
            durationMs: durationMs,
            failureReason: failureReason
        )
    }

    var summary: SubagentSummary {
        SubagentSummary(
            agentId: agentId,
            parentAgentId: parentAgentId,
            agentType: agentType,
            description: description,
            status: status,
            toolUses: toolUses,
            startedAt: startedAt,
            durationMs: durationMs
        )
    }

    var workflowAgent: WorkflowAgent {
        WorkflowAgent(agentId: agentId, label: description, status: status, activity: activity, durationMs: durationMs)
    }

    func chatInfo(parentTitle: String) -> SubagentChatInfo {
        SubagentChatInfo(
            parentTitle: parentTitle,
            agentType: agentType,
            status: status,
            startedAt: startedAt,
            durationMs: durationMs,
            toolUses: toolUses,
            failureReason: failureReason
        )
    }

    func finished(at date: Date, answer: String, result: String) -> (subagent: DemoSubagent, updated: [ChatItem], appended: [ChatItem]) {
        var subagent = self
        var updated: [ChatItem] = []
        for index in subagent.items.indices {
            guard case .toolCall(var toolCall) = subagent.items[index].kind, toolCall.status == .running else { continue }
            toolCall.status = .succeeded
            toolCall.resultPreview = result
            subagent.items[index].kind = .toolCall(toolCall)
            updated.append(subagent.items[index])
        }
        let appended = [ChatItem(id: "\(agentId)-answer", at: date, kind: .assistantText(markdown: answer))]
        subagent.items += appended
        subagent.status = .completed
        subagent.durationMs = DemoSubagents.milliseconds(from: startedAt, to: date)
        return (subagent, updated, appended)
    }

    func shifted(by interval: TimeInterval) -> DemoSubagent {
        var subagent = self
        subagent.startedAt = startedAt.addingTimeInterval(interval)
        subagent.items = items.map { $0.shifted(by: interval) }
        return subagent
    }

    static func listOrder(_ lhs: DemoSubagent, _ rhs: DemoSubagent) -> Bool {
        switch (lhs.status == .running, rhs.status == .running) {
        case (true, false): true
        case (false, true): false
        case (true, true): lhs.startedAt > rhs.startedAt
        case (false, false): (lhs.endedAt ?? lhs.startedAt) > (rhs.endedAt ?? rhs.startedAt)
        }
    }
}

extension ChatItemKind {
    var cardId: String? {
        switch self {
        case .subagent(let call): call.agentId.map { DemoSubagents.cardPrefix + $0 }
        case .workflow(let call): call.runId.map { DemoSubagents.cardPrefix + $0 }
        default: nil
        }
    }
}

extension [DemoSubagent] {
    func subagent(sessionId: String, agentId: String) -> DemoSubagent? {
        first { $0.sessionId == sessionId && $0.agentId == agentId }
    }

    func runningSubagents(inSession sessionId: String) -> Int? {
        let session = filter { $0.sessionId == sessionId }
        guard !session.isEmpty else { return nil }
        return session.count { $0.status == .running }
    }

    func summaries(inSession sessionId: String) -> [SubagentSummary] {
        let listed = filter { $0.sessionId == sessionId && !$0.isWorkflowAgent }.sorted(by: DemoSubagent.listOrder)
        let listedIds = Set(listed.map(\.agentId))
        func branch(_ subagent: DemoSubagent) -> [DemoSubagent] {
            [subagent] + listed.filter { $0.parentAgentId == subagent.agentId }.flatMap(branch)
        }
        let roots = listed.filter { subagent in
            guard let parentAgentId = subagent.parentAgentId else { return true }
            return !listedIds.contains(parentAgentId)
        }
        return roots.flatMap(branch).map(\.summary)
    }
}

enum DemoSubagents {
    static let cardPrefix = "card-"
    static let workflowAgentType = "workflow-subagent"
    static let receitasSessionId = DemoLongChat.sessionId
    static let demoAppAgentId: AgentID = "w1:p1"
    static let demoAppSessionId = "6a1f4c2e-9b3d-4e7a-8c5f-0d2b1a9e8f7c"
    static let loginAgentId: AgentID = "w5:p1"
    static let loginSessionId = "b3e8d1f0-2c4a-4b6e-9f1d-7a5c3e2b0d9f"
    static let loadTestAgentId = "a0123456789abcdef"
    static let auditRunId = "wf_0a1b2c3d-4e5"
    static let loginAuditRunId = "wf_7c8d9e0f-1a2"
    static let auditName = "auditoria-a11y"
    static let loadTestResult = "checks: 100% · http_req_duration p(95)=142ms · 0 erros"
    static let loadTestAnswer = """
    Teste de carga de `GET /receitas` com 50 usuários por 2 min:

    | Rodada | p95 | Erros |
    |---|---:|---:|
    | `main` (OFFSET) | 1,82 s | 0 |
    | `feat/cursor-receitas` | 142 ms | 0 |

    Com o cursor, o p95 da página 200 caiu 92% e a taxa de erro continuou zero.
    """

    static var all: [DemoSubagent] {
        [loadTest, loadScript, offsetMap, fixtures, indexReview, loginExplore] + auditAgents + loginAuditAgents
    }

    static let loadScript: DemoSubagent = {
        let agentId = "a76543210fedcba98"
        var transcript = DemoTranscript(agentId: agentId)
        transcript.add(-225, .task(text: "Ache o script do k6 que carrega GET /receitas e diga como rodar."))
        transcript.tool(-221, "Glob", "load/**/*.js", ["pattern": "load/**/*.js"], result: "load/list-recipes.js\nload/create-recipe.js")
        transcript.tool(-217, "Grep", "receitas", ["pattern": "receitas", "path": "load"], result: "load/list-recipes.js:12")
        transcript.tool(-212, "Read", "load/list-recipes.js", ["file_path": root + "load/list-recipes.js"], result: "38 linhas")
        transcript.tool(-206, "Read", "load/README.md", ["file_path": root + "load/README.md"], result: "21 linhas")
        transcript.tool(-199, "Bash", "k6 version", ["command": "k6 version"], result: "k6 v0.54.0 (go1.23.2, darwin/arm64)")
        transcript.add(-185, .assistantText(markdown: "O script é `load/list-recipes.js`. Rode com `k6 run --vus 50 --duration 2m load/list-recipes.js`; ele lê o `BASE_URL` do ambiente (padrão `http://localhost:8080`)."))
        return DemoSubagent(
            sessionId: receitasSessionId,
            agentId: agentId,
            parentAgentId: loadTestAgentId,
            toolUseId: "toolu_demo_" + agentId,
            agentType: "Explore",
            description: "Achar o script de carga",
            status: .completed,
            toolUses: 5,
            startedAt: date(-225),
            durationMs: 41_000,
            items: transcript.items
        )
    }()

    static let loadTest: DemoSubagent = {
        let k6 = "k6 run --vus 50 --duration 2m load/list-recipes.js"
        var transcript = DemoTranscript(agentId: loadTestAgentId)
        transcript.add(-231, .task(text: "Rode o teste de carga de GET /receitas com o k6 (load/list-recipes.js): 50 usuários por 2 min, primeiro na main e depois em feat/cursor-receitas. Compare o p95 e a taxa de erro das duas rodadas."))
        transcript.add(-228, .thinking(text: nil))
        transcript.add(-226, .subagent(loadScript.call))
        transcript.tool(-182, "Read", "load/list-recipes.js", ["file_path": root + "load/list-recipes.js"], result: "38 linhas")
        transcript.tool(-176, "Bash", k6, ["command": k6], status: .failed, result: "ERRO: dial tcp 127.0.0.1:8080: connect: connection refused")
        transcript.tool(-170, "Bash", k6, ["command": k6], status: .failed, result: "ERRO: dial tcp 127.0.0.1:8080: connect: connection refused")
        transcript.tool(-160, "Bash", k6, ["command": k6], result: "checks: 100% · http_req_duration p(95)=1.82s · 0 erros")
        transcript.add(-100, .assistantText(markdown: "Na `main`, com OFFSET: p95 de 1,82 s na página 200 e nenhum erro. Agora com o cursor:"))
        let build = "git switch feat/cursor-receitas && go build ./..."
        transcript.tool(-95, "Bash", build, ["command": build], result: "Switched to branch 'feat/cursor-receitas'")
        transcript.tool(-90, "Bash", build, ["command": build], result: "Already on 'feat/cursor-receitas'")
        transcript.tool(-80, "Edit", "load/list-recipes.js", ["file_path": root + "load/list-recipes.js", "old_string": "offset += 20", "new_string": "cursor = body.next_cursor"], result: "Arquivo atualizado.")
        transcript.add(-70, .assistantText(markdown: "O script agora segue o `next_cursor` da resposta em vez de somar o offset."))
        transcript.tool(-65, "Bash", k6, ["command": k6], status: .running)
        return DemoSubagent(
            sessionId: receitasSessionId,
            agentId: loadTestAgentId,
            toolUseId: "toolu_demo_" + loadTestAgentId,
            agentType: "general-purpose",
            description: "Teste de carga /receitas",
            status: .running,
            toolUses: 9,
            startedAt: date(-231),
            items: transcript.items
        )
    }()

    static let offsetMap: DemoSubagent = {
        let agentId = "a3c5e7a9b1d3f5e7c"
        let search = #"rg -n "OFFSET" internal/"#
        var transcript = DemoTranscript(agentId: agentId)
        transcript.add(-232, .task(text: "Procure em internal/ os endpoints que ainda paginam com LIMIT/OFFSET. Liste rota, função e arquivo; não edite nada."))
        for offset: TimeInterval in [-228, -223, -218, -213, -208, -204] {
            transcript.tool(offset, "Bash", search, ["command": search], result: "internal/ingredients/store.go:61:  LIMIT $1 OFFSET $2")
        }
        for offset: TimeInterval in [-200, -195, -190, -185, -180, -175, -170, -165, -160] {
            transcript.tool(offset, "Read", "internal/ingredients/store.go", ["file_path": root + "internal/ingredients/store.go"], result: "118 linhas")
        }
        transcript.add(-150, .assistantText(markdown: "Três arquivos usam `OFFSET`. Confiro as rotas no router:"))
        transcript.tool(-145, "Grep", #"r.Get\("#, ["pattern": #"r.Get\("#, "path": "internal/api"], result: "internal/api/router.go:24\ninternal/api/router.go:31")
        transcript.tool(-140, "Grep", #"r.Get\("#, ["pattern": #"r.Get\("#, "path": "internal/api"], result: "internal/api/router.go:38")
        transcript.tool(-130, "Read", "internal/api/router.go", ["file_path": root + "internal/api/router.go"], result: "64 linhas")
        transcript.add(-99, .assistantText(markdown: """
        ### Endpoints com OFFSET

        - `/ingredientes`: `ListIngredients` em `internal/ingredients/store.go`
        - `/autores`: `ListAuthors` em `internal/authors/store.go`

        O `/receitas` já usa cursor. Os dois ordenam por `created_at`, sem desempate por id.
        """))
        return DemoSubagent(
            sessionId: receitasSessionId,
            agentId: agentId,
            toolUseId: "toolu_demo_" + agentId,
            agentType: "Explore",
            description: "Mapear uso de OFFSET",
            status: .completed,
            toolUses: 18,
            startedAt: date(-232),
            durationMs: 134_000,
            items: transcript.items
        )
    }()

    static let fixtures: DemoSubagent = {
        let agentId = "a4d6f8b0c2e4a6b8d"
        let steps: [(String, String, KeyValuePairs<String, String>, String)] = [
            ("Read", "migrations/0003_recipes.sql", ["file_path": root + "migrations/0003_recipes.sql"], "42 linhas"),
            ("Write", "load/fixtures/gen.go", ["file_path": root + "load/fixtures/gen.go", "content": "package main\n"], "Arquivo criado."),
            ("Bash", "go run ./load/fixtures", ["command": "go run ./load/fixtures"], "40000 receitas geradas"),
            ("Bash", "wc -l load/fixtures/receitas.sql", ["command": "wc -l load/fixtures/receitas.sql"], "40012 load/fixtures/receitas.sql"),
        ]
        var transcript = DemoTranscript(agentId: agentId)
        transcript.add(-857, .task(text: "Gere fixtures para o teste de carga de /receitas: 40 mil receitas com datas de criação repetidas, em load/fixtures/receitas.sql, e um script que carrega o arquivo no banco local."))
        for index in 0..<22 {
            let step = steps[index % steps.count]
            transcript.tool(-850 + Double(index) * 9.5, step.0, step.1, step.2, result: step.3)
        }
        transcript.add(-638, .assistantText(markdown: "Criei `load/fixtures/receitas.sql` com 40 mil receitas (200 datas repetidas, para testar o desempate) e `load/fixtures/load.sh`, que recria a tabela e importa o arquivo em 6 s."))
        return DemoSubagent(
            sessionId: receitasSessionId,
            agentId: agentId,
            toolUseId: "toolu_demo_" + agentId,
            agentType: "general-purpose",
            description: "Gerar fixtures de carga",
            status: .completed,
            toolUses: 22,
            startedAt: date(-857),
            durationMs: 220_000,
            items: transcript.items
        )
    }()

    static let indexReview: DemoSubagent = {
        let agentId = "a89abcdef01234567"
        let psql = #"psql receitas -c '\d recipes'"#
        var transcript = DemoTranscript(agentId: agentId)
        transcript.add(-859, .task(text: "Revise o índice de receitas para a paginação por cursor: confira se (created_at, id) está coberto e proponha a migração, sem editar nada."))
        transcript.add(-855, .thinking(text: nil))
        transcript.tool(-851, "Read", "migrations/0003_recipes.sql", ["file_path": root + "migrations/0003_recipes.sql"], result: "42 linhas")
        transcript.tool(-845, "Grep", "CREATE INDEX", ["pattern": "CREATE INDEX", "path": "migrations"], result: "migrations/0003_recipes.sql:30")
        transcript.tool(-838, "Bash", psql, ["command": psql], result: "Indexes:\n    \"recipes_pkey\" PRIMARY KEY, btree (id)\n    \"recipes_created_at_idx\" btree (created_at)")
        return DemoSubagent(
            sessionId: receitasSessionId,
            agentId: agentId,
            toolUseId: "toolu_demo_" + agentId,
            agentType: "Plan",
            description: "Revisar o índice de receitas",
            status: .failed,
            toolUses: 3,
            startedAt: date(-859),
            durationMs: 48_000,
            failureReason: "Agent terminated early due to an API error: 529 Overloaded",
            items: transcript.items
        )
    }()

    static let loginExplore: DemoSubagent = {
        let agentId = "a6e8a0c2e4f6b8d0a"
        var transcript = DemoTranscript(agentId: agentId)
        transcript.add(-179, .task(text: "Mapeie como o AuthService guarda a sessão hoje: onde lê e grava o token e se já usa o Keychain. Não edite nada."))
        transcript.tool(-175, "Grep", "SecItem", ["pattern": "SecItem", "path": "Sources"], result: "Nenhum resultado.")
        transcript.tool(-168, "Grep", "UserDefaults", ["pattern": "UserDefaults", "path": "Sources"], result: "Sources/DemoApp/Auth/AuthService.swift:18")
        transcript.tool(-160, "Read", "Auth/AuthService.swift", ["file_path": appRoot + "Auth/AuthService.swift"], result: "96 linhas")
        transcript.tool(-150, "Read", "Auth/SessionStore.swift", ["file_path": appRoot + "Auth/SessionStore.swift"], result: "41 linhas")
        transcript.tool(-138, "Read", "App/DemoApp.swift", ["file_path": appRoot + "App/DemoApp.swift"], result: "33 linhas")
        transcript.tool(-126, "Grep", "token", ["pattern": "token", "path": "Sources/DemoApp/Auth"], result: "Sources/DemoApp/Auth/SessionStore.swift:12\nSources/DemoApp/Auth/AuthService.swift:44")
        return DemoSubagent(
            sessionId: loginSessionId,
            agentId: agentId,
            toolUseId: "toolu_demo_" + agentId,
            agentType: "Explore",
            description: "Mapear a sessão no AuthService",
            status: .stopped,
            toolUses: 6,
            startedAt: date(-179),
            durationMs: 62_000,
            items: transcript.items
        )
    }()

    static let auditAgents: [DemoSubagent] = [
        mapScreensAgent("a1111111111111111", session: demoAppSessionId, startedAt: -372, toolUses: 14, durationMs: 95_000),
        auditAgent("a2222222222222222", session: demoAppSessionId, label: "Ajustes", file: "SettingsView.swift", startedAt: -270, toolUses: 21, running: ("Edit", "SettingsView.swift")),
        auditAgent("a3333333333333333", session: demoAppSessionId, label: "Perfil", file: "ProfileView.swift", startedAt: -268, toolUses: 9, running: ("Read", "ProfileView.swift")),
        auditAgent("a4444444444444444", session: demoAppSessionId, label: "Login", file: "LoginView.swift", startedAt: -272, toolUses: 20, durationMs: 108_000),
        auditAgent("a5555555555555555", session: demoAppSessionId, label: "Home", file: "HomeView.swift", startedAt: -271, toolUses: 22, durationMs: 125_000),
    ]

    static let loginAuditAgents: [DemoSubagent] = {
        let screens: [(String, String, Int, Int)] = [
            ("Login", "LoginView.swift", 9, 71_000),
            ("Cadastro", "SignUpView.swift", 8, 64_000),
            ("Home", "HomeView.swift", 11, 80_000),
            ("Ajustes", "SettingsView.swift", 10, 77_000),
            ("Perfil", "ProfileView.swift", 7, 58_000),
            ("Recuperar senha", "PasswordResetView.swift", 6, 55_000),
            ("Onboarding", "OnboardingView.swift", 8, 69_000),
            ("Busca", "SearchView.swift", 7, 62_000),
        ]
        let fixes = screens.enumerated().map { index, screen in
            auditAgent(
                String(format: "a7%015lx", index + 2),
                session: loginSessionId,
                label: screen.0,
                file: screen.1,
                startedAt: -141 + Double(index),
                toolUses: screen.2,
                durationMs: screen.3
            )
        }
        return [mapScreensAgent(String(format: "a7%015lx", 1), session: loginSessionId, startedAt: -164, toolUses: 12, durationMs: 22_000)]
            + fixes
            + [reviewAgent(String(format: "a7%015lx", 10), session: loginSessionId, startedAt: -55, toolUses: 6, durationMs: 21_000)]
    }()

    static func demoAppTurn() -> [ChatItem] {
        let glob = "Sources/**/*View.swift"
        let entries: [(TimeInterval, ChatItemKind)] = [
            (-380, .userPrompt(text: "roda o workflow auditoria-a11y em todas as telas do app", imageCount: 0)),
            (-378, .thinking(text: nil)),
            (-376, .toolCall(ToolCall(
                toolUseId: "toolu_demo_audit_glob",
                name: "Glob",
                summary: glob,
                inputJSON: TranscriptText.json(["pattern": glob]),
                status: .succeeded,
                resultPreview: "Sources/DemoApp/LoginView.swift\nSources/DemoApp/HomeView.swift\nSources/DemoApp/SettingsView.swift\nSources/DemoApp/ProfileView.swift"
            ))),
            (-374, .assistantText(markdown: "O app tem 4 telas. O workflow mapeia as telas, corrige cada uma em paralelo e revisa tudo no fim.")),
            (-373, workflowCard(
                runId: auditRunId,
                status: .running,
                startedAt: -372,
                durationMs: nil,
                phases: [
                    WorkflowPlan(title: "Mapear telas", agents: [auditAgents[0]]),
                    WorkflowPlan(title: "Corrigir por tela", detail: "uma tela por agente, com testes de UI", agents: Array(auditAgents[1...])),
                    WorkflowPlan(title: "Revisar", agents: []),
                ]
            )),
            (-363, .assistantText(markdown: "Ele roda em background; eu aviso quando a revisão terminar.")),
            (-362, .turnFooter(durationMs: 18_000)),
        ]
        return entries.enumerated().map { index, entry in
            ChatItem(id: entry.1.cardId ?? "demo-app-audit-\(index)", at: date(entry.0), kind: entry.1)
        }
    }

    static func loginSocialCards() -> [ChatItem] {
        [
            loginExplore.card(at: date(-180)),
            ChatItem(
                id: cardPrefix + loginAuditRunId,
                at: date(-165),
                kind: workflowCard(
                    runId: loginAuditRunId,
                    status: .completed,
                    startedAt: -164,
                    durationMs: 131_000,
                    phases: [
                        WorkflowPlan(title: "Mapear telas", agents: [loginAuditAgents[0]]),
                        WorkflowPlan(title: "Corrigir por tela", detail: "uma tela por agente, com testes de UI", agents: Array(loginAuditAgents[1...8])),
                        WorkflowPlan(title: "Revisar", agents: [loginAuditAgents[9]]),
                    ]
                )
            ),
        ]
    }

    static func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1_000).rounded())
    }

    private static let root = "/Users/dev/projects/receitas-api/"
    private static let appRoot = "/Users/dev/projects/demo-app/Sources/DemoApp/"

    private struct WorkflowPlan {
        var title: String
        var detail: String?
        var agents: [DemoSubagent]
    }

    private static func date(_ offset: TimeInterval) -> Date {
        DemoDataset.anchor.addingTimeInterval(offset)
    }

    private static func workflowCard(
        runId: String,
        status: WorkflowStatus,
        startedAt: TimeInterval,
        durationMs: Int?,
        phases: [WorkflowPlan]
    ) -> ChatItemKind {
        let agents = phases.flatMap(\.agents)
        return .workflow(
            WorkflowCall(
                toolUseId: "toolu_demo_" + runId,
                runId: runId,
                name: auditName,
                status: status,
                phases: phases.map { phase in
                    WorkflowPhase(
                        title: phase.title,
                        detail: phase.detail,
                        status: phaseStatus(of: phase.agents),
                        agents: phase.agents.map(\.workflowAgent)
                    )
                },
                agentCount: agents.count,
                toolUses: agents.map(\.toolUses).reduce(0, +),
                startedAt: date(startedAt),
                durationMs: durationMs
            )
        )
    }

    private static func phaseStatus(of agents: [DemoSubagent]) -> WorkflowPhaseStatus {
        if agents.isEmpty {
            return .pending
        }
        if agents.contains(where: { $0.status == .running }) {
            return .running
        }
        if agents.contains(where: { $0.status == .failed || $0.status == .stopped }) {
            return .failed
        }
        return .completed
    }

    private static func mapScreensAgent(_ agentId: String, session: String, startedAt: TimeInterval, toolUses: Int, durationMs: Int) -> DemoSubagent {
        workflowAgent(
            agentId,
            session: session,
            label: "Mapear",
            task: "Liste as telas do app (os arquivos *View.swift em Sources/), com o nome e o caminho de cada uma. Não edite nada.",
            steps: [
                ("Glob", "Sources/**/*View.swift", ["pattern": "Sources/**/*View.swift"]),
                ("Read", "LoginView.swift", ["file_path": appRoot + "LoginView.swift"]),
                ("Read", "HomeView.swift", ["file_path": appRoot + "HomeView.swift"]),
            ],
            answer: "Mapeei as telas do app e a navegação entre elas; cada uma vai para um agente da próxima fase.",
            startedAt: startedAt,
            toolUses: toolUses,
            durationMs: durationMs
        )
    }

    private static func reviewAgent(_ agentId: String, session: String, startedAt: TimeInterval, toolUses: Int, durationMs: Int) -> DemoSubagent {
        workflowAgent(
            agentId,
            session: session,
            label: "Revisar",
            task: "Revise as correções de acessibilidade de todas as telas e rode a suíte de testes de UI inteira.",
            steps: [
                ("Bash", "git diff --stat", ["command": "git diff --stat"]),
                ("Bash", "swift test --filter UITests", ["command": "swift test --filter UITests"]),
            ],
            answer: "Revisei as correções das telas: rótulos do VoiceOver completos, Dynamic Type sem cortes e contraste acima de 4,5:1. A suíte de UI passou.",
            startedAt: startedAt,
            toolUses: toolUses,
            durationMs: durationMs
        )
    }

    private static func auditAgent(
        _ agentId: String,
        session: String,
        label: String,
        file: String,
        startedAt: TimeInterval,
        toolUses: Int,
        durationMs: Int? = nil,
        running: (name: String, summary: String)? = nil
    ) -> DemoSubagent {
        let tests = String(file.prefix { $0 != "." }) + "Tests"
        return workflowAgent(
            agentId,
            session: session,
            label: label,
            task: "Audite a acessibilidade da tela \(label) (\(file)): rótulos do VoiceOver, Dynamic Type e contraste. Corrija o que faltar e rode os testes de UI da tela.",
            steps: [
                ("Read", file, ["file_path": appRoot + file]),
                ("Grep", "accessibilityLabel", ["pattern": "accessibilityLabel", "path": "Sources/DemoApp"]),
                ("Edit", file, ["file_path": appRoot + file, "old_string": "Image(systemName: \"gear\")", "new_string": "Image(systemName: \"gear\").accessibilityLabel(\"Ajustes\")"]),
                ("Bash", "swift test --filter \(tests)", ["command": "swift test --filter \(tests)"]),
            ],
            answer: "Tela \(label) corrigida: rótulos do VoiceOver nos botões de ícone, fontes com Dynamic Type e contraste acima de 4,5:1. Os testes de UI passaram.",
            startedAt: startedAt,
            toolUses: toolUses,
            durationMs: durationMs,
            running: running
        )
    }

    private static func workflowAgent(
        _ agentId: String,
        session: String,
        label: String,
        task: String,
        steps: [(String, String, KeyValuePairs<String, String>)],
        answer: String,
        startedAt: TimeInterval,
        toolUses: Int,
        durationMs: Int?,
        running: (name: String, summary: String)? = nil
    ) -> DemoSubagent {
        let end = durationMs.map { startedAt + TimeInterval($0) / 1_000 } ?? -12
        let spacing = (end - startedAt - 4) / Double(toolUses)
        var transcript = DemoTranscript(agentId: agentId)
        transcript.add(startedAt, .task(text: task))
        for index in 0..<toolUses {
            let offset = startedAt + 2 + Double(index) * spacing
            if let running, index == toolUses - 1 {
                let input: KeyValuePairs<String, String> = ["file_path": appRoot + running.summary]
                transcript.tool(offset, running.name, running.summary, input, status: .running)
            } else {
                let step = steps[index % steps.count]
                transcript.tool(offset, step.0, step.1, step.2, result: step.0 == "Bash" ? "Executed 12 tests, with 0 failures" : "Feito.")
            }
        }
        if durationMs != nil {
            transcript.add(end - 1, .assistantText(markdown: answer))
        }
        return DemoSubagent(
            sessionId: session,
            agentId: agentId,
            agentType: workflowAgentType,
            description: label,
            status: durationMs == nil ? .running : .completed,
            toolUses: toolUses,
            startedAt: date(startedAt),
            durationMs: durationMs,
            items: transcript.items
        )
    }
}

extension DemoSubagent {
    func card(at date: Date) -> ChatItem {
        ChatItem(id: cardId, at: date, kind: .subagent(call))
    }
}

private struct DemoTranscript {
    let agentId: String
    private(set) var items: [ChatItem] = []

    init(agentId: String) {
        self.agentId = agentId
    }

    mutating func add(_ offset: TimeInterval, _ kind: ChatItemKind) {
        items.append(
            ChatItem(
                id: kind.cardId ?? "\(agentId)-\(items.count)",
                at: DemoDataset.anchor.addingTimeInterval(offset),
                kind: kind
            )
        )
    }

    mutating func tool(
        _ offset: TimeInterval,
        _ name: String,
        _ summary: String,
        _ input: KeyValuePairs<String, String>,
        status: ToolStatus = .succeeded,
        result: String? = nil
    ) {
        add(
            offset,
            .toolCall(
                ToolCall(
                    toolUseId: "toolu_\(agentId)_\(items.count)",
                    name: name,
                    summary: summary,
                    inputJSON: TranscriptText.json(input),
                    status: status,
                    resultPreview: status == .running ? nil : result
                )
            )
        )
    }
}
