import Foundation
import MochaProtocol

enum DemoLongChat {
    static let agentId: AgentID = "w3:p1"
    static let itemCount = 2_000
    static let title = "Paginação com cursor em /receitas"
    static let workspaceLabel = "receitas-api"
    static let branch = "development"
    static let model = "claude-opus-5-5"
    static let sessionId = "8b2e6f4a-3c1d-4a9e-b7f5-2d8c0e6a1f93"
    static let turnStartOffset: TimeInterval = -238
    static let historyEndOffset: TimeInterval = -300

    private static let start = Date(timeIntervalSince1970: 1_789_981_200)
    private static let seed: UInt64 = 0x6D6F_6368_61

    static func chat() -> DemoChat {
        DemoChat(
            agentId: agentId,
            meta: ChatMeta(
                title: title,
                workspaceLabel: workspaceLabel,
                model: model,
                branch: branch,
                status: .working,
                permissionMode: "default"
            ),
            items: items()
        )
    }

    static func items() -> [ChatItem] {
        let turn = PaginationTurn.items()
        var writer = TranscriptWriter(start: start, seed: seed)
        var turnNumber = 0
        let historyCount = itemCount - turn.count
        while writer.entries.count < historyCount {
            writer.writeTurn(turnNumber)
            turnNumber += 1
        }
        let history = writer.entries.suffix(historyCount)
        let historyEnd = DemoDataset.anchor.addingTimeInterval(historyEndOffset)
        let shift = historyEnd.timeIntervalSince(history.last?.at ?? historyEnd)
        let shifted = history.map { (at: $0.at.addingTimeInterval(shift), kind: $0.kind) } + turn
        return shifted.enumerated().map { offset, entry in
            ChatItem(id: "long-\(offset)", at: entry.at, kind: entry.kind)
        }
    }
}

private enum PaginationTurn {
    private static let root = "/Users/dev/projects/receitas-api/"

    static func items() -> [(at: Date, kind: ChatItemKind)] {
        let steps: [(TimeInterval, ChatItemKind)] = [
            (DemoLongChat.turnStartOffset, .userPrompt(text: "troca a paginação de /receitas para cursor. mantém o formato da resposta", imageCount: 0)),
            (-233, .thinking(text: nil)),
            (-226, .assistantText(markdown: "A listagem usa `LIMIT/OFFSET`; com 40 mil receitas a página 200 leva 1,8 s. Cursor resolve sem mudar o contrato.")),
            (-221, tool(1, "Bash", #"rg -n "OFFSET" internal/"#, command: #"rg -n "OFFSET" internal/"#, result: "internal/recipes/store.go:88:  LIMIT $1 OFFSET $2")),
            (-216, tool(2, "Bash", #"rg -n "OFFSET" internal/"#, command: #"rg -n "OFFSET" internal/"#, result: "internal/recipes/store.go:88:  LIMIT $1 OFFSET $2")),
            (-209, tool(3, "Read", "internal/recipes/handler.go", path: "internal/recipes/handler.go", result: "212 linhas")),
            (-200, .assistantText(markdown: "Vou usar um cursor opaco em base64 com ordenação estável por id.")),
            (-194, tool(4, "Read", "internal/recipes/store.go", path: "internal/recipes/store.go", result: "164 linhas")),
            (-188, tool(5, "Read", "internal/recipes/store.go", path: "internal/recipes/store.go", result: "40 linhas")),
            (-178, tool(6, "Edit", "internal/recipes/store.go", path: "internal/recipes/store.go", result: "Arquivo atualizado.")),
            (-167, tool(7, "Edit", "internal/recipes/store.go", path: "internal/recipes/store.go", result: "Arquivo atualizado.")),
            (-158, tool(8, "Edit", "internal/recipes/store.go", path: "internal/recipes/store.go", result: "Arquivo atualizado.")),
            (-146, .assistantText(markdown: "Troquei o `OFFSET` por cursor em `ListRecipes` e ajustei o handler. Rodando os testes de integração:")),
            (-140, tool(9, "Bash", "go test ./internal/... -run Pagination -count=1", command: "go test ./internal/... -run Pagination -count=1", status: .running)),
        ]
        return steps.map { (DemoDataset.anchor.addingTimeInterval($0.0), $0.1) }
    }

    private static func tool(
        _ number: Int,
        _ name: String,
        _ summary: String,
        command: String? = nil,
        path: String? = nil,
        status: ToolStatus = .succeeded,
        result: String? = nil
    ) -> ChatItemKind {
        let input = command.map { TranscriptText.json(["command": $0]) }
            ?? TranscriptText.json(["file_path": root + (path ?? summary)])
        return .toolCall(
            ToolCall(
                toolUseId: "toolu_long_turn_\(number)",
                name: name,
                summary: summary,
                inputJSON: input,
                status: status,
                resultPreview: result
            )
        )
    }
}

private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    mutating func chance(percent: Int) -> Bool {
        int(1...100) <= percent
    }

    mutating func element<Element>(of values: [Element]) -> Element {
        values[int(0...(values.count - 1))]
    }
}

private enum ToolKind {
    case bash, read, edit, write, grep, glob, agent, webFetch, todoWrite
}

private struct TranscriptWriter {
    private(set) var entries: [(at: Date, kind: ChatItemKind)] = []
    private var clock: Date
    private var random: SeededRandom
    private var toolNumber = 0

    init(start: Date, seed: UInt64) {
        clock = start
        random = SeededRandom(seed: seed)
    }

    mutating func writeTurn(_ turn: Int) {
        clock += TimeInterval(random.int(90...1_200))
        if turn % 17 == 16 {
            writeSlashCommand(turn)
            return
        }
        let turnStart = clock
        write(.userPrompt(text: random.element(of: TranscriptText.prompts), imageCount: turn % 29 == 5 ? 1 : 0))
        if random.chance(percent: 75) {
            write(.thinking(text: random.chance(percent: 15) ? random.element(of: TranscriptText.thoughts) : nil))
        }
        write(.assistantText(markdown: random.element(of: TranscriptText.plans)))
        let toolCount = random.int(1...6)
        let isInterrupted = turn % 31 == 30
        for index in 0..<toolCount {
            let isLast = index == toolCount - 1
            let status: ToolStatus =
                if isInterrupted && isLast { .running } else if random.chance(percent: 12) { .failed } else { .succeeded }
            writeTool(status: status)
            if !isLast && random.chance(percent: 30) {
                write(.thinking(text: nil))
            }
        }
        if isInterrupted {
            write(.notice(text: "Interrompido pelo usuário"))
            return
        }
        write(.assistantText(markdown: answer(turn)))
        advance()
        entries.append((clock, .turnFooter(durationMs: Int((clock.timeIntervalSince(turnStart) * 1_000).rounded()))))
        if turn % 23 == 22 {
            write(.recap(text: random.element(of: TranscriptText.recaps)))
        }
    }

    private mutating func advance() {
        clock += TimeInterval(random.int(2...25))
    }

    private mutating func write(_ kind: ChatItemKind) {
        advance()
        entries.append((clock, kind))
    }

    private mutating func writeSlashCommand(_ turn: Int) {
        switch (turn / 17) % 4 {
        case 0:
            write(.slashCommand(name: "/compact", args: "", output: "Conversa compactada (\(random.int(40...90)) mil → \(random.int(6...12)) mil tokens)."))
            write(.notice(text: "Conversa compactada"))
        case 1:
            write(.slashCommand(name: "/context", args: "", output: "Contexto: \(random.int(20...80)) mil de 200 mil tokens usados."))
        case 2:
            write(.slashCommand(name: "!", args: "git status --short", output: " M internal/recipes/handler.go\n M internal/recipes/store.go"))
        default:
            write(.slashCommand(name: "/cost", args: "", output: "Custo da sessão: US$ \(random.int(1...9)),\(random.int(10...99))"))
        }
    }

    private mutating func writeTool(status: ToolStatus) {
        toolNumber += 1
        let toolUseId = "toolu_long_\(toolNumber)"
        let call: ToolCall
        switch random.element(of: TranscriptText.toolWeights) {
        case .bash:
            let command = random.element(of: TranscriptText.commands)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Bash",
                summary: command.line,
                inputJSON: TranscriptText.json(["command": command.line]),
                status: status,
                resultPreview: status == .failed ? command.failure : command.success
            )
        case .read:
            let path = random.element(of: TranscriptText.paths)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Read",
                summary: path,
                inputJSON: TranscriptText.json(["file_path": TranscriptText.projectRoot + path]),
                status: status,
                resultPreview: status == .failed ? "Arquivo não encontrado." : "\(random.int(30...420)) linhas"
            )
        case .edit:
            let path = random.element(of: TranscriptText.paths)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Edit",
                summary: path,
                inputJSON: TranscriptText.json([
                    "file_path": TranscriptText.projectRoot + path,
                    "old_string": "return nil, err",
                    "new_string": "return nil, fmt.Errorf(\"listar receitas: %w\", err)",
                ]),
                status: status,
                resultPreview: status == .failed ? "old_string não encontrado no arquivo." : "Arquivo atualizado."
            )
        case .write:
            let path = random.element(of: TranscriptText.newPaths)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Write",
                summary: path,
                inputJSON: TranscriptText.json(["file_path": TranscriptText.projectRoot + path, "content": "package recipes\n"]),
                status: status,
                resultPreview: status == .failed ? "Permissão negada." : "Arquivo criado."
            )
        case .grep:
            let pattern = random.element(of: TranscriptText.grepPatterns)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Grep",
                summary: pattern,
                inputJSON: TranscriptText.json(["pattern": pattern, "path": "internal"]),
                status: status,
                resultPreview: status == .failed
                    ? "Expressão regular inválida."
                    : "internal/recipes/store.go:\(random.int(10...200))\ninternal/tags/store.go:\(random.int(10...90))"
            )
        case .glob:
            let pattern = random.element(of: TranscriptText.globPatterns)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Glob",
                summary: pattern,
                inputJSON: TranscriptText.json(["pattern": pattern]),
                status: status,
                resultPreview: status == .failed
                    ? "Nenhum arquivo encontrado."
                    : "internal/recipes/handler_test.go\ninternal/recipes/store_test.go\ninternal/tags/tags_test.go"
            )
        case .agent:
            let description = random.element(of: TranscriptText.agentTasks)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "Agent",
                summary: description,
                inputJSON: TranscriptText.json(["description": description, "prompt": description + " e resuma o que encontrar."]),
                status: status,
                resultPreview: status == .failed
                    ? "O subagente foi interrompido."
                    : "Encontrei \(random.int(2...9)) pontos. Nenhum bloqueia a mudança."
            )
        case .webFetch:
            let url = random.element(of: TranscriptText.urls)
            call = ToolCall(
                toolUseId: toolUseId,
                name: "WebFetch",
                summary: url,
                inputJSON: TranscriptText.json(["url": url, "prompt": "Resuma a parte sobre paginação."]),
                status: status,
                resultPreview: status == .failed ? "HTTP 404" : "A documentação recomenda paginação por cursor em listas grandes."
            )
        case .todoWrite:
            call = ToolCall(
                toolUseId: toolUseId,
                name: "TodoWrite",
                summary: "3 tarefas",
                inputJSON: #"{"todos":[{"content":"Criar migração","status":"completed"},{"content":"Atualizar store","status":"in_progress"},{"content":"Documentar endpoint","status":"pending"}]}"#,
                status: status,
                resultPreview: status == .failed ? "Lista inválida." : "Lista atualizada."
            )
        }
        write(.toolCall(call))
    }

    private mutating func answer(_ turn: Int) -> String {
        switch random.int(0...9) {
        case 0:
            """
            ## Resumo da etapa \(turn + 1)

            - `internal/recipes/handler.go`: validação do payload movida para `Validate()`
            - `internal/recipes/store.go`: consulta paginada com `LIMIT` e cursor
            - testes novos em `handler_test.go` (**\(random.int(3...12)) casos**)

            Tudo passando com `go test ./...`.
            """
        case 1:
            """
            A consulta paginada ficou assim:

            ```go
            func (s *Store) List(ctx context.Context, after int64, limit int) ([]Recipe, error) {
                rows, err := s.db.Query(ctx, listQuery, after, limit)
                if err != nil {
                    return nil, fmt.Errorf("listar receitas: %w", err)
                }
                defer rows.Close()
                return scanRecipes(rows)
            }
            ```

            O cursor é o `id` da última receita da página anterior.
            """
        case 2:
            """
            Medi antes e depois da mudança:

            | Endpoint | Antes | Depois |
            |---|---:|---:|
            | `GET /recipes` | \(random.int(120...400)) ms | \(random.int(20...80)) ms |
            | `GET /recipes/:id` | \(random.int(30...90)) ms | \(random.int(5...25)) ms |
            | `GET /favorites` | \(random.int(200...900)) ms | \(random.int(40...120)) ms |

            A maior diferença veio do índice em `recipe_id`.
            """
        case 3:
            """
            Plano para a migração:

            1. Criar `migrations/\(String(turn % 90 + 10))_add_tags.sql`
               - tabela `tags` com `name` único
               - tabela de junção `recipe_tags`
            2. Atualizar o `store.go`
               - `AddTag` e `RemoveTag`
               - `ListByTag` com paginação
            3. Expor `POST /recipes/:id/tags`

            Posso seguir?
            """
        case 4:
            """
            > **Atenção:** o `TestImportCSV` depende do fuso horário da máquina.

            Fixei o fuso em *UTC* no `TestMain`, e o teste passou \(random.int(5...50)) vezes seguidas.
            """
        case 5:
            """
            Para reproduzir localmente:

            ```bash
            docker compose up -d db
            go test ./internal/... -run TestList -count=1
            ```

            Referência: [documentação do pgx](https://pkg.go.dev/github.com/jackc/pgx/v5).
            """
        case 6:
            """
            Resposta nova do `GET /recipes?limit=2`:

            ```json
            {
              "items": [
                {"id": \(turn * 2 + 100), "title": "Bolo de cenoura", "minutes": 50},
                {"id": \(turn * 2 + 101), "title": "Arroz de forno", "minutes": 35}
              ],
              "next": "c\(turn)",
              "hasMore": true
            }
            ```
            """
        case 7:
            """
            ### Checklist

            - [x] migração aplicada
            - [x] testes de `store_test.go`
            - [ ] atualizar o README

            ```sql
            CREATE INDEX CONCURRENTLY idx_ingredients_name ON ingredients (lower(name));
            ```
            """
        case 8:
            """
            ### O que mudou

            O middleware de rate limit agora usa um *token bucket* por IP, com **\(random.int(5...50)) requisições por segundo**.

            ---

            ### O que falta

            Ler o limite da variável de ambiente `RATE_LIMIT_RPS`.
            """
        default:
            "Feito. O teste agora passa e o `go vet` não aponta nada."
        }
    }
}

private enum TranscriptText {
    struct Command {
        var line: String
        var success: String
        var failure: String
    }

    static let projectRoot = "/Users/dev/projects/receitas-api/"

    static let toolWeights: [ToolKind] = [
        .bash, .bash, .bash, .read, .read, .read, .edit, .edit, .write, .grep, .glob, .agent, .webFetch, .todoWrite,
    ]

    static let prompts = [
        "roda os testes do pacote de receitas e corrige o que falhar",
        "adiciona paginação por cursor no GET /recipes",
        "por que o TestImportCSV falha só no CI?",
        "cria a migração para a tabela de tags",
        "revisa o handler de busca e simplifica a validação",
        "sobe o limite de upload de fotos para 5 MB",
        "o Postgres está recusando conexão, investiga",
        "documenta os endpoints novos no README",
        "troca o log para slog com nível configurável",
        "adiciona um índice para a busca por ingrediente",
        "escreve testes de tabela para o parser de quantidades",
        "extrai o cliente HTTP de nutrição para um pacote próprio",
        "o endpoint de favoritos está lento, mede e otimiza",
        "remove o código morto do importador antigo",
        "adiciona rate limit por IP no middleware",
        "prepara o changelog da versão 0.8",
    ]

    static let thoughts = [
        "O erro parece vir do fuso horário do container de CI.",
        "Preciso checar se o cursor continua estável quando duas receitas têm a mesma data de criação.",
        "Melhor medir antes de mexer no índice.",
        "O handler valida o payload duas vezes; dá para juntar num lugar só.",
    ]

    static let plans = [
        "Vou começar lendo o código atual.",
        "Primeiro vou reproduzir o problema localmente.",
        "Vou procurar onde isso é usado antes de mudar.",
        "Certo. Vou olhar os testes existentes e depois ajustar o `store.go`.",
        "Deixa eu conferir o esquema do banco antes.",
    ]

    static let recaps = [
        "Paginação por cursor pronta em /recipes; faltam os testes de favoritos e o README.",
        "Migração de tags aplicada e testada. Próximo passo: expor o endpoint de tags.",
        "O TestImportCSV estava quebrando por causa do fuso; corrigido no TestMain.",
    ]

    static let commands = [
        Command(
            line: "go test ./...",
            success: "ok  \tgithub.com/dev/receitas-api/internal/recipes\t0.412s\nok  \tgithub.com/dev/receitas-api/internal/tags\t0.198s",
            failure: "--- FAIL: TestImportCSV (0.02s)\n    import_test.go:48: esperava 12 receitas, veio 11\nFAIL"
        ),
        Command(
            line: "go build ./cmd/api",
            success: "Build concluído sem erros.",
            failure: "cmd/api/main.go:31:2: undefined: recipes.NewStore"
        ),
        Command(
            line: "go vet ./...",
            success: "Nenhum problema encontrado.",
            failure: "internal/recipes/store.go:88:3: unreachable code"
        ),
        Command(
            line: "psql receitas -c 'select count(*) from recipes'",
            success: " count \n-------\n  1284\n(1 row)",
            failure: "psql: error: connection to server on socket \"/tmp/.s.PGSQL.5432\" failed"
        ),
        Command(
            line: "git status --short",
            success: " M internal/recipes/handler.go\n M internal/recipes/store.go\n?? migrations/0007_add_tags.sql",
            failure: "fatal: not a git repository"
        ),
        Command(
            line: "curl -s localhost:8080/recipes?page=2",
            success: #"{"items":[{"id":41,"title":"Pão de queijo"}],"page":2,"hasMore":true}"#,
            failure: "curl: (7) Failed to connect to localhost port 8080"
        ),
        Command(
            line: "golangci-lint run",
            success: "0 issues.",
            failure: "internal/tags/tags.go:14:6: func `normalize` is unused (unused)"
        ),
    ]

    static let paths = [
        "internal/recipes/handler.go",
        "internal/recipes/store.go",
        "internal/recipes/import.go",
        "internal/tags/tags.go",
        "internal/http/middleware.go",
        "cmd/api/main.go",
        "README.md",
    ]

    static let newPaths = [
        "internal/recipes/handler_test.go",
        "internal/tags/store_test.go",
        "migrations/0007_add_tags.sql",
        "internal/nutrition/client.go",
    ]

    static let grepPatterns = ["func .*Handler", "TODO", "sql.ErrNoRows", "context.Background()"]

    static let globPatterns = ["**/*_test.go", "migrations/*.sql", "internal/**/*.go"]

    static let agentTasks = [
        "Revisar a migração de tags",
        "Procurar usos de ListRecipes",
        "Conferir os testes do importador",
    ]

    static let urls = [
        "https://pkg.go.dev/github.com/jackc/pgx/v5",
        "https://go.dev/doc/effective_go",
    ]

    static func json(_ fields: KeyValuePairs<String, String>) -> String {
        "{" + fields.map { quoted($0.key) + ":" + quoted($0.value) }.joined(separator: ",") + "}"
    }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
