# Mocha: plano de execução

Este plano é executado por **um agente orquestrador** que distribui pacotes de trabalho (WPs) entre subagentes. O **quê** e o **como** estão em `docs/SPEC.md` (fonte da verdade). As regras de trabalho estão em `AGENTS.md`. O prompt de partida está em `prompts/orquestrador.md`.

## Como o orquestrador trabalha

1. Lê `AGENTS.md`, a SPEC inteira e a fase atual deste plano.
2. Confere os bloqueios (`Bx`) da fase. O que depende do João é pedido **no começo da fase**, junto, não no meio.
3. Executa os WPs em **ondas**: dentro de uma onda, os WPs rodam em paralelo, um subagente por WP. A próxima onda começa quando a anterior foi revisada e commitada.
4. A partir da 1a-core, cada WP roda num **worktree do Herdr** próprio, que o orquestrador cria no início da onda: `herdr worktree create --cwd ~/Developer/mocha --branch wp/<id> --base fase/<fase> --path ~/Developer/mocha/.claude/worktrees/<id> --no-focus`. O subagente trabalha só nesse caminho.
5. Para cada WP, o subagente recebe: o bloco do WP deste plano, as §§ da SPEC citadas, os arquivos que já existem e são relevantes, as regras de subagente de `AGENTS.md` e o caminho absoluto do worktree.
6. O orquestrador revisa o diff de cada WP contra os critérios de aceite, roda a validação (ou delega a um subagente de validação, §Builds) e faz os commits. A partir da 1a-core, os commits vão para `wp/<id>`; depois, o orquestrador faz `git merge --no-ff wp/<id>` na branch da fase (sem rebase) e roda `herdr worktree remove`, que mantém a branch. Só então marca o WP como feito na tabela de status (fim deste arquivo).
7. Ao fim de cada marco, roda o WP de integração com o João (teste no iPhone real).

**Paralelismo seguro**
- Cada WP tem um **diretório dono**. Dois WPs da mesma onda nunca têm donos sobrepostos. Com um worktree por WP, os donos continuam valendo: são eles que garantem o merge sem conflito.
- Arquivos compartilhados são **do orquestrador**: `MochaKit/Package.swift`, `project.yml`, `MochaKit/Sources/MochaProtocol/**`, `MochaKit/Fixtures/protocol/**`, `App/Info.plist`, `App/Mocha.entitlements`, `Widgets/Info.plist`, `AGENTS.md`, `.gitignore`, `docs/SPEC.md`, `docs/PLANO.md` e `docs/HANDOFF.md`. Um subagente que precisar mudar algum deles descreve a mudança (diff) no relatório, e o orquestrador aplica antes de integrar. O bloco de um WP pode entregar um desses arquivos ao WP, só naquela onda (ex.: WP-D1).
- Mudança num arquivo do orquestrador no meio de uma onda: ele aplica no worktree do WP que precisa dela, em commit separado.
- No máximo **3 subagentes simultâneos**, spikes incluídos (M1 com 8 GB; builds do Xcode são pesados).
- Quando dois WPs da mesma onda precisam do mesmo diretório, o bloco de cada WP diz quais **arquivos** são dele. Um WP que precisar mexer num arquivo do outro propõe o diff no relatório.

**Builds**
- Cada worktree tem o próprio `.build` e o próprio `build/DerivedData`. `scripts/test.sh` roda no worktree, sem `--scratch-path`.
- `xcodebuild` roda **um de cada vez** na máquina. Os scripts de build do app (`build-app.sh`, `build-device.sh`) garantem isso com uma trava (`scripts/lib/xcode-lock.sh`, em `~/Library/Caches/com.joaoalves.mocha/xcodebuild.lock`) e compartilham os pacotes clonados em `~/Library/Caches/com.joaoalves.mocha/SourcePackages`.
- Medições de desempenho (tempo de página, `signpost`, RSS) rodam numa janela sem nenhum build, marcada pelo orquestrador.

## Visão das fases

| Fase | Resultado | Marco de integração |
|---|---|---|
| 0 | Repositório, contratos, servidor HTTP e todas as incertezas técnicas resolvidas por spikes | — |
| 1a-core | Parear, Home (central de agentes) com uso do plano e sessões arquivadas, gaveta, ler e mandar mensagem, mandar imagem, interromper. Uso diário possível | WP-X1 |
| 1a-final | Push de turno concluído e de agente bloqueado; slash commands; nova tab | WP-X2 |
| subagentes | Subagentes e workflows no app: card do subagente no chat com o transcript dele, selo na Home, lista no Detalhe e card de workflow | WP-X6 |
| 1b | Inbox e ações na notificação, Live Activity, voz | WP-X3 |
| 1b-feed | Live Activity única que acompanha o último evento (§7.5); aceitar plano pela tela bloqueada | WP-XF |
| codex | Codex CLI no Herdr com chat e ações; desktop como leitura posterior | WP-XC |
| preview-web | Servidores web do Mac listados no app e abertos no iPhone por túnel SSH | WP-W5 |
| 2 | Terminal SSH | WP-X4 |
| 3 | Mosh | WP-X5 |

A `main` só recebe uma fase depois do checklist do WP de integração dela. Enquanto isso, a branch da fase seguinte sai da branch da fase anterior (`fase/1a-final` a partir de `fase/1a-core`, e assim por diante), e o merge em `main` segue a mesma ordem. A fase Codex é a exceção de início: sai de `main` após o merge de 1b, antes do checklist WP-X3, por decisão do João em 2026-09-27.

## Bloqueios externos (ações do João)

| Código | O que o João faz | Necessário em |
|---|---|---|
| B1 | Confirmar a conta Apple Developer paga ativa e informar o **Team ID** (developer.apple.com › Membership). **Resolvido**: time da empresa, Team ID em `Config/Signing.xcconfig` | S4, WP-I1 (assinatura no device) |
| B2 | Criar uma chave **APNs** (developer.apple.com › Certificates, IDs & Profiles › Keys › "+" › Apple Push Notifications service), baixar a `.p8` e informar o **Key ID**. A importação é feita com `mochad apns import`. **Resolvido**: chave Team Scoped nova, só para o Mocha; o João informa o caminho da `.p8` e o Key ID ao orquestrador (fora do git) | S4 |
| B3 | iPhone com **Modo de Desenvolvedor** ligado (Ajustes › Privacidade e Segurança) e pareado com o Xcode (Window › Devices and Simulators), no mesmo Wi-Fi ou por cabo. **Resolvido**: iPhone 14 (iOS 27), Modo de Desenvolvedor ligado e aparelho registrado no time. Sem Dynamic Island: ela é verificada no simulador | S4, WP-X1 |
| B4 | Os certificados HTTPS do tailnet já estão ativos. Resta **autorizar** o comando `tailscale serve` quando o S5 pedir (ele altera a config do Tailscale do Mac). **Autorizado** em 2026-09-25 para o S5: `tailscale serve --bg --https=443` com os alvos `unix:` e `http://127.0.0.1:47421`, e `tailscale serve reset` no fim. **Autorizado** também para o WP-X1: `mochad serve-setup --apply`, que fica como config definitiva | S5 |
| B5 | Ligar o **Login Remoto** (Ajustes do Sistema › Geral › Compartilhamento › Login Remoto) e adicionar a chave pública do app em `~/.ssh/authorized_keys` | preview-web (depois do WP-W4) e Fase 2 |
| B6 | No app Tailscale do iPhone, ligar **VPN On Demand** (sempre conectado) | WP-X2 |
| B7 | Remover os hooks do Moshi: `moshi-hook uninstall` e `brew services stop moshi-hook`. Só **depois** que o Mocha estiver cobrindo o uso diário (fim da 1a-final) | Antes da fase 1b |
| B8 | Testar no iPhone e dar o ok visual em cada marco (checklists dos WPs de integração) | WP-X1…X5 |

---

## Fase 0: fundação e spikes

**Ondas**
- **Onda 0.A**: WP0.1, feito pelo orquestrador direto em `main`. Depois, a branch `fase/0`.
- **Onda 0.B**, em paralelo: WP0.2 · S2 · S1.
- **Onda 0.C**, em paralelo: WP0.3 · S3. O WP0.3 não roda junto com o WP0.2 porque o `swift test` compila o pacote inteiro num bundle só: com o `MochaProtocol` em edição, o build do `MochaDaemonCore` quebra na mesma árvore.
- **Onda 0.D**: S5 (mexe em `mochad/` e no app; roda sozinho).
- **Onda 0.E**: S4 (mexe em `mochad/` e no app; roda sozinho). Precisa de B1–B3. Se esses bloqueios atrasarem, o S4 passa para o começo da 1a-final e a Fase 0 fecha sem ele (registrado na tabela de status).

A Fase 0 termina com o merge de `fase/0` em `main`, depois do ok do João.

Os spikes registram o resultado em `docs/spikes/Sx.md` (formato em `docs/spikes/TEMPLATE.md`). As mudanças nas §§ indicadas em "SPEC a atualizar" e o impacto nos WPs seguintes vão na seção "Impacto". O orquestrador aplica tudo na SPEC e neste plano antes da próxima onda que dependa do spike.

**Regras de segurança dos spikes**
- **Herdr**: o Herdr do João é real e está em uso. Spikes só **leem** estado do Herdr, exceto dentro do próprio workspace de laboratório (`mocha-lab-<Sx>`, com diretório em `~/Developer/mocha-lab/<Sx>/`, fora do repositório), fechado no fim do spike. Nunca mandar texto ou teclas para panes fora dele.
- **Claude**: sessões de teste rodam dentro do laboratório, iniciadas com `herdr pane run <pane do lab> "claude --setting-sources project,local --settings <arquivo>"`. Assim os hooks globais do João (inclusive os do moshi-hook) não carregam e o `~/.claude/settings.json` não é tocado. O arquivo de settings do teste inclui o hook `SessionStart` do Herdr (`bash ~/.claude/hooks/herdr-agent-state.sh session`) para o Herdr continuar reconhecendo a sessão.
- **Redação**: fixtures tiradas do ambiente real trocam nomes e caminhos de projetos de trabalho (initech, acme, bank-app) e textos de conversa por equivalentes neutros (`demo-app`, `/Users/dev/projects/demo-app`), preservando a estrutura.

### WP0.1: scaffold do repositório

- **Executor**: o orquestrador, direto em `main`.
- **Dono**: raiz, `project.yml`, `Config/`, `MochaKit/Package.swift`, `scripts/`, esqueletos vazios de todos os diretórios de §2.2.
- **Depende de**: —
- **SPEC**: §1.2, §2.2, §11.
- **Faz**:
  1. `git init` (branch `main`) e `.gitignore` (`.build/`, `build/`, `*.xcodeproj`, `DerivedData`, `.DS_Store`, `xcuserdata/`, `.swiftpm/`, `*.p8`, `Config/Signing.xcconfig`, `MochaKit/Fixtures/transcripts/generated/`).
  2. Primeiro commit só com `docs/`, `prompts/`, `AGENTS.md`, `CLAUDE.md` e `README.md` (`docs(spec): add spec, plan and agent rules`).
  3. `MochaKit/Package.swift` com os targets e dependências da tabela de §2.2 (bibliotecas vazias compilando, `mochad --version` imprimindo `0.1.0`) e os test targets com um teste trivial cada, incluindo `MochaDemoTests`. Cada test target ganha um helper `Fixtures` que resolve `MochaKit/Fixtures/` por `#filePath` (o SwiftPM não aceita recurso fora do diretório do target).
  4. `project.yml` com os targets `Mocha` (iOS 26, bundle `com.example.mocha`, dependências de §2.2) e `MochaWidgets` (extensão de widget com Live Activity, bundle `com.example.mocha.widgets`). `swift-markdown` com a versão estável mais recente, fixada com `exactVersion` e registrada na §11. Assinatura automática com `DEVELOPMENT_TEAM` vindo de `Config/Signing.xcconfig`.
  5. Entitlements do app: `aps-environment` (development) e `com.apple.developer.usernotifications.time-sensitive`. `NSSupportsLiveActivities = YES` no Info.plist do app.
  6. Scripts de §2.2, executáveis, com `set -euo pipefail` e caminhos absolutos para as ferramentas do Homebrew. O `bootstrap.sh` copia `Config/Signing.example.xcconfig` para `Config/Signing.xcconfig` se ele não existir. O `build-app.sh` compila para o simulador com `CODE_SIGNING_ALLOWED=NO`. O `build-device.sh` compila assinado para o iPhone (`-allowProvisioningUpdates`).
  7. App mínimo: tela preta com "Mocha" em mono. Em `AppShell/`, o ponto de entrada já tem `@UIApplicationDelegateAdaptor` e um roteador de sondas de debug por argumento de launch (`-probe push|gateway`), para o S4 e o S5 plugarem as sondas sem mexer fora dos seus donos.
  8. `MochaAgentsAttributes` (§7.3) em `MochaProtocol`, sob `#if os(iOS)`, e a extensão `MochaWidgets` com uma Live Activity mínima sobre ele.
  9. Commit do scaffold (`chore(scaffold): …`) em `main` e criação da branch `fase/0`.
- **Aceite**:
  - [ ] `scripts/bootstrap.sh` gera `Mocha.xcodeproj` sem erro.
  - [ ] `scripts/test.sh` passa.
  - [ ] `scripts/build-app.sh` compila para o simulador.
  - [ ] `scripts/build-daemon.sh` gera o binário e `mochad --version` imprime `0.1.0`.
  - [ ] `git log` mostra o commit de docs primeiro.

### WP0.2: `MochaProtocol` v1, fixtures e fakes

- **Dono**: `MochaKit/Sources/MochaProtocol/`, `MochaKit/Fixtures/protocol/`, `MochaKit/Sources/MochaDemo/`, `MochaKit/Tests/MochaProtocolTests/`, `MochaKit/Tests/MochaDemoTests/`. Executado pelo orquestrador, ou por um subagente com revisão linha a linha.
- **Depende de**: WP0.1.
- **SPEC**: §5 inteira.
- **Faz**:
  1. Todos os tipos de §5.2 e as mensagens de §5.3 como `enum ClientMessage`/`ServerMessage` (com caso `.unknown(type:)`), `Codable` manual no formato de §5.2.1, e o envelope com `v`/`id`/`type`. Uma fixture JSON por mensagem em `Fixtures/protocol/`, começando pelos exemplos canônicos de §5.2.1.
  2. O protocolo `ServerConnection` em `MochaProtocol`: `func send(_ message: ClientMessage) async throws -> String` (devolve o `id`) e `var messages: AsyncStream<ServerEnvelope> { get }`.
  3. Em `MochaDemo`, o `DemoServerConnection`: uma implementação em processo de `ServerConnection` que responde a `hello`, `openChat`, `sendPrompt` (ecoa como `userPrompt` e, 2 s depois, uma resposta fixa) e `interrupt`, com uma árvore de 4 workspaces (um com worktree aninhado) e 3 chats longos em `Sources/MochaDemo/Resources/*.json`. É esse modo demo que o app usa para rodar sem daemon.
- **Aceite**:
  - [ ] Teste de ida e volta (decode → encode → decode) de cada fixture passa.
  - [ ] Tipo desconhecido decodifica como `.unknown(type:)` sem lançar erro; `ChatItem` desconhecido vira `.unsupported`.
  - [ ] Teste do `DemoServerConnection`: `hello` → `helloOk` + `tree`; `openChat` → `chatPage`.
  - [ ] Compila para iOS e macOS (`swift build` e build do app).

### WP0.3: `HttpServer`

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Http/`, `MochaKit/Tests/MochaDaemonCoreTests/Http/`.
- **Depende de**: WP0.1.
- **SPEC**: §4.4.
- **Faz**: servidor HTTP/1.1 mínimo sobre `NWListener` (TCP em `127.0.0.1`; socket Unix se o `NWListener` suportar, senão reporta), com roteador por método e path, handlers `async`, limites de corpo, e WebSocket com upgrade e framing RFC 6455 próprios (§4.4).
- **Aceite**:
  - [ ] Teste com `URLSession` real contra a porta efêmera: GET, POST com corpo, 404, 405 e corpo acima do limite (413). O 413 é decidido pelo `Content-Length` e o servidor drena o corpo antes de fechar, para o cliente receber a resposta em vez de um reset.
  - [ ] Handler que segura a resposta (5 s no teste) responde no fim; o cliente que desiste antes cancela a `Task` do handler.
  - [ ] Teste de WebSocket com `URLSessionWebSocketTask`: handshake, texto nos dois sentidos, ping/pong e close.
  - [ ] Teste de mensagem fragmentada e de frame sem máscara (rejeitado) com um cliente TCP cru (`NWConnection` e frames montados à mão), porque o `URLSessionWebSocketTask` não fragmenta.
  - [ ] Resultado registrado no relatório: o `NWListener` aceita ou não socket Unix.
  - [ ] Nenhuma dependência nova.

### S1: transcript do Claude Code

- **Dono**: `docs/spikes/S1.md`, `MochaKit/Fixtures/transcripts/`, `scripts/gen-big-transcript.swift`, laboratório `mocha-lab-S1`.
- **Depende de**: WP0.1.
- **SPEC a atualizar**: §3.2.
- **Faz**:
  1. Catalogar os tipos e subtipos em transcripts reais de `~/.claude/projects` (versão atual do Claude Code), incluindo imagens coladas, `/clear`, `/compact` (`compact_boundary`), subagentes (`isSidechain`, arquivos em `<session>/subagents/`), erros de ferramenta, interrupção (Esc), AskUserQuestion, pedidos de permissão e plan mode.
  2. Gerar 6–10 fixtures pequenas (≤ 300 linhas cada) cobrindo esses casos. Texto de trabalho (initech, acme) é trocado por texto neutro, preservando a estrutura.
  3. Gerar uma fixture sintética grande (≥ 50 MB) por script, para medir desempenho, em `MochaKit/Fixtures/transcripts/generated/` (ignorado pelo git). Ela não vai para o git: o script sim.
  4. No laboratório, confirmar se `/clear` cria um novo `session_id` e como o Herdr reflete isso em `agent.list`.
- **Aceite**:
  - [ ] `S1.md` com a tabela de mapeamento final (entrada → `ChatItem`), casos-limite e a política para tipos novos.
  - [ ] Fixtures versionadas e o script da fixture grande em `scripts/`.

### S2: socket do Herdr

- **Dono**: `docs/spikes/S2.md`, `MochaKit/Fixtures/herdr/`, laboratório `mocha-lab-S2`.
- **Depende de**: WP0.1.
- **SPEC a atualizar**: §3.1.
- **Faz**:
  1. Confirmar o caminho do socket, o framing, os ids e o formato de erro.
  2. Registrar as respostas reais de `workspace.list`, `tab.list`, `agent.list`, `agent.get` e `pane.get`, e os eventos de §3.1.3, cada um como fixture.
  3. No laboratório: `tab.create`, Claude iniciado por `pane run` com as flags das regras acima, `agent.prompt`, `agent.send_keys` (`Escape`) e `pane.agent_status_changed` durante um turno. Registrar a sequência de status de um turno completo.
  4. Testar `agent.start` uma vez e registrar se ele aceita argumentos para o `claude`. Sem argumentos, a sessão abre com as configs globais do João (inclusive o moshi-hook, que manda notificação pro Moshi dele). Isso é tolerado só no laboratório.
  5. Descobrir se há evento de mudança de `agent_session` ou se é preciso reconsultar, e se uma tab com panes divididos pode ter dois agentes.
  6. Confirmar quais eventos globais de §3.1.3 aceitam inscrição sem `pane_id`.
- **Aceite**:
  - [ ] `S2.md` com o protocolo exato (exemplos de requisição e resposta), a lista de eventos com os payloads, a sequência de status de um turno e a estratégia de inscrição por pane.
  - [ ] Fixtures em `Fixtures/herdr/`.
  - [ ] Nenhum input enviado fora do `mocha-lab-S2`.

### S3: aprovações e perguntas

- **Dono**: `docs/spikes/S3.md`, `MochaKit/Fixtures/hooks/`, laboratório `mocha-lab-S3`.
- **Depende de**: WP0.1. Usa um servidor HTTP de teste qualquer. Não depende do WP0.3: um script `nc`/Swift simples basta.
- **SPEC a atualizar**: §3.3, §8.
- **Faz**:
  1. Com uma sessão de teste (regras de segurança acima), registrar os payloads reais de `SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest` e `PreToolUse` como fixtures. Confirmar a interpolação de `$HERDR_PANE_ID` no header com `allowedEnvVars`, o campo `last_assistant_message` no `Stop` e o respeito ao `timeout` configurado.
  2. **Permissão**: com o `PermissionRequest` HTTP segurado, verificar se o diálogo aparece no terminal em paralelo, se a primeira resposta vence dos dois lados, e o formato de allow/deny. Registrar também a sequência de teclas do diálogo para o fallback.
  3. **Pergunta**: testar o mecanismo A (`PreToolUse` + `updatedInput.answers`, com uma e com várias perguntas, múltipla escolha e "Outro") e o B (`send_keys` no seletor), registrando o formato de `answers` que funciona e as sequências de teclas.
  4. Recomendar um mecanismo por tipo, pelo critério de §8.2.
- **Notas do S1 e do S2**: com diálogo de permissão, o `tool_use` já está no transcript enquanto o Herdr mostra `blocked`. Com AskUserQuestion, a gravação do `tool_use` atrasou até a resposta numa de duas execuções, e numa execução o Herdr não passou por `blocked`: nem o transcript nem só o status do Herdr detectam pergunta pendente. O diálogo de confiança da pasta também é `blocked` (opção padrão "No, exit"), o de permissão abre com "1. Yes" selecionado, e `agent.send_keys` aceita `Escape`/`esc`, `enter` e `down`.
- **Aceite**:
  - [ ] `S3.md` com a decisão por tipo, os JSONs exatos de resposta e as sequências de teclas.
  - [ ] Seção "Impacto" com o texto novo da §8 da SPEC, pronto para o orquestrador aplicar.
  - [ ] Nenhuma alteração em `~/.claude/settings.json`.

### S4: APNs e Live Activity saindo do Mac

- **Dono**: `docs/spikes/S4.md`, `MochaKit/Sources/MochaDaemonCore/Push/`, `MochaKit/Sources/mochad/` (subcomandos `apns`), `Widgets/`, `App/Sources/Notifications/`, `App/Sources/LiveActivity/`, `App/Sources/Debug/PushProbe*`. O código do S4 é protótipo que o WP-M6 e o WP-I9 evoluem.
- **Depende de**: WP0.1, WP0.2, B1, B2, B3.
- **SPEC a atualizar**: §7.
- **Faz**:
  1. `mochad apns import`/`apns test` mínimos: JWT com CryptoKit e envio HTTP/2 para o sandbox. Alerta recebido no iPhone com build do Xcode. Como o `devices.json` só existe a partir da 1a-core, o `apns test` do spike aceita `--token <hex> --env sandbox`; o app mostra o token numa sonda de debug (`-probe push`), nunca no log.
  2. Live Activity mínima no widget: iniciar pelo app, atualizar por push, encerrar por push, e iniciar por push-to-start com o app encerrado.
  3. Medir o atraso de entrega e confirmar os headers e o comportamento das prioridades 5 e 10.
  4. Confirmar como o app descobre o `env` (sandbox ou produção).
- **Aceite**:
  - [ ] `S4.md` com os comandos, payloads e headers que funcionaram, e fotos ou vídeo de tela do iPhone (pedidos ao João).
  - [ ] Seção "Impacto" com o texto novo da §7 da SPEC, pronto para o orquestrador aplicar.

### S5: gateway, `tailscale serve` e reconexão

- **Dono**: `docs/spikes/S5.md`, `MochaKit/Sources/MochaDaemonCore/Gateway/` (protótipo), `MochaKit/Sources/mochad/` (subcomando temporário `spike-gateway`, removido no WP-M3), `App/Sources/Debug/GatewayProbe*`.
- **Depende de**: WP0.1, WP0.3, B4 (autorização). A parte no iPhone também precisa de B1 e B3; sem eles, o S5 testa no simulador e o teste no iPhone fica para o WP-X1.
- **SPEC a atualizar**: §4.5.
- **Faz**:
  1. Servir `/v1/health` e um WS de eco (com o `HttpServer` do WP0.3) atrás de `tailscale serve --bg --https=443`, testando os alvos `unix:<socket>` e `http://127.0.0.1:47421`. Confirmar que os headers (`Authorization`) chegam, se a query string é descartada, e se o Tailscale standalone consegue abrir o socket em `~/Library/Application Support/Mocha/`.
  2. Cliente de teste iOS (simulador e iPhone) com `URLSessionWebSocketTask`: conexão, envio, queda de Wi-Fi/4G e retorno, e ida e volta de background.
  3. Confirmar que um `POST` com corpo (como o futuro `/v1/upload`) passa pelo `tailscale serve` com `Content-Length`: se o proxy repassar em chunked, o `HttpServer` responde 411 (§4.4).
  4. Registrar o comando final do `serve-setup` e como desfazê-lo (`tailscale serve reset` só se não houver outras configs; hoje não há nenhuma).
- **Aceite**:
  - [ ] `S5.md` com o alvo escolhido, os comandos, as latências medidas e o comportamento de reconexão.
  - [ ] Seção "Impacto" com o texto novo da §4.5 da SPEC, pronto para o orquestrador aplicar.

---

## Fase 1a-core: uso diário mínimo

**Ondas**
- **Onda 1.0**: o orquestrador, em `fase/1a-core`: SPEC, PLANO, `AGENTS.md` e config (`Package.swift`, `project.yml`, `App/Info.plist` e scripts de build). Depois, WP-D1.
- **Onda 1.A**, em paralelo: WP-M1 · WP-M2 · WP-I1 (Fase A). O João reprovou o visual da Fase A no iPhone e pediu o desenho completo: o mock aprovado (`docs/design/mock.html`) e o escopo B (Home, Uso, sessões arquivadas) replanejaram o resto da fase.
- **Passo 1** (orquestrador): contratos do escopo B na SPEC, neste plano, no `AGENTS.md`, no `MochaProtocol` e nas fixtures.
- **Onda 1.A'**, em paralelo: WP-D2 · WP-M2b · WP-I1 (Fase B, pelo mock).
- **Onda 1.B**, em paralelo: WP-M3 · WP-I12 · WP-I4.
- **Onda 1.C**, em paralelo: WP-M4 · WP-I3 · WP-I5.
- **Onda 1.D**, em paralelo: WP-I2 · WP-M10.
- **Onda 1.E**: WP-X1 (integração).
- **Onda 1.F**, em paralelo, pedida pelo João durante o X1: WP-M11 · WP-I13 (mandar imagem, antes na 1b). Depois do merge, o `mochad` é reinstalado e o app reinstalado no iPhone; o checklist do X1 ganha o item da imagem.

Todos os WPs rodam em worktree (§Como o orquestrador trabalha). Os testes de cada WP ficam em `MochaKit/Tests/<Target>Tests/<Área>/`, sob o mesmo dono.

### WP-D1: demo dinâmico

- **Dono**: `MochaKit/Sources/MochaDemo/` e `MochaKit/Tests/MochaDemoTests/`. Nesta onda, também `MochaKit/Sources/MochaProtocol/ServerConnection.swift`, os arquivos novos `ConnectionState.swift` e `PairingLink.swift` em `MochaKit/Sources/MochaProtocol/` e um arquivo de teste novo em `MochaKit/Tests/MochaProtocolTests/`.
- **Depende de**: WP0.2.
- **SPEC**: §6.1, §5.3, §5.3.1.
- **Faz**:
  1. Escreve em `MochaProtocol` o contrato de conexão da §6.1: `ConnectionState`, `ConnectionProblem`, `PairingLink`, `ServerConnectionError` e o protocolo `ServerConnection` com `states`, `start`/`stop`/`pair` e `send(_:id:)`.
  2. O `DemoServerConnection` implementa esse contrato: estados, `hello` feito pela própria conexão e ids gerados pelo app.
  3. Eco do prompt com atraso, para a bolha "enviando" aparecer (§6.3).
  4. Mudança de status que mexe na árvore e emite `agentStatus` e `treeChanged`.
  5. Roteiro `-demo-script` (§2.2): worktree novo, troca de sessão, `chatAppend` contínuo, `toolCall` de `running` para `succeeded`, `chatMeta`, troca de id por `pane_moved` e queda e volta da conexão.
  6. Um chat de 2.000 itens gerado em código, para a medição do WP-I5.
  7. `openChat` no agente do codex → `invalidPayload` (§5.3.1).
- **Aceite**:
  - [ ] Testes do roteiro `-demo-script`, passo a passo, em `MochaDemoTests`.
  - [ ] Sem o argumento, o demo continua igual: os testes atuais de `MochaDemoTests` passam, adaptados só ao contrato novo.
  - [ ] Teste do `PairingLink` (§6.1) no arquivo novo de `MochaProtocolTests`.
  - [ ] Compila para iOS e macOS (`scripts/test.sh` e `scripts/build-app.sh`).

### WP-M1: `HerdrClient` e `HerdrBridge`

- **Dono**: `MochaKit/Sources/MochaHerdr/`, `MochaKit/Sources/MochaDaemonCore/Herdr/`, `MochaKit/Sources/MochaTestSupport/Herdr/`, as fixtures sintéticas novas em `MochaKit/Fixtures/herdr/` (`*.synthetic.json`) e os testes correspondentes (`MochaKit/Tests/MochaHerdrTests/` e `MochaKit/Tests/MochaDaemonCoreTests/Herdr/`).
- **Depende de**: WP0.2, S2.
- **SPEC**: §3.1, §4.1, §4.1.1.
- **Faz**:
  1. Cliente com uma conexão por requisição (NDJSON, o servidor fecha depois de responder) e conexões de eventos só de leitura (uma global e uma por pane com agente); `ping` com checagem do protocolo 22; bootstrap e reconexão por `session.snapshot` (inscrever → ack → snapshot → aplicar eventos guardados).
  2. Árvore reconciliada por snapshot com debounce (§3.1.3), com `HEAD` do git lido direto e `isDirty` com cache, por `git --no-optional-locks` (§3.1.4); detecção de troca de sessão sem evento (§3.1.3); mapa de `pane_moved`; comandos `prompt`/`interrupt`.
  3. O `HerdrBridge` implementa `HerdrBridging` (§4.1.1), inclusive o `serverInfo` com a versão e o protocolo do último `ping`, para o `status` e o `doctor`.
  4. Entrega o `FakeHerdrBridge` em `MochaTestSupport/Herdr/` (§4.1.1), usado pelo WP-M3.
  5. Fixtures sintéticas novas (`*.synthetic.json`) para o que o S2 não registrou, como um `session.snapshot` com worktree ligado.
- **Aceite**:
  - [ ] Testes com um servidor de socket falso que reproduz as fixtures do S2: árvore correta, aninhamento de worktree ligado (pela fixture sintética de `session.snapshot`), status por pane, reconexão depois de o socket cair.
  - [ ] O servidor falso reproduz o Herdr real: fecha depois de uma resposta, devolve `id: ""` em `invalid_request`, fecha a conexão de inscrição se o cliente escrever depois do ack, e toca os `stream.*.jsonl`.
  - [ ] Teste: `tab_closed` e `pane_exited` sem `pane_closed` removem os panes (via snapshot) e fecham as inscrições deles.
  - [ ] Teste: `agent_session` que muda sem evento é detectada: `pane_updated` com a sessão antiga seguido de `agent.get` com a nova (reconsulta com atraso), e pela reconciliação por `agent.list` (§3.1.3).
  - [ ] Teste de contrato: todo método e parâmetro enviado existe em `Fixtures/herdr/herdr-api.schema.json`.
  - [ ] Teste: protocolo ≠ 22 no `ping` gera o aviso sem derrubar o daemon.
  - [ ] Testes do `HerdrBridging`: `events()` com vários assinantes, cada um começando pelo `.snapshot` do estado atual (árvore e disponibilidade); `resolve` pelo mapa do `pane_moved`; `setOpenChats` alimentando a reconciliação (c).
  - [ ] `FakeHerdrBridge` com teste próprio.
  - [ ] Teste: o `isDirty` roda `git --no-optional-locks … status` (§3.1.4).
  - [ ] Teste `.integration` (só com `MOCHA_INTEGRATION=1`) lendo o Herdr real sem enviar input: só `ping`, `session.snapshot`, `agent.list` e uma inscrição global.

### WP-M2: parser e `TranscriptStore`

- **Dono**: `MochaKit/Sources/MochaTranscript/`, `MochaKit/Sources/MochaDaemonCore/Transcript/`, `MochaKit/Sources/MochaTestSupport/Transcript/`, `MochaKit/Fixtures/transcripts/expected/` e os testes (`MochaKit/Tests/MochaTranscriptTests/` e `MochaKit/Tests/MochaDaemonCoreTests/Transcript/`).
- **Depende de**: WP0.2, S1.
- **SPEC**: §3.2, §4.1.1, §5.4.
- **Faz**:
  1. Parser de linha → itens (§3.2.2), com resolução de `tool_result` em `toolCall`, índice de offsets, página pelo fim, cursor `<sessionId>:<offset>` (§3.2.3), acompanhamento com `DispatchSource` e buffer de linha incompleta, troca de sessão.
  2. O `TranscriptStore` implementa `TranscriptProviding` (§4.1.1): `open` atômico com contagem de referência por assinante, `page`, `meta(forSession:)` e `stats(forSession:)`.
  3. Entrega o `FakeTranscriptProvider` em `MochaTestSupport/Transcript/` (§4.1.1), usado pelo WP-M3.
  4. Roda as fixtures e os transcripts reais de `~/.claude/projects` e propõe no relatório o diff da §3.2.2 (título e política, item 3) com a versão instalada do Claude Code como a última validada. Os transcripts reais são lidos só para contar tipos e ver a versão: nenhum conteúdo vai para fixture ou relatório.
- **Aceite**:
  - [ ] Cada fixture do S1, inclusive `subagents.jsonl` com o diretório `subagents/`, gera o snapshot de `Fixtures/transcripts/expected/<fixture>.json` no formato `{"meta":{"title","model","branch","permissionMode"},"items":[…],"stats":{"dropped","orphanResults","unknown":{"<nome>":n}}}`, com os itens no estado final, e a sequência de tipos bate com a coluna "Itens esperados" do README das fixtures. Os snapshots são gerados com `MOCHA_UPDATE_SNAPSHOTS=1 swift test --filter TranscriptSnapshotTests`, revisados item a item contra a §3.2.2 antes do commit, e o teste normal compara estruturas, não bytes.
  - [ ] A fixture de 50 MB (`Fixtures/transcripts/generated/big-50mb.jsonl`, de `swift scripts/gen-big-transcript.swift`) responde a primeira página em < 300 ms, medida em release (`swift test -c release`) numa janela sem build (teste `.integration`; sem o arquivo, falha com a instrução de gerar).
  - [ ] Append simulado (escrever no arquivo durante o teste) gera `chatAppend`/`chatUpdate` em < 300 ms.
  - [ ] `malformed.jsonl` termina com 2 linhas descartadas, 1 linha parcial pendente e os desconhecidos listados no README, sem derrubar a sessão.
  - [ ] Escrever `clear-and-compact.jsonl` e `tool-calls.jsonl` em pedaços, cortando linhas ao meio, gera a mesma lista final da leitura inteira, com os `chatAppend`/`chatUpdate` esperados.
  - [ ] Página montada no meio de `tool-calls.jsonl` aplica os `tool_result` que ficam depois dela.
  - [ ] A resolução de sessão ignora `subagents/`, `memory/` e `.jsonl` de plugins, e trata arquivo inexistente como sessão vazia.
  - [ ] Testes do `open`: linhas gravadas entre a leitura da página e a inscrição chegam uma vez só, sem perda nem duplicação; dois assinantes na mesma sessão recebem os mesmos deltas, e cancelar um não afeta o outro.
  - [ ] Cursor inválido ou de outra sessão lança `TranscriptError.invalidCursor`.
  - [ ] `FakeTranscriptProvider` com teste próprio.
  - [ ] Diff da §3.2.2 com a versão instalada no relatório, que traz só contagens de tipos e a versão.

### WP-D2: demo da Home e do escopo B

- **Dono**: `MochaKit/Sources/MochaDemo/` e `MochaKit/Tests/MochaDemoTests/`.
- **Depende de**: WP-D1, Passo 1 (contratos do escopo B).
- **SPEC**: §3.4, §4.9, §5.2, §5.3, §5.3.1, §6.1 (argumentos de launch), §6.3.
- **Faz**:
  1. Troca os dados do demo pelos do mock (`docs/design/mock.html`): os workspaces, tabs e agentes da gaveta (tela 11), os cards da Home (tela 2: `site-pessoal` bloqueado, `login-social` e `receitas-api` trabalhando, `demo-app` e `receitas-api` concluídos, dois arquivados), o chat de `receitas-api` das telas 5, 5b, 6 e 7, e o uso da tela 3. Os horários são relativos ao lançamento ("há 1 min", "há 6 min", "ontem"), para as capturas baterem com o mock.
  2. Preenche os campos novos do `AgentSummary` (`preview`, `activity`, `contextLeftPercent`, `sessionStartedAt`, `turnStartedAt`, `turnEndedAt`, `archivedAt`) em todos os agentes, cobrindo as quatro seções da Home, inclusive um agente arquivado por tempo e um com `preview == nil` ("Sessão limpa").
  3. Manda `archived` (duas sessões, `cleared` e `ended`) e `usage` depois de `tree`, e `herdrStatus` no roteiro.
  4. `archive{sessionId}` → `ack` e `treeChanged` com `archivedAt`; sessão que não é atual → `sessionNotFound`.
  5. `openChat`/`closeChat` com `sessionId` das sessões arquivadas (páginas fixas) e as regras da §5.3.1 (`invalidPayload` fora do formato UUID, `sessionNotFound`).
  6. `-demo-empty`: árvore sem nenhum Claude e `archived` vazio (tela 2c).
  7. Roteiro `-demo-script`: acrescenta um agente saindo de `working` para `idle` com `turnEndedAt` (vai para CONCLUÍDOS), uma troca de sessão que gera uma `ArchivedSession` `cleared`, e `herdrStatus` falso e verdadeiro.
- **Aceite**:
  - [ ] Testes em `MochaDemoTests` para cada item acima, inclusive a sequência `helloOk` → `tree` → `archived` → `usage`.
  - [ ] Os testes atuais do demo passam, adaptados só aos contratos novos.
  - [ ] `scripts/test.sh` verde.

### WP-M2b: meta da Home no transcript

- **Dono**: `MochaKit/Sources/MochaTranscript/`, `MochaKit/Sources/MochaDaemonCore/Transcript/`, `MochaKit/Sources/MochaTestSupport/Transcript/`, `MochaKit/Fixtures/transcripts/expected/` e os testes (`MochaKit/Tests/MochaTranscriptTests/` e `MochaKit/Tests/MochaDaemonCoreTests/Transcript/`).
- **Depende de**: WP-M2, Passo 1.
- **SPEC**: §3.2.2 (meta da Home), §3.2.3 (meta sem acompanhamento), §3.4 (contexto), §4.1.1.
- **Faz**:
  1. `TranscriptMeta` com `preview`, `activity`, `contextTokens`, `sessionStartedAt`, `turnStartedAt` e `turnEndedAt` (§3.2.2), mantidos no estado da sessão acompanhada.
  2. `PlainText.preview(fromMarkdown:)` e `ContextWindow.size(forModel:)` em `MochaTranscript`, públicos (o M6 e o M3 usam).
  3. `meta(forSession:)` sem acompanhamento: varredura do fim até 8 MB e primeira linha, com cache por tamanho e mtime.
  4. Delta `.meta` quando qualquer campo muda (menos o `lastModified` sozinho).
  5. `FakeTranscriptProvider` com os campos novos.
  6. Snapshots de `Fixtures/transcripts/expected/` com os campos novos do meta, regenerados e revisados.
- **Aceite**:
  - [ ] Testes do `PlainText` (cada regra da §3.2.2) e do `ContextWindow`.
  - [ ] Cada fixture do S1 tem os campos novos no snapshot, conferidos à mão: `turnEndedAt` do último `turn_duration`, `turnStartedAt` ignorando `queued_command`, `contextTokens` sem sidechain nem `<synthetic>`, `activity` preferindo o `toolCall` `running`.
  - [ ] Append simulado de um `tool_use` gera `.meta` com a `activity` nova, e o `tool_result` gera outro com o status novo.
  - [ ] `meta(forSession:)` num arquivo de 50 MB sem acompanhamento em < 50 ms (teste `.integration`, release, janela sem build).
  - [ ] `scripts/test.sh` verde.

### WP-M3: gateway, `SessionHub`, pareamento e aparelhos

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Gateway/`, `Pairing/` e `Devices/`, e os testes (`MochaKit/Tests/MochaDaemonCoreTests/Gateway/`, `Pairing/` e `Devices/`). Também a remoção do `spike-gateway` em `MochaKit/Sources/mochad/`: `SpikeGatewayCommand.swift`, `SpikeGatewayLog.swift`, o caso e o texto de uso no `main.swift`, e o `TerminationSignals`, que sai de `SpikeGatewayCommand.swift` para `mochad/TerminationSignals.swift`.
- **Depende de**: WP0.2, WP0.3, S5, WP-M1 e WP-M2 (os fakes).
- **SPEC**: §3.1.3, §3.1.4, §4.1.1, §4.1.2, §4.4, §4.5, §4.6, §4.8, §5 (inclusive §5.3.1 e §5.5), §10.
- **Faz**:
  1. Rotas `/v1` e `/v1/health`, handshake `hello` com código ou token, `unpair`, `Pairing`, `DeviceStore` (relê `devices.json` antes de cada gravação, §4.8) e `SessionHub` (clientes, chats abertos, primeiro plano).
  2. Roteamento das mensagens de §5.3 da 1a-core para `HerdrBridging` e `TranscriptProviding` (§4.1.1), com as regras da §5.3.1 e a composição da §4.1.2. Os testes usam `FakeHerdrBridge` e `FakeTranscriptProvider`; o WP-M4 injeta o `HerdrBridge` e o `TranscriptStore` reais.
  3. O `herdr` do `/v1/health` vem de `HerdrBridging.isAvailable`.
  4. Expõe para o WP-M4, sem rota HTTP: emitir um código de pareamento (código, URL e validade, §4.5), listar os clientes conectados, listar as sessões acompanhadas (`sessionId` e `agentId`, para o `/local/status`) e derrubar um aparelho (fecha as conexões dele com `error{unauthorized}` e close 1008 e o tira de `devices.json`, §4.8).
  5. Parte do protótipo `MochaDaemonCore/Gateway/` do S5 (`Gateway.makeRouter()`, `GatewayHealth`, `GatewayEvent`, `HttpResponse.json`). Troca o eco do `/v1` pelo `SessionHub` e apaga `GatewaySpikeRoutes.swift` (`/spike/echo`, `GatewaySpikeEcho`) e os três testes do eco em `Tests/MochaDaemonCoreTests/Gateway/GatewayTests.swift`: `webSocketEchoesAndReportsLifecycle`, `spikeRoutesAreOptIn` e `spikeEchoReportsQueryHeadersAndBody`.
  6. Apaga o subcomando `spike-gateway` do `mochad`, que depende do eco, com o texto de uso dele no `main.swift`, e move o `TerminationSignals` para `mochad/TerminationSignals.swift`, para o `mochad run` do WP-M4.
  7. Binding só `.loopback(port: 47421)`. No encerramento, fecha cada WebSocket com 1001 antes do `HttpServer.stop()`, que hoje corta sem close frame (o app vê POSIX 57).
  8. Contratos do escopo B no `SessionHub`: `ChatTarget` em `openChat`/`closeChat` e nos eventos de chat, com o chat por `sessionId` (§5.3.1, `sessionNotFound`); `herdrStatus`; a composição nova da §4.1.2 com os campos do `TranscriptMeta` (`preview`, `activity`, horários) e o `contextLeftPercent` pelo `contextTokens` e pelo `ContextWindow` (o `UsageProviding` e o `SessionArchiving` entram no WP-M10); e a Home ao vivo (inscrição nos agentes `working`/`blocked`, solta 30 s depois de saírem desses estados). `archive` responde `unknownType` até o WP-M10.
- **Aceite**:
  - [ ] Teste de ponta a ponta com um cliente WS de teste, com `FakeHerdrBridge` e `FakeTranscriptProvider`: pareamento → token → reconexão com token → `tree` → `openChat` → `chatAppend`.
  - [ ] Token errado → `unauthorized`; três falhas, contando o `hello` recusado → close 1008. Primeira mensagem que não é `hello` → `unauthorized` e close 1008.
  - [ ] Um teste por regra da §5.3.1, inclusive a tabela de erros do Herdr.
  - [ ] Testes da composição da §4.1.2: título, modelo e branch; agregado de status; `agentStatus` na hora e `treeChanged` com debounce; `chatMeta` só quando o meta muda; troca de sessão; id antigo traduzido depois de `pane_moved`; Herdr indisponível (última árvore e `herdrUnavailable`).
  - [ ] `devices.json` com permissão 0600 e só com o hash do token.
  - [ ] `/v1/health` devolve `herdr` de `HerdrBridging.isAvailable`, com o fake disponível e indisponível.
  - [ ] Testes das APIs para o WP-M4: o código vale uma vez por 10 min, as listas refletem as conexões abertas e os chats acompanhados, e derrubar um aparelho fecha as conexões dele com 1008 e o tira de `devices.json`.
  - [ ] Testes do escopo B: `openChat` por `sessionId` (página, eventos com o mesmo `sessionId`, UUID inválido, arquivo inexistente), `herdrStatus` nas mudanças de disponibilidade, `treeChanged` quando muda a `preview` ou a `activity` de um agente sem chat aberto, inscrição de Home ao vivo aberta em `working` e solta 30 s depois de `idle`, `contextLeftPercent` pelo `contextTokens`.
  - [ ] `rg -n -i spike MochaKit/` sem resultado.

### WP-M4: `mochad`: composição, CLI, LaunchAgent e `doctor`

- **Dono**: `MochaKit/Sources/mochad/`, `MochaKit/Sources/MochaDaemonCore/App/`, `MochaKit/Sources/MochaDaemonCore/Admin/` (canal local da §4.8 e cliente da CLI sobre `NWConnection` unix), `MochaKit/Tests/MochaDaemonCoreTests/App/`, `MochaKit/Tests/MochaDaemonCoreTests/Admin/` e `scripts/build-daemon.sh`.
- **Depende de**: WP-M1, WP-M2, WP-M3.
- **SPEC**: §3.1.1, §3.2.2, §3.3, §4.2, §4.3, §4.5, §4.6, §4.7, §4.8, §7.1, §10.
- **Faz**:
  1. Liga os componentes reais (`HerdrBridge`, `TranscriptStore`, `SessionHub` e `Gateway`) e implementa os comandos da 1a-core: `run`, `install`, `uninstall`, `pair`, `devices`, `serve-setup`, `status` e `doctor`. O `spike-gateway` já saiu no WP-M3; resta confirmar que não sobrou nada dele.
  2. Canal local (§4.8): o `LocalControl` no socket Unix `mochad.sock` (0600), com as rotas `/local/*` sobre as APIs do WP-M3, e o cliente da CLI sobre `NWConnection` com `NWEndpoint.unix(path:)`.
  3. `pair` pede o código pelo canal local e renderiza o QR (§4.5). `status` e `devices` seguem a §4.2, com e sem daemon.
  4. `config.json` com `hookSecret` (§4.3): todo gravador preserva as chaves desconhecidas, a gravação é atômica, e nesta fase só `install` e `run` geram o `hookSecret`.
  5. `run` falha com mensagem clara quando a porta está em uso (`EADDRINUSE`).
  6. `doctor` (§4.2): item Transcript pelo `/local/status`, comparando com a última versão validada da §3.2.2 (2.1.283), guardada numa constante; hooks mostrados como "chegam na 1a-final"; moshi-hook detectado lendo `~/.claude/settings.json`, só em leitura (§3.3.2).
  7. Serve: o `serve-setup` mostra `tailscale serve --bg --https=443 http://127.0.0.1:47421`. `--apply` executa, confere `tailscale serve status --json` (handler `"/"` em `"<host>:443"` com `"Proxy": "http://127.0.0.1:47421"`) e aquece com `GET https://<host>/v1/health` (limite de 90 s). `--remove` executa `tailscale serve --https=443 off`. O Tailscale é chamado pelo caminho absoluto `/Applications/Tailscale.app/Contents/MacOS/tailscale` (o `/usr/local/bin/tailscale` é só um wrapper), sem depender do `PATH` do LaunchAgent. O host vem de `tailscale status --json` → `.Self.DNSName` sem o ponto final, e também dá a URL do WS que o `Pairing` põe no link (§4.5). `doctor`, item Serve: ✅ com o handler certo e o health 200 pela URL `https://<host>`; ❌ sem handler (mostra o comando), com alvo `unix:` ("a extensão do Tailscale não abre socket Unix") ou com 502 ("Serve ativo, gateway sem escutar"); ⚠️ com timeout no TLS ("certificado sendo emitido; tente de novo em 1 min").
  8. Do S4: `scripts/build-daemon.sh` e `mochad install` assinam o binário com a identidade "Apple Development" do time: `codesign --force --sign <identidade> --identifier com.joaoalves.mochad --options runtime`. A identidade vem de `security find-identity -v -p codesigning`, filtrada pelo certificado cujo OU é o `DEVELOPMENT_TEAM` de `Config/Signing.xcconfig`; sem ela, avisa que o Keychain vai pedir autorização. `doctor`, item APNs: config presente; binário assinado pelo time (`codesign -dr -` com `identifier "com.joaoalves.mochad"`); item do Keychain presente (`SecItemCopyMatching` sem `kSecReturnData`, sem ler o segredo).
- **Aceite**:
  - [ ] Na ordem: `mochad install` sobe o LaunchAgent → `launchctl print gui/$UID/com.joaoalves.mochad` mostra o serviço rodando → `mochad uninstall` → `mochad run` parado por ~10 min numa tab do Herdr, com RSS < 30 MB (medido com `footprint` ou `ps`, numa janela sem build). A tab fecha antes do WP-X1.
  - [ ] `mochad run` com a porta em uso sai com mensagem clara (`EADDRINUSE`).
  - [ ] `mochad doctor` lista os itens de §4.2 com o estado real, incluindo a versão e o protocolo do `ping` do Herdr (❌ se o socket não existir, ⚠️ se protocolo ≠ 22), o item Transcript, os hooks como "chegam na 1a-final" e o moshi-hook detectado.
  - [ ] `doctor` distingue sem handler, alvo `unix:`, 502 e timeout de TLS, em testes com runner de processo e HTTP falsos.
  - [ ] `mochad pair`: um teste rasteriza o texto do QR impresso no terminal e o decodifica com CoreImage, voltando ao mesmo `PairingLink`. A leitura pela câmera do iPhone fica no WP-X1.
  - [ ] Sem daemon, `status` e `doctor` mostram "mochad parado" e saem com código ≠ 0, e `devices --remove` edita o arquivo direto.
  - [ ] Teste do `config.json`: gravar preserva as chaves desconhecidas, é atômico e mantém 0600.
  - [ ] `apns test`: recompilar com `build-daemon.sh` → `mochad install` → `mochad apns test --token <hex falso> --env sandbox` com timeout. Passa se nenhum diálogo do Keychain aparecer (o APNs responde `BadDeviceToken`).

### WP-I1: design system, shell do app e modo demo (Fase B pelo mock)

- **Dono**: `App/Sources/DesignSystem/`, `App/Sources/AppShell/`, `App/Resources/`, `App/Sources/Debug/DesignSystemPreview*`, `MochaKit/Sources/MochaClient/Presentation/` com `MochaKit/Tests/MochaClientTests/Presentation/`, e as telas de encaixe: `App/Sources/Home/HomeScreen.swift` (`HomeScreen(session:)`), `App/Sources/AgentDetail/AgentDetailSheet.swift` (`AgentDetailSheet(session:, target: ChatTarget)`), `App/Sources/Usage/UsageSheet.swift` (`UsageSheet(session:)`), `App/Sources/Settings/SettingsScreen.swift` (`SettingsScreen(session:)`), `App/Sources/Pairing/PairingScreen.swift` (`PairingScreen(session:)`), `App/Sources/Drawer/DrawerScreen.swift` (`DrawerScreen(session:)`), `App/Sources/Chat/ChatScreen.swift` (`ChatScreen(session:, target: ChatTarget)`), `App/Sources/Markdown/MarkdownView.swift` (`MarkdownView(markdown:)`) e `App/Sources/Debug/MarkdownPreviewScreen.swift` (`MarkdownPreviewScreen()`), que o I12, o I2, o I3, o I5 e o I4 substituem.
- **Depende de**: WP0.1, WP0.2, WP-D1, Passo 1. A Fase A (commits `d09483f`, `fd07098`, `cab25c6`, `1941ba0`) já está em `wp/I1`.
- **SPEC**: §2.2, §6.1, §6.2, §6.3.
- **Faz**:
  1. Descarta a navegação gaveta-sobre-chat da Fase A (`MainShellView`, `WorkspaceTree`).
  2. `AppSession` completo (§6.1): árvore, `archived`, `usage`, `herdrConnected`, estado da conexão, chat visível por `ChatTarget`, correlação por id, reabertura do chat ao reconectar, troca de id por `sessionId` e a navegação: Home como raiz de um `NavigationStack`, chat por push, voltar pela borda (o gesto padrão do `NavigationStack`) e pelo disco de status, gaveta como camada sem gesto de borda, folhas de Detalhe, Uso e Ajustes, e Pareamento cobrindo tudo em `pairingRequired`. Ações para os WPs de tela: `openChat(target)`, `closeChat`, `openDrawer`, `closeDrawer`, `showDetail(target)`, `showUsage`, `showSettings`, `archive(sessionId)`, `sendPrompt`, `interrupt`, carregar página anterior.
  3. Design system pelo mock (§6.2): todas as cores e vidros, o brilho da Home, a tipografia, e os componentes base: botão redondo de vidro (variantes chat, Home, hero e black), header do chat, composer recolhido e expandido (sem a lógica de envio), card de ferramenta (fechado e expandido), bolha, disco de status, anel de contexto (com o giro de `working`), selo (verde e âmbar), cabeçalho de seção, card da Home (moldura), barra de uso com traço de ritmo, alça de folha, linha de lista de folha e chip de slash.
  4. `DesignSystemPreview` (só em Debug) com todos os componentes, e `-preview-section <seção>`.
  5. `MochaClient/Presentation/`: abreviação do modelo, nome de exibição da ferramenta (`Bash` → "Shell"), tempo relativo ("agora", "há N min", "há N h", "ontem", "há N dias") e duração do turno ("3m 58s"), com testes.
  6. Deep links pelo `AppSession` (`mocha://agent/<paneId>` por cima da Home; `mocha://pair`), e o argumento `-open-url <url>` (só em Debug). `-demo-empty` repassado ao demo.
  7. Encaixes: cada tela de encaixe mostra o nome dela e os dados mínimos (a Home lista os títulos dos agentes com toque abrindo o chat), para a navegação ser testável ponta a ponta antes dos WPs de tela.
- **Aceite**:
  - [ ] Capturas da `DesignSystemPreview` no simulador (iPhone 17e, `-preview-section` por componente), comparadas com os mesmos componentes nas capturas de `docs/design/mock/`, com as diferenças listadas e corrigidas até ficarem só as ditadas pelo conteúdo.
  - [ ] Cores exatamente as da §6.2.
  - [ ] Com o esquema `Mocha Demo`, o app abre na Home de encaixe sobre o `DemoServerConnection`; tocar num agente empurra o chat de encaixe; voltar pela borda e pelo disco funciona (conferido no simulador por captura antes e depois).
  - [ ] `-open-url mocha://agent/<paneId>` abre o chat certo por cima da Home; `-open-url mocha://pair?…` inicia o pareamento.
  - [ ] Com um `probe` gravado no `UserDefaults` e sem `-probe` nos argumentos, nenhuma sonda abre.
  - [ ] Testes de `MochaClient/Presentation/` verdes; `scripts/test.sh` e `scripts/build-app.sh` verdes.
  - [ ] No aparelho (checklist do WP-X1): arrastar da borda volta à Home.

### WP-I12: Home, Detalhe do agente e Uso

- **Dono**: `App/Sources/Home/`, `App/Sources/AgentDetail/` e `App/Sources/Usage/` (substituem os encaixes do WP-I1), e os arquivos novos `HomeSections.swift` e `UsagePace.swift` em `MochaKit/Sources/MochaClient/Presentation/` com os testes em `MochaKit/Tests/MochaClientTests/Presentation/`. Não toca em `AppShell/` nem em `DesignSystem/`: mudanças neles vão como diff no relatório.
- **Depende de**: WP-I1, WP-D2.
- **SPEC**: §3.4, §6.2, §6.3 (Home, Uso do plano, Detalhe do agente).
- **Faz**: Home com as quatro seções pela regra da §6.3 (reavaliada a cada 30 s), cards com anel, prévia, ferramenta e metadados, arrastar para arquivar em CONCLUÍDOS, segurar para o Detalhe, pílula de uso, estados sem conexão e vazio; folha de Uso com barras, ritmo e "atualizado há X"; folha de Detalhe com o bloco principal, os selos, o cartão Conta, a lista e a cópia do id da sessão.
- **Aceite**:
  - [ ] `HomeSections` e `UsagePace` com testes de cada regra (precedência, 10 min, 6 h, `archivedAt`, `ArchivedSession`, filtro `kind`, ordem; ritmo com a tolerância de 5 pontos e o tempo até zerar).
  - [ ] Capturas no simulador (iPhone 17e, `simctl status_bar … override --time 9:41`) comparadas com `02-home`, `02b-home-sem-conexao`, `02c-home-vazia`, `03-uso-plano`, `04-detalhe-agente` e `04b-detalhe-precisa-de-voce`, com as diferenças listadas e corrigidas até ficarem só as ditadas pelo conteúdo.
  - [ ] Com `-demo-script`, um agente que termina o turno passa de TRABALHANDO para CONCLUÍDOS sem recarregar; arrastar um card de CONCLUÍDOS o leva para ARQUIVADOS.
  - [ ] Tocar num card de sessão arquivada abre o chat por `sessionId`.

### WP-I4: renderizador de markdown

- **Dono**: `App/Sources/Markdown/` e `App/Sources/Debug/MarkdownPreview*` (substituem os encaixes `MarkdownView` e `MarkdownPreviewScreen` do WP-I1).
- **Depende de**: WP-I1 (tokens e encaixe).
- **SPEC**: §11 (lista de elementos), §6.2, §6.3 (Chat).
- **Faz**: AST do `swift-markdown` → views SwiftUI em JetBrains Mono, com seleção de texto nos parágrafos, código inline em `link`, blocos de código com rolagem horizontal (borda esmaecida e barrinha indicando que há mais à direita), listas aninhadas, títulos, citações, links e tabelas com borda `tableBorder` e rolagem horizontal, como na tela `05b-chat-fim-turno`.
- **Aceite**:
  - [ ] `MarkdownPreviewScreen` (só em Debug) com um documento de teste cobrindo todos os elementos, capturada no simulador; o trecho do turno da tela 5b reproduzido nela e comparado com `05b-chat-fim-turno`.
  - [ ] Layout só dos blocos visíveis de uma mensagem de 20 KB, na lista preguiçosa do chat (WP-I5, cada bloco de nível superior é uma linha), abaixo de 16 ms no simulador, medido com `signpost` numa janela sem build. A mensagem inteira de uma vez mede ~131 ms em Debug e não é o critério (decisão do João, 2026-09-26).

### WP-I3: gaveta

- **Dono**: `App/Sources/Drawer/` (substitui o encaixe `DrawerScreen` do WP-I1). Não toca em `AppShell/`.
- **Depende de**: WP-I1, WP-D2.
- **SPEC**: §6.2, §6.3 (Gaveta), §3.1.4, §5.3.
- **Faz**: busca nas duas abas, Recentes/Árvore, aninhamento de worktree, estados (pulso com brilho, ponto âmbar), linha do chat aberto, engrenagem para Ajustes, fechar pelo scrim e arrastando para a esquerda, fechar o teclado ao abrir, e tocar num agente abre o chat pela navegação do `AppSession`. Sem gesto de borda para abrir.
- **Aceite**:
  - [ ] Capturas no simulador comparadas com `11-gaveta-arvore` e `11b-gaveta-recentes`.
  - [ ] A busca filtra workspace, tab e título.
  - [ ] Com `-demo-script`, o `treeChanged` com um worktree novo aparece aninhado sem recarregar a tela.

### WP-I5: chat e composer

- **Dono**: `App/Sources/Chat/` (substitui o encaixe `ChatScreen` do WP-I1), `App/Sources/Composer/` e os arquivos novos `ToolGrouping.swift` e `PendingBubbles.swift` em `MochaKit/Sources/MochaClient/Presentation/`, com testes. Não toca em `AppShell/` nem em `DesignSystem/`.
- **Depende de**: WP-I1, WP-I4, WP-D2.
- **SPEC**: §2.3, §5.3, §5.4, §6.2, §6.3 (Chat, Composer).
- **Faz**: lista com todos os tipos de item, agrupamento de ferramentas consecutivas, expansão com caixa interna, paginação para cima mantendo a posição, grudar no fim, botão ↓, linha de status "Trabalhando… (Xm Ys)" com o botão de parar, bolha "enviando" pela regra da §6.3, composer de uma linha que expande ao focar (até 6 linhas e a linha de botões), regras de fechar o teclado, rascunho na linha recolhida, chat só de leitura de sessão arquivada, header com toque no título para o Detalhe e no disco para voltar, e `setForeground` do chat visível (ao abrir, trocar e fechar o chat).
- **Aceite**:
  - [ ] Testes de `ToolGrouping` e `PendingBubbles` (FIFO, texto aparado, `slashCommand` para `/x` e `!cmd`, 60 s).
  - [ ] Capturas no modo demo comparadas com `05-chat-inicio-turno`, `05b-chat-fim-turno`, `06-card-expandido`, `07-chat-trabalhando` e `08-chat-digitando`.
  - [ ] Chat de 2.000 itens do WP-D1 no simulador, medido com `signpost` numa janela sem build: nenhum layout acima de 16 ms. Os 60 fps no iPhone 14 ficam no checklist do WP-X1.
  - [ ] Paginação sem salto visível.
  - [ ] Com o eco atrasado do demo, a bolha "enviando" aparece no envio e some quando o `userPrompt` casa com ela.
  - [ ] Chat de sessão arquivada sem composer e sem linha de status.

### WP-I2: conexão, pareamento e ajustes

- **Dono**: `MochaKit/Sources/MochaClient/`, `MochaKit/Tests/MochaClientTests/`, `MochaKit/Sources/MochaTestSupport/Http/`, a opção `automaticPong` em `MochaKit/Sources/MochaDaemonCore/Http/` (só ela), `App/Sources/Connection/`, `App/Sources/Pairing/`, `App/Sources/Settings/`, `App/Sources/AppShell/` (`scenePhase`, troca entre demo e real, rotas de pareamento e Ajustes), `App/Sources/Debug/GatewayProbe*` (apaga) e `scripts/build-app.sh` (assinatura no simulador para o Keychain, se o erro −34018 aparecer).
- **Depende de**: WP0.2, WP0.3, S5, WP-I1, WP-D2.
- **SPEC**: §2.3 (Reconexão), §4.5, §5.1, §5.3, §5.3.1, §6.1, §6.3 (Pareamento, Ajustes).
- **Faz**:
  1. `ConnectionManager` (actor, em `MochaClient`) implementa o contrato de `ServerConnection` da §6.1 (`ConnectionState`, `ConnectionProblem`, `start`/`stop`/`pair`, `send(_:id:)` e o `hello` feito pela conexão), com backoff e `TokenStore` injetado, sempre com um `receive()` pendente no `URLSessionWebSocketTask` (sem ele, o pong do `sendPing` e o close do servidor não são processados; WP0.3).
  2. Backoff, tentativa imediata em `.satisfied`, heartbeat `sendPing` a cada 5 s e depois de mudança de caminho, conexão morta com 15 s sem pong, nada de fechar na troca de rede e close 1001 só em `.background` (§2.3, §6.1).
  3. Decide pelo `error.code` antes do close (§5.3.1): `unauthorized` e `pairingExpired` levam ao pareamento, e o token só é apagado quando um pareamento novo dá certo ou no `unpair`. Estados: 502 no handshake → "O Mac respondeu, mas o mochad não está rodando"; timeout ou erro de conexão → "Sem conexão com o Mac" (§6.3).
  4. `KeychainTokenStore` no app; `scenePhase` com `setForeground`; telas de Pareamento (leitura de QR com `DataScannerViewController`, link colado, estados de erro) e de Ajustes (host e data do pareamento, guardada no app, estado da conexão, validade do perfil de provisionamento, versões e desparear com confirmação) pelo mock (§6.3), substituindo os encaixes `PairingScreen` e `SettingsScreen` do WP-I1.
  5. A opção `automaticPong` no `HttpServer` (ligada por padrão), para o teste do servidor sem pong.
  6. Pendência do WP-I1: o `PairingScreen` fica atrás das folhas (`.sheet`) quando a conexão cai em `pairingRequired` com uma folha aberta; o Pareamento precisa cobrir tudo (§6.1), fechando a folha ou apresentando por cima dela.
  7. Parte da sonda `App/Sources/Debug/GatewayProbe*` do S5 (lógica movida para o `ConnectionManager` de `MochaClient`). Com a conexão real pronta, apaga `App/Sources/Debug/GatewayProbe*` e o caso `gateway` do `DebugProbe` em `AppShell/RootView.swift`.
- **Aceite**:
  - [ ] `MochaClientTests` contra um servidor WS de teste montado com o `HttpServer` (WP0.3) em `MochaTestSupport/Http/`: pareamento por código → token salvo no `TokenStore` → reconexão com token, queda do servidor e sequência de backoff.
  - [ ] Teste da sequência de backoff (limite de 8 s depois do jitter, contagem zerada ao abrir) com relógio e aleatoriedade injetados.
  - [ ] Teste do heartbeat com transporte falso: sem pong, a conexão é dada como morta em 15–20 s e reaberta.
  - [ ] Dois testes com `URLSessionWebSocketTask` real: um `ping` respondido pelo `HttpServer`, e outro contra um servidor sem pong (`automaticPong` desligado), dado como morto.
  - [ ] Testes dos estados da §6.1: `unauthorized` e `pairingExpired` → `pairingRequired` sem apagar o token; `unpair` → token apagado e `pairingRequired(nil)`; `send` fora de `.connected` → `notConnected`.
  - [ ] No simulador, com `-demo` e `-demo-unpaired`, as telas de pareamento e Ajustes aparecem e navegam; capturas comparadas com `01-pareamento`, `01c-erro-pareamento` e `12-ajustes`. O pareamento contra o `mochad` real acontece no WP-X1.
  - [ ] Ajustes mostra a validade do perfil de provisionamento quando o `embedded.mobileprovision` existe (§6.3).
  - [ ] O app manda `setForeground` nas mudanças de `scenePhase`.

### WP-M10: uso do plano e sessões arquivadas no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Usage/`, `MochaKit/Sources/MochaDaemonCore/Sessions/`, `MochaKit/Sources/MochaTestSupport/Usage/`, `MochaKit/Sources/MochaTestSupport/Sessions/`, `MochaKit/Fixtures/usage/`, os testes (`MochaKit/Tests/MochaDaemonCoreTests/Usage/` e `Sessions/`), e nesta onda também: o tratamento de `archive`, `archived` e `usage` e a origem nova do contexto em `MochaDaemonCore/Gateway/`, a ligação dos serviços novos em `MochaDaemonCore/App/`, e o item Uso do `doctor` em `MochaKit/Sources/mochad/`.
- **Depende de**: WP-M3, WP-M4, Passo 1.
- **SPEC**: §3.4, §4.1.1 (`UsageProviding`, `SessionArchiving`), §4.1.2, §4.3, §4.9, §5.3, §5.3.1.
- **Faz**:
  1. `UsageMonitor`: observa o diretório do cache do plugin (gravação por rename), lê `windows`, `fetched_at_unix` e `session_contexts`, e o plano e a conta de `~/.claude.json` (só as duas chaves da §3.4, com cache por mtime; nunca no log). Os testes usam só as fixtures sintéticas de `Fixtures/usage/` e diretórios temporários; nenhum teste nem agente lê o `~/.claude.json` real.
  2. `SessionArchive`: `sessions.json` (§4.9), retenção de 7 dias e 50 sessões, arquivamento do usuário apagado por `turnStarted`, e a sessão que volta (`--resume`) saindo da lista.
  3. `FakeUsageProvider` e `FakeSessionArchive` em `MochaTestSupport/`.
  4. No `SessionHub`: `contextLeftPercent` primeiro pelo `UsageProviding`; `archivedAt` pelo `SessionArchiving`; `sessionEnded` com `cleared` na troca de sessão e com `ended` quando o agente some (não com o Herdr indisponível); `turnStarted` a cada `turnStartedAt` novo; `archive` pelas regras da §5.3.1; `archived` e `usage` depois de `tree` e a cada mudança; `workspaceLabel` do chat de sessão pela `ArchivedSession`.
  5. `mochad run` liga o `UsageMonitor` e o `SessionArchive` reais; `doctor` ganha o item Uso (§3.4).
- **Aceite**:
  - [ ] Testes do `UsageMonitor` com a fixture: janelas, `fetchedAt`, contexto por sessão, arquivo trocado por rename gerando evento, arquivo ausente ou inválido sem `usage`, plano e conta mascarada pelas regras da §3.4.
  - [ ] Testes do `SessionArchive`: gravação atômica 0600, retenção, `archive`/`turnStarted`, `--resume`.
  - [ ] Testes do `SessionHub` com os quatro fakes: sequência `helloOk` → `tree` → `archived` → `usage`; `/clear` gera `archived` com `cleared`; pane fechado gera `ended`; Herdr indisponível não arquiva; `archive` de sessão atual → `ack` + `treeChanged`; de sessão desconhecida → `sessionNotFound`; contexto do plugin vence o do transcript.
  - [ ] `mochad doctor` mostra o item Uso com a idade do cache.
  - [ ] **Para o João conferir** (checklist do WP-X1): o plano e a conta que aparecem no app batem com a conta real; se não baterem, os nomes das chaves de `~/.claude.json` da §3.4 estão errados.

### WP-M11: upload de imagem no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Uploads/` (novo), a rota `POST /v1/upload` e a verificação do Bearer em `MochaDaemonCore/Gateway/`, a busca de aparelho por token em `MochaDaemonCore/Devices/`, a ligação em `MochaDaemonCore/App/` (`DaemonPaths`, `DaemonRuntime`), a regra dos marcadores de imagem em `MochaKit/Sources/MochaTranscript/` e `MochaKit/Fixtures/transcripts/`, e os testes (`MochaKit/Tests/MochaDaemonCoreTests/Uploads/` e os do `MochaTranscriptTests` da regra nova).
- **Depende de**: WP-M3, WP-M10.
- **SPEC**: §5.5 (`POST /v1/upload`), §3.2 (marcadores de imagem do Mocha), §4.3 (`uploads/`), §10.
- **Faz**:
  1. `UploadStore`: grava o corpo atômico com 0600 em `uploads/` (0700), com nome UUID e extensão pelo `Content-Type`, e devolve o caminho absoluto. Limpeza dos arquivos com mais de 7 dias na subida do daemon e a cada 6 h.
  2. Rota `POST /v1/upload` com `maxBodySize` de 20 MB, Bearer verificado contra o `DeviceStore` (mesma regra do `hello` com `deviceToken`), e os erros da §5.5. Resposta `UploadResponse` do `MochaProtocol`.
  3. `mochad run` liga o `UploadStore` real e a limpeza.
  4. `MochaTranscript`: os marcadores `[imagem: <caminho em uploads/>]` saem do texto do `userPrompt` e somam no `imageCount` (§3.2), inclusive no `preview` da Home.
- **Aceite**:
  - [ ] Testes da rota: 200 com JPEG, PNG e HEIC, com o caminho em `uploads/` e a extensão certa; 401 sem Bearer e com token desconhecido; 411; 413 acima de 20 MB; 415; 400 com corpo vazio; o nome é gerado pelo daemon e o caminho do cliente é ignorado.
  - [ ] Testes do `UploadStore`: permissões 0700 e 0600, gravação atômica, limpeza só do que tem mais de 7 dias.
  - [ ] Testes do transcript: prompt com 1 e com 3 marcadores vira `userPrompt` sem os marcadores e com `imageCount` certo; marcador fora de `uploads/` fica no texto; `queued_command` com marcador; prompt só com marcador vira `[imagem]` no `preview`.
  - [ ] `scripts/test.sh` verde.

### WP-I13: mandar imagem pelo app

- **Dono**: `App/Sources/Composer/`, a bolha do usuário em `App/Sources/Chat/`, o envio com anexos em `App/Sources/AppShell/AppSession.swift`, `MochaKit/Sources/MochaClient/Connection/` (cliente de upload), `MochaKit/Sources/MochaClient/Presentation/` (texto do prompt com marcadores, redução da imagem) e os testes em `MochaKit/Tests/MochaClientTests/`.
- **Depende de**: WP-I5, WP-I2. Roda em paralelo com o WP-M11, contra o contrato da §5.5.
- **SPEC**: §6.5, §6.3 (Composer), §5.5 (`POST /v1/upload`).
- **Faz**:
  1. `+` no composer expandido com o menu "Fotos", "Câmera" e "Colar imagem"; faixa de miniaturas com "x"; enviar habilitado com imagem e sem texto; até 5 imagens.
  2. Redução para 2.048 px no lado maior, JPEG 0,85, com a orientação certa (ImageIO, testável no macOS).
  3. Cliente de upload no `MochaClient`: `URLSession.upload(for:from: Data)` para `https://<host do pareamento>/v1/upload`, com `Authorization: Bearer <deviceToken>` do `TokenStore` e o `Content-Type`; lê o `UploadResponse`.
  4. Envio: uploads em sequência e depois um `sendPrompt` com o texto e uma linha `[imagem: <path>]` por imagem. Falha em qualquer upload não envia nada e mantém texto e miniaturas.
  5. Bolha pendente e definitiva com "📎 1 imagem" / "📎 N imagens".
  6. No `-demo`, o upload é falso e devolve um caminho em `uploads/`. Uma flag de Debug anexa imagens de amostra para a captura (nome proposto no relatório, para a §6.1).
- **Aceite**:
  - [ ] Testes no `MochaClient`: texto do prompt com marcadores na ordem; redução mantém a proporção e o lado maior ≤ 2.048 px; requisição com URL, Bearer, `Content-Type` e corpo `Data`; falha de upload não chama `sendPrompt`.
  - [ ] No simulador com `-demo`: o menu do `+` aparece; com a flag de amostra, a faixa de miniaturas aparece e o enviar acende sem texto; depois de enviar, a bolha mostra "📎 2 imagens". Capturas comparadas com `08-chat-digitando` (resto do composer inalterado).
  - [ ] `scripts/test.sh` e `scripts/build-app.sh` verdes.
  - [ ] No iPhone (checklist do WP-X1): foto do rolo, da câmera e print colado chegam ao Claude, que descreve a imagem.

### WP-X1: integração da 1a-core

- **Dono**: orquestrador. Correções pequenas em qualquer diretório, commitadas separadamente.
- **Depende de**: todos os WPs da 1a-core e os bloqueios B1, B3, B4 e B8.
- **Faz** (preparação, sem o João): `mochad install` (LaunchAgent), `mochad serve-setup --apply` (autorizado no B4; antes, `tailscale serve status` precisa estar vazio), `mochad doctor`, e o build assinado do app com `scripts/build-device.sh`, deixando no HANDOFF os comandos de instalação e de abertura no iPhone. O João instala e percorre o checklist.
- **Checklist do João** (no iPhone, pelo tailnet):
  - [ ] O app foi apagado e instalado de novo antes do checklist, porque a sonda de debug pode estar gravada.
  - [ ] Pareia lendo com a câmera o QR do `mochad pair`, e cai na Home.
  - [ ] A Home mostra os agentes reais nas seções certas: um agente trabalhando em TRABALHANDO, com a última ferramenta; um diálogo de permissão no Mac o leva para PRECISA DE VOCÊ; o turno terminado vai para CONCLUÍDOS e, 10 min depois, para ARQUIVADOS.
  - [ ] O anel mostra o contexto livre parecido com o do statusLine do Claude no Mac, e gira enquanto o agente trabalha.
  - [ ] A pílula de uso mostra 5h e 7d iguais aos do Herdr, e o Uso mostra o plano e a conta certos (confere as chaves de `~/.claude.json`).
  - [ ] `/clear` num agente leva a sessão antiga para ARQUIVADOS como "Sessão encerrada", e o chat dela abre só de leitura. Arrastar um card de CONCLUÍDOS o arquiva.
  - [ ] Segurar um card abre o Detalhe; tocar na sessão copia o id.
  - [ ] A gaveta mostra os workspaces, tabs e agentes reais, com branch e `*`; pedir a um agente para criar um worktree com `herdr worktree create` faz o workspace novo aparecer aninhado sem recarregar.
  - [ ] Abrir um chat longo mostra a última página em menos de 1 s, e a rolagem pra cima carrega o histórico.
  - [ ] A rolagem num chat longo fica a 60 fps no iPhone 14.
  - [ ] Arrastar da borda esquerda volta do chat para a Home; tocar no disco também.
  - [ ] O composer fica em uma linha; ao tocar, expande; rolar, tocar fora, abrir a gaveta ou enviar fecham o teclado.
  - [ ] Enviar um prompt pelo celular faz o Claude responder, e a resposta aparece no chat. Enviar durante um turno enfileira.
  - [ ] O botão de parar da linha "Trabalhando…" interrompe o agente.
  - [ ] Fechar o app, mandar um prompt pelo Mac e reabrir: a Home e o chat estão atualizados.
  - [ ] Trocar Wi-Fi ↔ 4G com o app aberto: o chat continua sem reconectar (pode parar de atualizar por até ~10 s).
  - [ ] App em background ou tela bloqueada por 30 s e de volta: reconecta em menos de 1 s.
  - [ ] Parar o `mochad` mostra a cápsula de sem conexão na Home, sem esvaziar a lista.
  - [ ] Foto do rolo, foto da câmera e print colado chegam ao Claude, que descreve a imagem; a bolha mostra "📎 N imagens".
  - [ ] O visual bate com o mock (ok visual do João).

---

## Fase 1a-final: push, slash e nova tab

**Ondas**
- Branch `fase/1a-final`, criada a partir de `fase/1a-core`.
- **Onda 2.A**, em paralelo: WP-M5 · WP-I6 · WP-I7.
- Antes da onda 2.B, o orquestrador completa o contrato do `newAgentTab` (SPEC §5.3 e §5.3.1) e desenha o `+` por workspace na gaveta do mock, com o ok do João no print.
- **Onda 2.B**, em paralelo: WP-M6 · WP-I11.
- **Onda 2.C**: WP-M12. Vem depois do WP-M6 porque os dois mexem em `Gateway/SessionHubConnection.swift`, no `HerdrBridging` e no `FakeHerdrBridge`.
- **Onda 2.D**: WP-X2.

### WP-M5: `HookServer` e `install-hooks`

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Hooks/`, o comando `install-hooks`/`uninstall-hooks` em `mochad`, e em `MochaDaemonCore/App/` só a montagem das rotas no listener local e a linha de hooks do `doctor` (único WP da onda no daemon).
- **Depende de**: WP0.3, WP-M4, S3.
- **SPEC**: §3.3.
- **Faz**: rotas `POST /hooks/<Evento>` no listener local, validação do segredo, tradução dos payloads (fixtures do S3) em eventos internos, merge idempotente no `settings.json` com backup do bloco de `Fixtures/hooks/settings.install-hooks.proposed.json` (comando `curl` assíncrono em `SessionStart`/`UserPromptSubmit`/`Stop`/`Notification`, `http` em `PermissionRequest`), entradas do Mocha reconhecidas por `127.0.0.1:47420/hooks/` em `url` ou `command`, e detecção do moshi-hook.
- **Aceite**:
  - [ ] Testes com as fixtures do S3: cada request de `Fixtures/hooks/` decodifica, com campos opcionais ausentes (`model`, `prompt_id`, `title`, `permission_suggestions`).
  - [ ] O merge sobre um `settings.json` que só tem o hook do Herdr resulta igual a `settings.install-hooks.proposed.json`, com a porta e o segredo do config.
  - [ ] Dois hooks seguidos de um cliente com `Connection: keep-alive` são atendidos sem erro (a resposta leva `Connection: close`, §4.4).
  - [ ] `SessionStart` com `transcript_path` inexistente é aceito, e `source` distingue `clear` de `compact` (S1).
  - [ ] Teste do merge sobre uma cópia do `settings.json` real do João (em diretório temporário): preserva hooks de terceiros, é idempotente e o uninstall remove só o que é do Mocha.
  - [ ] `PermissionRequest` responde `{}` na hora (sem decidir) nesta fase.

### WP-M6: `PushService` (alertas)

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Push/`, a permissão de escrita em `Hooks/ClaudeHooksInstaller.swift`, o limite de corpo das rotas em `Hooks/HookServer.swift`, o comando `apns` em `mochad`, o tratamento de `setPreferences`, `slash` e `hello.apns` em `Gateway/`/`Devices/`, e a ligação dos hooks aos serviços em `MochaDaemonCore/App/` (único WP da onda).
- **Depende de**: S4, WP-M5.
- **SPEC**: §7.1, §4.6.
- **Faz**: JWT com cache e renovação, cliente HTTP/2, escolha de ambiente por aparelho, os dois tipos de alerta, supressão por primeiro plano e por preferência, deduplicação e limpeza de token inválido. Parte do protótipo `MochaDaemonCore/Push/` do S4, que já tem `ApnsJWT`, `ApnsTokenProvider` (40 min, invalidação em `ExpiredProviderToken`), `ApnsRequest` (headers e validações de 4 KB e 64 bytes), `ApnsResponse`, `ApnsClient`, `URLSessionApnsTransport` (métrica h2), `ApnsAlertPush`, `KeychainApnsKeyStore`, `ApnsConfigStore` e `ApnsKeyImporter`, com 26 testes em `Tests/MochaDaemonCoreTests/Push/`. Evolui o `ApnsClient` para uma `URLSession` única reaproveitada entre envios. Política de headers da §7.1 (`apns-expiration` por tipo, `apns-collapse-id` = `agentId`, `apns-id` no log). Respostas: 410 e `BadDeviceToken` removem o token; `ExpiredProviderToken` renova e repete uma vez; `BadEnvironmentKeyInToken`, `BadEnvironmentKeyIdInToken` e `InvalidProviderToken` viram erro de configuração no log e no `doctor`, sem retry; 429 e 5xx com backoff. O `mochad apns test` passa a aceitar `--device <id>` (de `devices.json`), e o `--token <hex> --env` fica como diagnóstico. O `apns liveactivity start|update|end` fica como diagnóstico até o WP-M8. O corpo do alerta de turno concluído usa o `PlainText.preview(fromMarkdown:)` do WP-M2b. O `SessionStart` com `source: clear` também chega ao `SessionHub` como troca de sessão, e a sessão antiga vai para o `SessionArchive` com `cleared` (§4.1.2). O `ApnsConfigStore` passa a gravar pelo `AtomicFile` do WP-M4 com 0600 desde a criação (hoje grava com `.atomic` e só depois faz `chmod`, uma janela em 0644 num arquivo que agora guarda o `hookSecret`). O `install-hooks` (WP-M5, `Hooks/ClaudeHooksInstaller.swift`) passa a gravar o `settings.json` e o backup em 0600 (§3.3.1); hoje mantém a permissão anterior, e o arquivo do João é 0644. As rotas `/hooks/*` do `HookServer` passam a aceitar corpo de até 16 MiB (§4.4): com o limite padrão de 1 MB, um `PermissionRequest` de um `Write` grande recebe 413 e fica sem push. O `Stop` de um agente recalcula o `isDirty` do workspace dele (§3.1.4): o `GitInspector` de `MochaDaemonCore/Herdr/` (WP-M1) ainda não tem API para invalidar o cache, e o WP-M6 é dono dessa extensão e da exposição dela no `HerdrBridging` nesta onda.
- **Aceite**:
  - [ ] Testes do JWT (formato e assinatura verificável com a chave pública), da montagem de payloads e das regras de supressão e deduplicação, com cliente APNs falso.
  - [ ] `mochad apns test` entrega no iPhone.
  - [ ] Teste: `403 BadEnvironmentKeyInToken` não é repetido e aparece no `doctor`.
  - [ ] `slash` vira `agent.prompt` com o comando (§5.3), `hello.apns` grava o token e o `env` no `devices.json` (§4.6), e o `SessionStart` do hook dispara o `agent.get` e a troca de arquivo do `TranscriptStore` (§3.1.3 d).
  - [ ] Teste: o `Stop` invalida o cache de `isDirty` do workspace do agente, e a árvore seguinte reflete o `git status` novo.
  - [ ] Teste: o `install-hooks` sobre um `settings.json` 0644 deixa o arquivo e o backup em 0600.
  - [ ] Teste: um `PermissionRequest` com corpo de 2 MB é aceito, e um acima de 16 MiB recebe 413.

### WP-I6: notificações no app

- **Dono**: `App/Sources/Notifications/`, o campo `apns` do `hello` em `App/Sources/Connection/` e `MochaKit/Sources/MochaClient/` (único WP da onda que mexe ali), o item de notificações em `App/Sources/Settings/`, e `App/Sources/AppShell/AppDelegate.swift` e `App/Sources/AppShell/AppSession.swift` (delegate das notificações, `setForeground` e navegação pelo toque; único WP da onda que mexe ali).
- **Depende de**: S4, WP-I2.
- **SPEC**: §7.1, §6.1 (deep links), §6.3 (Ajustes).
- **Faz**: pedido de permissão (`.alert`, `.sound`, `.badge`; o time-sensitive vem do entitlement do WP0.1 e do `interruption-level` do payload), registro do token com `env` no `hello`, `setForeground`, categorias `TURN_DONE`/`NEEDS_INPUT`, o toque abrindo o chat certo por cima da Home pela navegação do `AppSession` (com o app encerrado, em background ou aberto em outro chat; telas `14-tela-bloqueada` e `14b-banner`), e o controle "Avisar quando o Claude terminar" em Ajustes (`setPreferences`). Parte de `App/Sources/Notifications/` do S4: `PushRegistration` (permissão e registro) e `ApnsEnvironmentDetector` (`env` pelo `embedded.mobileprovision`). `registerForRemoteNotifications` a cada launch; o token chega em ~0,2 s. O delegate do `UNUserNotificationCenter` é definido no `didFinishLaunchingWithOptions`, `nonisolated`, com a variante de completion handler, porque os tipos de UserNotifications não são `Sendable` (como no `PushProbeNotificationDelegate` do S4). Alertas só testáveis no iPhone, porque o simulador não entrega o token de alerta.
- **Aceite**:
  - [ ] Os três estados de abertura testados no device (checklist no relatório).
  - [ ] O app manda `setForeground` ao abrir, trocar e fechar um chat, e ao ir para background (a supressão do alerta é do WP-M6 e é conferida no WP-X2).
  - [ ] Dois alertas com o mesmo `agentId`: o segundo substitui o primeiro na Central (`apns-collapse-id`), que o S4 não verificou em detalhe.

### WP-I7: menu de slash

- **Dono**: `App/Sources/Composer/SlashMenu*`, o botão `↻` do composer expandido (oculto antes desta fase), o `slash` do demo em `MochaKit/Sources/MochaDemo/` (simula o `/clear`: sessão nova e a antiga em ARQUIVADOS) e `App/Sources/Chat/`, se a troca de sessão depois do `/clear` pedir.
- **Depende de**: WP-I5.
- **SPEC**: §6.3 (Menu `↻`), §5.3 (`slash`).
- **Faz**: menu acima do `↻`, por cima do teclado, e a confirmação do `/clear`, pelas telas `09-menu-slash` e `09b-confirma-clear`.
- **Aceite**:
  - [ ] Os comandos da lista enviam `slash`; `/clear` pede confirmação.
  - [ ] Depois de `/clear`, o chat troca para a sessão nova (depende do WP-M2 e do S1), e a antiga aparece em ARQUIVADOS.
  - [ ] Capturas comparadas com `09-menu-slash` e `09b-confirma-clear`.

### WP-I11: nova tab no app

- **Dono**: o `+` por workspace em `App/Sources/Drawer/`, e o `newAgentTab` do demo em `MochaKit/Sources/MochaDemo/` e `MochaKit/Tests/MochaDemoTests/`.
- **Depende de**: WP-I3, o contrato do `newAgentTab` (SPEC §5.3.1) e o `+` da gaveta no mock.
- **SPEC**: §6.3 (Gaveta), §5.3 (`newAgentTab`), §5.3.1.
- **Faz**: o `+` na linha de cada workspace da gaveta manda `newAgentTab` pelo `AppSession.request(_:)` e, no `ack{agentId}`, fecha a gaveta e abre o chat do agente novo pelo `openChat(_:)`. Um `error` vira o aviso da gaveta com a `message`. No demo, o `newAgentTab` cria um agente Claude `idle` numa tab nova do workspace, manda a árvore nova e responde `ack{agentId}` (hoje responde erro, e o teste espera isso). O teste real é no WP-X2, depois do WP-M12.
- **Aceite**:
  - [ ] No demo, o `+` de um workspace abre o chat vazio do agente novo, e a gaveta mostra a tab nova.
  - [ ] Teste do demo: `newAgentTab` responde `ack{agentId}` e a árvore seguinte tem o agente; workspace desconhecido responde o erro da §5.3.1.
  - [ ] Captura da gaveta comparada com a tela do mock que mostra o `+`.

### WP-M12: nova tab no daemon

- **Dono**: `tab.create`, `agent.start` e `agent.wait` em `MochaKit/Sources/MochaHerdr/` (com `Tests/MochaHerdrTests/`), a extensão do `HerdrBridge`/`HerdrBridging` para `newAgentTab` em `MochaDaemonCore/Herdr/`, o `FakeHerdrBridge` em `MochaTestSupport/Herdr/`, e o tratamento da mensagem WS `newAgentTab` no `SessionHub` (`Gateway/`).
- **Depende de**: WP-M1, WP-M3, WP-M6 (mesmos arquivos).
- **SPEC**: §5.3 (`newAgentTab`), §5.3.1, §3.1.1, §3.1.2.
- **Faz**: `tab.create {workspace_id, cwd, focus:false}` → `agent.start {name:"mocha-<n>", kind:"claude", pane_id:root_pane, args:[]}` → espera `idle` ou `blocked` por evento, com timeout de 30 s, e responde `ack{agentId}`. O `blocked` (diálogo de confiança numa pasta nova, S2) não é respondido pelo daemon: o agente aparece em PRECISA DE VOCÊ e o João responde no Mac. O `HerdrClient` (WP-M1) ainda usa só os timeouts de 5 s e 10 s: o WP-M12 acrescenta o timeout de `timeout_ms` + 2 s das chamadas com espera (`agent.wait`, `agent.start`, §3.1.1). Fixtures em `Fixtures/herdr/`: `tab.create.response.json`, `agent.start.response.json`, `agent.wait.response.json`, `error.timeout.json` e `stream.status.startup-trust-dialog.jsonl`.
- **Aceite**:
  - [ ] Teste com o Herdr falso: `newAgentTab` faz `tab.create` → `agent.start` → espera `idle` e responde `ack{agentId}`; com `blocked`, responde `ack{agentId}` do mesmo jeito; os erros seguem a §5.3.1.
  - [ ] Teste: a chamada com espera usa o timeout de `timeout_ms` + 2 s.
  - [ ] Teste: durante a espera do `newAgentTab`, outra mensagem da mesma conexão (ex.: `ping`) é respondida.
  - [ ] O `unknownType` de `newAgentTab` sai do `SessionHubConnection`, e o teste de regras do hub cobre a mensagem.

### WP-X2: integração da 1a-final

- **Checklist do João**:
  - [ ] Com o app fechado, um turno longo termina e chega o push "Claude terminou · <workspace>" com a prévia sem markdown, como na tela `14-tela-bloqueada`.
  - [ ] Com o app aberto em outro chat, o alerta chega como banner (`14b-banner`).
  - [ ] Tocar no push abre o chat certo, com o app encerrado, em background e aberto em outro chat.
  - [ ] Na primeira conexão aparece o pedido de permissão, e o `devices.json` passa a ter o `apns` com `env: sandbox`.
  - [ ] `mochad devices` e depois `mochad apns test --device <id>` entregam o alerta no iPhone (critério do WP-M6).
  - [ ] Dois alertas do mesmo agente: o segundo substitui o primeiro na Central.
  - [ ] Com "Turno concluído" desligado em Ajustes, só chegam os alertas de "precisa de você", que chegam como time-sensitive.
  - [ ] Um pedido de permissão no Mac gera o push "precisa de você" em menos de 5 s.
  - [ ] Com o chat do agente aberto, nenhum push desse agente.
  - [ ] `/compact` e `/clear` pelo menu funcionam.
  - [ ] O `+` de um workspace na gaveta abre o chat de um Claude novo numa tab nova, e ele responde ao primeiro prompt.
  - [ ] Num workspace cuja pasta o Claude ainda não conhece, o `+` responde em até 30 s e o agente novo aparece em PRECISA DE VOCÊ com o diálogo de confiança; respondido no Mac, o chat segue normal (critério do WP-M12).
  - [ ] Com o VPN On Demand ligado (B6), o app conecta sem abrir o Tailscale.
- **Depois do WP-X2**: o João decide quando executar o B7 (remover o moshi-hook). A fase 1b não começa antes disso.

---

## Fase subagentes

**Ondas**
- Branch `fase/subagentes`, criada a partir de `fase/1a-final`. Não depende do B7.
- **Escopo aprovado pelo João**: card do subagente (`Agent`) vivo no chat, que abre o transcript do subagente só de leitura; selo "N subagentes" no card da Home e lista no Detalhe do agente; card de workflow com as fases. O mock (telas 16 a 19) está aprovado.
- **Antes da onda 4.A**, o orquestrador: SPEC desta fase (§3.2.2, §3.5, §4.1.1, §4.1.2, §5, §6.1, §6.3) e contratos, com commit na fase. Os contratos são:
  - os tipos no `MochaProtocol` e as fixtures em `MochaKit/Fixtures/protocol/` (§5.3);
  - o tratamento mínimo dos casos novos nos `switch` exaustivos fora do protocolo (app, daemon, demo e transcript), que só compila e mantém o comportamento atual, para `scripts/test.sh` e `scripts/build-app.sh` ficarem verdes na fase;
  - em `App/Sources/DesignSystem/`, os glifos `agent` e `flow` do mock (`i-agent`, `i-flow`) e o ícone de estado do subagente (girando, ✓, ✗, ■), que o WP-I14 e o WP-I15 usam sem mexer em `DesignSystem/`.
- **Onda 4.A**, em paralelo: WP-M13 · WP-D3.
- **Onda 4.B**, em paralelo: WP-M14 · WP-I14 · WP-I15. Depois dos merges da onda, o orquestrador confere no demo que tocar numa linha da lista do Detalhe abre o transcript do subagente (I15 + I14).
- **Onda 4.C**: WP-X6.

### WP-M13: parser de subagentes e workflows

- **Dono**: `MochaKit/Sources/MochaTranscript/`, `MochaKit/Tests/MochaTranscriptTests/`, as fixtures novas em `MochaKit/Fixtures/transcripts/` (com o README delas) e `MochaKit/Fixtures/transcripts/expected/`.
- **Depende de**: contratos da fase.
- **SPEC**: §3.2.2 (card de subagente, card de workflow, notificação de tarefa, modo subagente), §3.5.1, §3.5.3 (fases), §5.2, §5.2.1.
- **Faz**:
  1. No transcript principal, `tool_use` `Agent`/`Task` vira `subagent` e `Workflow` vira `workflow`, com o `tool_result` preenchendo `agentId`, `runId` e o nome; resultado síncrono vira `completed` com os totais; `is_error`, `failed`.
  2. Notificação de tarefa: o `TaskNotification.parse` público (o WP-M14 usa o mesmo), com os blocos detectados só por `origin.kind` e `commandMode`, antes da regra de `isMeta`. `^a` e `^w` atualizam o card por `chatUpdate`, sem item; `^b`, bloco sem `<task-id>` e texto sem bloco continuam `notice`. A linha `user` de `peer` é ignorada por regra própria.
  3. Modo subagente: aceita `isSidechain`, gera `task` na primeira linha, pula até a fronteira do fork, transforma `Agent` aninhado em `subagent` e não gera `turnFooter`. A entrada do modo é o `TranscriptParseMode.subagent(forkToolUseId:)` da §3.2.2.
  4. `WorkflowScriptMeta`, público: `name` e fases do `export const meta` (§3.5.3), com falha sem erro.
  5. Tipo sem o prefixo de plugin.
  6. Fixtures redigidas a partir dos formatos da §3.5, sem conteúdo privado, cada uma com a linha no README e o snapshot em `expected/`: `subagents-background.jsonl` (principal: `Agent` em background, handback de `peer`, `queue-operation`, notificação por `attachment` e por `user`, interina, `failed`, `TaskStop` com `killed`, `Agent` sem `<tool-use-id>` na notificação e um `^b`) com `subagents-background/subagents/` (um `agent-<id>.jsonl` com `.meta.json` para concluído com handback, falha de API, parado, fork com `fork-context-ref`, fork aninhado com linhas copiadas e aninhado de `spawnDepth` 2, com a notificação do aninhado entregue no arquivo do pai como `user` com `origin.kind: "task-notification"` e `isMeta: true`, e um sidecar `*.forked-skill.json`); e `workflow.jsonl` (lançamento e notificação `Dynamic workflow`) com `workflow/subagents/workflows/wf_<runId>/` (journal com retentativa e dois agentes, um com `StructuredOutput`) e `workflow/workflows/wf_<runId>.json`. Essas fixtures também servem ao WP-M14.
  7. Regenera `expected/subagents.json` e a linha dele no README: os `Agent` viram `subagent` e o aviso `Agent "Revisar README" finished` some. Revisa item a item antes de entregar.
- **Aceite**:
  - [ ] Cada fixture nova gera o snapshot de `expected/`, revisado item a item contra a §3.2.2, e a sequência de tipos bate com a coluna "Itens esperados" do README.
  - [ ] `expected/subagents.json` regenerado: os dois `Agent` viram `subagent(completed)` (o primeiro pelo resultado síncrono, o segundo pela notificação `a4ccb30dd881b5306`), sem o `notice` do `Agent`; o `notice` do `Background command` continua. Os snapshots das outras fixtures não mudam.
  - [ ] Teste da notificação: `^a` com `<tool-use-id>` e sem ele (casado pelo `agentId`); interina mantém `running`; `failed` com o motivo depois de `failed: `; `killed` vira `stopped`; `<usage>` preenche `toolUses` e `durationMs`; `^w` fecha o `workflow` com as contagens; `^b` vira `notice`; linha com três blocos; no modo subagente, a notificação do aninhado com `isMeta: true` atualiza o card dele; `queue-operation`, `prompt_snapshot` e `deferred_tools_record` com a string `<task-notification>` não geram nada.
  - [ ] Teste do modo subagente: `task` da primeira linha; o fork com `fork-context-ref` e o fork aninhado começam depois da fronteira, com a tarefa depois de `Your directive: `; o `Agent` aninhado vira `subagent`; `turn_duration` não gera `turnFooter`.
  - [ ] Teste do `WorkflowScriptMeta`: aspas simples, duplas e crase, `detail` ausente, `name`; script sem `meta`, com `${` ou malformado falha sem lançar.
  - [ ] Tipo `feature-dev:code-reviewer` vira `code-reviewer`; sem `subagent_type`, `general-purpose`.
  - [ ] `scripts/test.sh` verde.

### WP-D3: demo dos subagentes

- **Dono**: `MochaKit/Sources/MochaDemo/` e `MochaKit/Tests/MochaDemoTests/`.
- **Depende de**: contratos da fase.
- **SPEC**: §2.2 (subagentes no demo), §5.2, §5.3, §5.3.1 (`openChat` com `subagentId`, `listSubagents`), §6.3 (telas 16 a 19).
- **Faz**:
  1. Os dados das telas 16 a 19 da §2.2: os cards de subagente no chat de `receitas-api` (inclusive os de cima da parte visível), o card do aninhado no transcript do subagente que roda (tela 16b), o card de workflow no chat de `demo-app`, o card parado e o workflow concluído no histórico de `login-social` e o `runningSubagents` da árvore (1 no `receitas-api`, 2 no `demo-app`).
  2. `openChat`/`closeChat` com `sessionId` e `subagentId`: o transcript de cada subagente e de cada agente do workflow (páginas fixas, com `task` no topo e `ChatMeta.subagent`), e as regras da §5.3.1 (`invalidPayload` fora do formato, `sessionNotFound` "Subagente não encontrado").
  3. `listSubagents` com a lista da tela 18 na ordem da §5.3.1, e as regras (`agentNotFound`, `invalidPayload` no agente do codex, lista vazia sem sessão).
  4. Roteiro `-demo-script`: o subagente que roda termina (`chatUpdate` do card, `chatMeta` do transcript, `treeChanged` com o selo zerado, e o `listSubagents` passa a devolvê-lo como `completed`).
- **Aceite**:
  - [ ] Testes em `MochaDemoTests` para cada item acima: os cards e estados de cada chat e transcript da §2.2, cada regra de `openChat`/`closeChat` e de `listSubagents`, e cada evento do roteiro, inclusive a lista depois dele.
  - [ ] Os testes atuais do demo passam, adaptados só aos contratos novos.
  - [ ] `scripts/test.sh` verde.

### WP-M14: subagentes no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Subagents/` (novo); em `MochaDaemonCore/Transcript/`, o modo subagente do `TranscriptStore` (`TranscriptSession.subagent`, cursor); a composição e as mensagens em `MochaDaemonCore/Gateway/`; a montagem do `SubagentStore` em `MochaDaemonCore/App/`; `MochaKit/Sources/MochaTestSupport/Subagents/` (novo) e o `FakeTranscriptProvider` em `MochaTestSupport/Transcript/`; e os testes (`MochaKit/Tests/MochaDaemonCoreTests/Subagents/`, `Transcript/` e `Gateway/`).
- **Depende de**: WP-M13.
- **SPEC**: §3.2.3, §3.5, §4.1, §4.1.1 (`SubagentProviding`, `TranscriptSession.subagent`), §4.1.2 (subagentes e workflows), §5.3, §5.3.1.
- **Faz**:
  1. O `SubagentStore` implementa `SubagentProviding`: observação por `DispatchSource` e leitura incremental (§3.5.4), estado e métricas de cada subagente (§3.5.2), workflows com journal, fases, fim e symlink (§3.5.3), contagem dos que rodam, lista na ordem da §5.3.1 e resolução do arquivo do subagente.
  2. O `TranscriptStore` abre um `TranscriptSession` com `subagent` no modo subagente do WP-M13, com o cursor `<sessionId>/<agentId>:<offset>`.
  3. O `SessionHub`: `observe(sessions:)`, sobreposição do estado nos cards com o limite de 1 s, `runningSubagents` com `treeChanged`, a Home ao vivo acompanhando agente com subagente rodando, `listSubagents`, `openChat`/`closeChat` com `subagentId` e o `ChatMeta` do chat de subagente (§4.1.2, §5.3.1).
  4. Entrega o `FakeSubagentProvider` em `MochaTestSupport/Subagents/`.
- **Aceite**:
  - [ ] Testes do estado com as fixtures do WP-M13 copiadas para um diretório temporário: cada desfecho da tabela (a) da §3.5.2, `stoppedByUser`, `enqueue` antes da entrega, notificação interina, retomada por `coordinator` voltando a `running`, `attachment` depois do fim sem mudar o estado, `failureReason` pela precedência da §3.5.2 (o texto sintético não muda quando a notificação chega), e a primeira leitura pelo `timestamp` mais recente.
  - [ ] Primeira observação de um transcript principal de 50 MB (fixture de `scripts/gen-big-transcript.swift`) lê no máximo 8 MB, conferido por um contador de bytes lidos; depois, a leitura é incremental só nas condições de acompanhamento da §3.5.4.
  - [ ] Append simulado: um `tool_use` no arquivo do subagente muda `activity` e `toolUses` e gera evento; o `meta.json` reescrito com inode novo é relido; `.jsonl` antes do meta é aceito; `*.forked-skill*.json` é ignorado.
  - [ ] Teste de workflow: fases do script inline e do `scriptPath`, reserva pelo journal com script malformado, retentativa com a mesma `key` (vale a última), estado das fases, fim pelo `wf_*.json` e pela notificação, symlink deduplicado. As variantes `scriptPath` (com o `workflows/scripts/*.js`) e symlink de `wf_*` são montadas pelo próprio teste no diretório temporário, a partir da fixture `workflow` do WP-M13.
  - [ ] Teste do `SessionHub` com `FakeSubagentProvider`: card sobreposto no `chatPage`; `chatUpdate` com no máximo 1 por card a cada 1 s e mudança de `status` na hora; `runningSubagents` gera `treeChanged`; agente `idle` com subagente rodando mantém a inscrição do transcript; `listSubagents` com as regras da §5.3.1.
  - [ ] Teste do chat de subagente: `openChat` com `subagentId` devolve `task` no topo e o `ChatMeta` da §4.1.2; paginação com o cursor novo; `subagentId` inválido → `invalidPayload`; arquivo inexistente → `sessionNotFound`; agente de workflow abre pelo diretório `wf_*`.
  - [ ] `FakeSubagentProvider` com teste próprio.
  - [ ] `scripts/test.sh` verde.

### WP-I14: subagentes e workflow no chat

- **Dono**: `App/Sources/Chat/`; em `App/Sources/AppShell/`, só a navegação do chat de subagente (`AppSession` e `AppShellView`; único WP da onda que mexe ali); `MochaKit/Sources/MochaClient/Presentation/ChatNavigation.swift` e os testes dele em `MochaKit/Tests/MochaClientTests/`.
- **Depende de**: WP-D3.
- **SPEC**: §6.1 (navegação, argumentos de launch), §6.3 (Subagente no chat, Transcript do subagente, Workflow no chat).
- **Faz**: `SubagentCard`, `WorkflowCard` e `TaskCard`; `ChatScreen(target: .subagent)` com o header de voltar, o aviso do topo, a pílula de estado e o rodapé ou o motivo da falha; o push sobre a pilha, com os chats da pilha abertos e reabertos na reconexão; e o `-chat-open-subagent`. Tudo contra o demo.
- **Aceite**:
  - [ ] Capturas no demo comparadas com `16-chat-subagente`, `16b-transcript-subagente`, `16c-transcript-concluido` e `19-chat-workflow`, e os estados abaixo das telas 16 e 19 no mock (falhou, parado, workflow recolhido), que no demo estão no `Plan` com falha do `receitas-api` e no subagente parado e no workflow concluído do `login-social`.
  - [ ] Tocar num card de subagente, num aninhado e num agente do workflow abre o transcript certo; voltar volta ao chat de baixo, que continua ao vivo.
  - [ ] No roteiro `-demo-script`, o card e a pílula passam de rodando a concluído sem reabrir o chat.
  - [ ] Testes do `ChatNavigation` para o push de subagente, o `closeChat` ao sair da pilha e a reabertura da pilha.

### WP-I15: Home e Detalhe com subagentes

- **Dono**: `App/Sources/Home/`, `App/Sources/AgentDetail/`, `MochaKit/Sources/MochaClient/Presentation/HomeSections.swift`, o arquivo novo `MochaKit/Sources/MochaClient/Presentation/SubagentRows.swift` e os testes deles em `MochaKit/Tests/MochaClientTests/`.
- **Depende de**: WP-D3.
- **SPEC**: §6.3 (Home, Home com subagentes, Detalhe com subagentes), §5.3.1 (`listSubagents`), §6.1 (`-home-open-detail`).
- **Faz**: o selo no card da Home; a regra de ARQUIVADOS com `runningSubagents > 0`; a seção SUBAGENTES do Detalhe, com `listSubagents` ao abrir e a cada mudança do `runningSubagents`, aninhado recuado e tempo ao vivo, com as linhas montadas pelo `SubagentRows` (lógica pura); o toque que fecha a folha e chama `AppSession.openChat(.subagent(sessionId:agentId:))`; e o `-home-open-detail`. Tudo contra o demo. A tela do transcript é do WP-I14, na mesma onda: o toque ponta a ponta é conferido pelo orquestrador depois dos merges da onda 4.B.
- **Aceite**:
  - [ ] Capturas no demo comparadas com `17-home-subagentes` e `18-detalhe-subagentes`.
  - [ ] Testes do `HomeSections`: agente `idle` com `runningSubagents > 0` e turno terminado há mais de 10 min fica em CONCLUÍDOS; com `archivedAt`, vai para ARQUIVADOS.
  - [ ] No roteiro `-demo-script`, o selo do `receitas-api` some, e o Detalhe aberto pede a lista de novo.
  - [ ] Testes do `SubagentRows`: recuo do aninhado, texto de cada linha (tipo, tempo, ferramentas, "falhou") e o `ChatTarget.subagent(sessionId:agentId:)` de cada linha, inclusive a do aninhado.

### WP-X6: integração dos subagentes

- **Checklist do João**, no iPhone, com o `mochad` e o app da fase:
  - [ ] Um `Agent` real em background aparece como card vivo, com a ferramenta atual, o tempo e a contagem mudando, e fecha com ✓ e os números finais.
  - [ ] Tocar no card abre o transcript do subagente, que atualiza ao vivo enquanto ele roda; voltar volta ao chat pai.
  - [ ] O selo "N subagentes" aparece no card da Home e some quando todos terminam, inclusive com o Claude principal já ocioso (em CONCLUÍDOS).
  - [ ] O Detalhe lista os subagentes da sessão, com o aninhado recuado sob o pai, e tocar numa linha abre o transcript.
  - [ ] Um subagente que falha mostra ✗, "falhou" e o motivo em inglês no fim do transcript; um parado pelo `TaskStop` mostra ■ e "Parado".
  - [ ] Um workflow real mostra as fases avançando, os agentes da fase atual com a ferramenta, e recolhe numa linha no fim; tocar num agente abre o transcript dele.
  - [ ] O aviso `Agent "…" finished` não aparece no chat.
  - [ ] O chat de sessão arquivada e o chat de agente continuam funcionando como antes.

---

## Fase 1b: completar o MVP

**Ondas**
- Branch `fase/1b`, criada a partir de `fase/subagentes`.
- **Onda 3.A**, em paralelo: WP-M7 · S6.
- **Onda 3.B**, em paralelo: WP-M8 · WP-M9. Antes da onda, o orquestrador cria em `MochaKit/Sources/MochaDaemonCore/LiveActivity/` o protocolo que recebe um `LiveActivityRegistration` (usado pelo `registerLiveActivity` do WP-M8 e pelo `POST /v1/live-activity` do WP-M9).
- **Onda 3.C**, em paralelo: WP-I8 · WP-I9 · WP-I10.
- **Onda 3.D**: WP-X3.

### WP-M7: pedidos pendentes

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Pending/`, extensões em `Hooks/`, rota `POST /v1/respond`.
- **Faz**: `PendingStore` com um pedido por sessão, criação a partir do `PermissionRequest` (permissão ou pergunta), respostas de §8.2 e os desfechos de §8.3; sem `PreToolUse` e sem `send_keys`.
- **Depende de**: S3, WP-M1 e WP-M2 (status do Herdr e `tool_result` do transcript para §8.3), WP-M5, WP-M6, B7.
- **SPEC**: §8, §5.3 (`respond`, `pending`), §5.5, §7.1 (`PERMISSION`/`QUESTION`).
- **Aceite**:
  - [ ] Testes dos desfechos de §8.3 a partir dos `sequence.*.jsonl`: celular (allow, deny, answers), terminal "Yes" (status e transcript), terminal "No"/Esc (conexão fechada) e tempo (580 s).
  - [ ] As respostas codificam igual a `response.PermissionRequest.*.json`.
  - [ ] `respond` com pergunta sem resposta → `invalidPayload`; `allow` em pergunta e `answers` em permissão → `invalidPayload`.
  - [ ] Push com as categorias certas.

### WP-M8: Live Activity no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/LiveActivity/`, o envio `liveactivity` em `Push/` e o tratamento da mensagem WS `registerLiveActivity` no `SessionHub`. Não mexe em rotas HTTP (são do WP-M9 nesta onda). A nova tab saiu para o WP-M12 (1a-final).
- **Depende de**: S4, WP-M6.
- **SPEC**: §7.3, §5.3 (`registerLiveActivity`).
- **Faz**: usa `LiveActivityPush` e `LiveActivityContentState` de `Push/` (datas em segundos desde 2001, testado). Regras de prioridade da §7.3 nova. Push-to-start com `alert` + `input-push-token: 1`. `stale-date` = agora + 15 min a cada update. No máximo 10 push-to-starts por hora (a renovação de 7 h 50 min usa um). O token de update de uma atividade iniciada por push chega por `registerLiveActivity` 2–40 s depois do start. Antes disso, o daemon só guarda o estado. A rota HTTP `POST /v1/live-activity` é do WP-M9; o WP-M8 expõe a interface que ela chama.
- **Aceite**:
  - [ ] Testes da máquina de estados: início, atualização com o limite de 10 s, prioridade 10 em mudança de contagem, destaque ou fim e 5 só em mudança de título, fim depois de 60 s ocioso, renovação às 7 h 50 min.
  - [ ] Teste: o `content-state` codifica datas em segundos desde 2001.

### S6: voz em pt-BR

- **Dono**: `docs/spikes/S6.md`.
- **Faz**: confirma `SpeechTranscriber.supportedLocales` com pt-BR no iPhone, o download do modelo, a latência de resultados parciais e a qualidade com termos técnicos.
- **Aceite**:
  - [ ] `S6.md` com o resultado e as configurações recomendadas.

### WP-I8: inbox e ações de notificação

- **Dono**: `App/Sources/Inbox/`, extensões em `App/Sources/Notifications/`, o card do pedido no chat (`App/Sources/Chat/Pending*`), o sino da Home (`App/Sources/Home/InboxButton*`) e o botão "Responder" do Detalhe (`App/Sources/AgentDetail/Respond*`).
- **Depende de**: WP-M7.
- **SPEC**: §6.3 (Pedido no chat, Inbox, Detalhe do agente), §7.2.
- **Faz**: folha da Inbox aberta pelo sino da Home, com a contagem; card do pedido no fim do chat com o disco âmbar; "Responder" no Detalhe; ações na notificação. Telas `10-pedido-aprovacao`, `10b-pergunta` e `13-inbox`.
- **Aceite**:
  - [ ] Aprovar pelo inbox, pela notificação com o app encerrado (Face ID pedido), e negar.
  - [ ] Responder uma pergunta de opção única pela notificação e uma com várias perguntas pelo app.
  - [ ] Capturas no demo comparadas com `10-pedido-aprovacao`, `10b-pergunta` e `13-inbox`.

### WP-I9: Live Activity no app

- **Dono**: `Widgets/`, `App/Sources/LiveActivity/`.
- **Depende de**: WP-M8.
- **SPEC**: §7.3.
- **Faz**: parte do protótipo `App/Sources/LiveActivity/` (`AgentsActivityController`, `LiveActivityTokenStore`) e de `Widgets/Sources/AgentsLiveActivity.swift`. O gancho no `AppDelegate` já existe. Quando o app é acordado em background por push-to-start, manda o token com `POST /v1/live-activity` (Bearer), porque não há WebSocket aberto. Em primeiro plano, manda `registerLiveActivity` pelo WS. O visual segue a §7.3 e os prints (a linha "atualizado às … há …" é só da sonda). No fim do WP, apaga `App/Sources/Debug/PushProbe*` e o caso `push` do `DebugProbe` em `AppShell/RootView.swift`. Push-to-start e token de update só testáveis no iPhone. Dynamic Island capturada no simulador com `simctl io … screenshot --mask=black`.
- **Ações na atividade** (pedido do João em 2026-09-27): com `pending` no `ContentState` (§7.3), "Negar"/"Permitir" e as opções de pergunta como `Button(intent:)` com `LiveActivityIntent`, que fazem `POST /v1/respond`. Exceção de dono nesta onda: `project.yml` (intent compilado no app e no widget).
- **Aceite**:
  - [ ] Tela bloqueada capturada no device, e Dynamic Island (compacta, mínima e expandida) capturada no simulador (iPhone 18 Pro), porque o iPhone 14 do João não tem Dynamic Island.
  - [ ] Início por push-to-start com o app encerrado.
  - [ ] Permitir (com Face ID), Negar e responder uma pergunta pela atividade na tela bloqueada.

### WP-M16: destaque da Live Activity no estilo do Moshi (daemon)

- **Dono**: `MochaKit/Sources/MochaDaemonCore/LiveActivity/`, `Push/LiveActivityPush.swift`.
- **Depende de**: WP-M15.
- **SPEC**: §7.3 (campos do `highlight`).
- **Faz**: o espelho `LiveActivityContentState.Highlight` ganha `tabTitle`, `model`, `contextLeftPercent`, `preview` e `activity`, preenchidos da árvore; omitidos quando nulos; `preview`/`activity` omitidos com `pending`. Mudança só em `preview`/`activity`/`contextLeftPercent` é prioridade 5; troca de destaque continua 10.
- **Aceite**:
  - [ ] Testes: campos preenchidos da árvore, omitidos com `pending`, prioridades e payload ≤ 4 KB no pior caso.

### WP-I16: Live Activity no estilo do Moshi (widget)

- **Dono**: `Widgets/`, `MochaKit/Sources/MochaClient/LiveActivity/`.
- **Depende de**: WP-I9 (paralelo ao WP-M16, pelo contrato da §7.3).
- **SPEC**: §7.3 (tela bloqueada), referência `docs/referencias/moshi/live-activity.jpg`.
- **Faz**: o card da tela bloqueada e a Dynamic Island expandida no layout do Moshi, com as ações do WP-I9 no mesmo card.
- **Aceite**:
  - [ ] Testes dos textos (linha 1/linha 2, modelo, contagem) e build; conferência no iPhone com o João.

### WP-M17: uma Live Activity por agente (daemon)

- **Dono**: `MochaKit/Sources/MochaDaemonCore/LiveActivity/`, `Push/`, `Devices/`, `mochad/ApnsCommand.swift`.
- **Depende de**: WP-M16.
- **SPEC**: §7.4.
- **Faz**: `devices.json` guarda uma atividade por agente; o serviço inicia, atualiza e encerra uma atividade por agente (máx. 5, `blocked` ocupa a vaga da parada mais antiga, fim após 30 min parado ou quando o agente some); o alerta vai no update da atividade e o `PushService` não manda a notificação da §7.1 a um aparelho com a atividade do agente; o payload inteiro cabe em 4 KB.
- **Aceite**:
  - [x] Testes: ciclo por agente, alertas e supressão, limite de 5 com despejo, fim em 30 min, payload ≤ 4 KB com alerta.

### WP-I17: uma Live Activity por agente (app e widget)

- **Dono**: `Widgets/`, `App/Sources/LiveActivity/`, `MochaKit/Sources/MochaClient/LiveActivity/`.
- **Depende de**: WP-I16 (paralelo ao WP-M17, pelo contrato da §7.4).
- **SPEC**: §7.4.
- **Faz**: widget em `MochaAgentAttributes` com cabeçalho "**projeto** · tab · modelo" e paleta do Moshi; o app inicia a atividade do agente em primeiro plano, manda o token com `agentId`, encerra duplicadas e as agregadas antigas.
- **Aceite**:
  - [x] Testes dos textos, do rastreador, dos tokens e do contrato com o daemon; build do iPhone.
  - [ ] Conferência no iPhone com o João.

### WP-M15: pedido pendente na Live Activity

- **Dono**: `MochaKit/Sources/MochaDaemonCore/LiveActivity/`, `Push/LiveActivityPush.swift`.
- **Depende de**: WP-M7, WP-M8.
- **SPEC**: §7.3 (`pending`).
- **Faz**: o espelho `LiveActivityContentState` ganha `pending`; o snapshot do `LiveActivityService` leva o pedido pendente mais antigo (com o `highlight` no agente dele) e as regras de `text`/`options` da §7.3; `pending` que aparece, some ou troca de `requestId` é prioridade 10.
- **Aceite**:
  - [ ] Testes: permissão, pergunta inline (texto e rótulos exatos), pergunta não inline, pedido resolvido, prioridade 10, `options` sempre codificado e o `content-state` decodificável pelo `JSONDecoder` padrão.

### WP-I10: voz

- **Dono**: `App/Sources/Voice/`, e o botão de microfone no composer expandido (oculto antes desta fase).
- **Depende de**: S6, WP-I5.
- **SPEC**: §6.4.
- **Aceite**:
  - [ ] Ditado em pt-BR no device, com parcial e final no campo, sem envio automático.

### WP-M9: rota de Live Activity no daemon

- **Dono**: a rota HTTP `/v1/live-activity` em `Gateway/`. Não mexe no tratamento de mensagens WS (é do WP-M8 nesta onda). O upload saiu para o WP-M11 (1a-core).
- **Depende de**: WP-M3.
- **SPEC**: §5.5, §10.
- **Faz**: a rota `POST /v1/live-activity` (§5.5, Bearer, com a verificação do WP-M11), que repassa o `LiveActivityRegistration` para a mesma interface que o WP-M8 usa no `registerLiveActivity` (fake nos testes).
- **Aceite**:
  - [ ] Testes da rota: 401 sem Bearer, 200 repassando o `LiveActivityRegistration` ao fake.

### WP-X3: integração da 1b

- **Checklist do João**:
  - [ ] Aprovação e pergunta pelo inbox e pela notificação.
  - [ ] Live Activity com 2 agentes trabalhando e 1 bloqueado.
  - [ ] Ditado em pt-BR, conferindo no iPhone o `supportedLocales`, o download do modelo e a latência dos parciais (resto do S6).
  - [ ] Imagem.
  - [ ] Um dia inteiro de uso sem abrir o Moshi.

---

## Fase 1b-feed: Live Activity follow-up

Branch `fase/1b-feed`, criada de `main` em 2026-09-27. Onda 1: orquestrador (SPEC §7.5, `MochaFeedAttributes`). Onda 2: WP-M18 ∥ WP-I18 ∥ WP-M19. Depois o WP-XF, o merge em `main` e o merge de `main` na `fase/codex` antes do WP-C2. Bloqueios do João: a reprodução do WP-M19 (aceitar um plano pela tela bloqueada e, na segunda rodada, desligar o `moshi-hook` do `PermissionRequest`) e a conferência no iPhone.

### WP-M18: card follow-up (daemon)

- **Dono**: `MochaKit/Sources/MochaDaemonCore/LiveActivity/`, `Push/`, `Devices/`, `mochad/ApnsCommand.swift` e os testes correspondentes.
- **SPEC**: §7.5 (e o que a nota da §7.4 mantém).
- **Faz**: uma atividade por aparelho em `devices.json` e no `LiveActivityService`; seletor de foco (pedido mais antigo, senão evento mais recente); `agentId` no espelho `LiveActivityContentState`; `attributes-type` `MochaFeedAttributes`; alerta no update que traz o foco e supressão da §7.1 para todo agente enquanto o aparelho tem card com token; sem limite de 5 nem despejo; `mochad apns liveactivity` no tipo novo.
- **Aceite**:
  - [x] Testes: troca de foco por `preview` nova e por `status`; pedido segura o foco; vários pedidos → o mais antigo; volta ao evento mais recente; mudança de `activity` do agente em foco sem troca; alerta no update e supressão da §7.1; evento de outro agente com o card preso num pedido sai pela §7.1; prioridade 10 na troca; fim em 30 min; payload ≤ 4 KB; registro antigo com `agentId` ignorado.

### WP-I18: card follow-up (app e widget)

- **Dono**: `Widgets/`, `App/Sources/LiveActivity/`, `MochaKit/Sources/MochaClient/LiveActivity/`, `Shared/LiveActivity/` (exceto o que o WP-M19 muda em `PendingActivityIntents.swift`: mudanças nesse arquivo vão como diff no relatório) e os testes correspondentes.
- **SPEC**: §7.5.
- **Faz**: widget em `MochaFeedAttributes`, com o `agentId` do estado no deep link e nas ações; o app controla uma atividade só (início local com o foco pelo critério da §7.5), encerra as `MochaAgentAttributes` e `MochaAgentsAttributes` ao abrir e registra os tokens sem `agentId`.
- **Aceite**:
  - [x] Testes do foco no app, dos textos, dos tokens e do contrato com o daemon; `scripts/build-app.sh`.
  - [x] Conferência no iPhone com o João (WP-XF).

### WP-M19: aceitar plano pela tela bloqueada

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Pending/`, `MochaKit/Sources/MochaClient/Pending/`, `App/Sources/LiveActivity/PendingActivityResponder.swift`, `Shared/LiveActivity/PendingActivityIntents.swift`, `MochaKit/Fixtures/hooks/` e os testes correspondentes.
- **SPEC**: §7.2, §7.3 (Ações), §8.
- **Faz**: primeiro a causa raiz (reprodução com `log stream` do subsistema `com.joaoalves.mocha`, com e sem o `moshi-hook`), reportada ao João antes de mudar código. Hipóteses: o pedido fecha antes da resposta (`PendingStore` por `session_id` com subagente, ou o pane saindo de `blocked`) e o 404 passa em silêncio; ou o `moshi-hook` decide o `ExitPlanMode` sozinho. Depois, o fix da causa; a notificação local quando a resposta pela Live Activity ou pela notificação volta 404/400 (§7.3); e o texto do plano ("Claude quer seguir o plano", a primeira linha do plano sem markdown, botões "Negar" e "Aprovar").
- **Aceite**:
  - [x] Causa reproduzida e registrada no relatório, com o payload do `PermissionRequest` do `ExitPlanMode` em `Fixtures/hooks/`.
  - [x] Testes de cada fix.
  - [x] Aceitar plano pela tela bloqueada no iPhone (WP-XF).

### WP-XF: integração da 1b-feed

- **Checklist do João** (iPhone, três agentes): um card só na tela bloqueada; o card troca para o agente que mandou mensagem; um pedido segura o card; Permitir, Negar, resposta de pergunta e aceitar plano pela tela bloqueada; alerta no card sem notificação duplicada; o card some 30 min depois de tudo parar.

## Fase Codex: CLI no Herdr, desktop como complemento

Branch `fase/codex`, criada de `main` antes do WP-X3. A SPEC §13 define o contrato desta fase. Ondas: S7 → WP-C1 → WP-C2 ∥ WP-C3 → WP-C2-wiring → WP-XC → WP-CD. O desktop não bloqueia o aceite do CLI. Bloqueios do João: nenhum para S7 e os testes locais; revisar a configuração real do App Server e dos hooks antes da instalação, e validar no iPhone no WP-XC.

### S7: App Server compartilhado no laboratório

- **Dono**: `docs/spikes/S7.md` e laboratório `~/Developer/mocha-lab/S7/`, em workspace Herdr `mocha-lab-S7`. Não tocar sessões Codex existentes nem configuração real em `~/.codex`.
- Validar com CLI `codex --remote` e dois clientes App Server na mesma thread: associação pane–thread, histórico e eventos, retomada após queda, prompt, interrupção e permissão respondida no terminal ou no outro cliente. Testar pergunta estruturada nos modos em que a API permitir; no Default, a ausência dessa ferramenta é limitação aceita pelo João em 2026-09-27. Verificar formato e limites de `account/rateLimits/read`, imagem e subagentes. Registrar versão, comandos, payloads redigidos, resultados e mudanças necessárias na §13.
- **Gate**: passou para chat/aprovações no Default e perguntas no Plan, conforme `docs/spikes/S7.md`. Não usar `agent.send_keys` para reproduzir ações. Casos secundários não testados no spike passam ao WP-XC.

### WP-C1: protocolo v2 e fixtures Codex

- **Dono**: `MochaKit/Sources/MochaProtocol/`, `MochaKit/Fixtures/protocol/`, `MochaKit/Tests/MochaProtocolTests/` (exceção de dono compartilhado nesta onda: o orquestrador implementa).
- Identificar provedor em sessão e arquivo com migração dos registros Claude, suportar nova tab Codex, janelas de uso com duração da API, chat e pedidos Codex. Atualizar `MochaDemo` em WP-C3. Aceite: round-trip v2, rejeição explícita de versão incompatível e fixtures antigas Claude decodificadas.

### WP-C2: integração Codex no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Codex/`, adaptação de `Gateway/`, `Herdr/`, `Pending/`, `Push/` e `LiveActivity/` necessária à §13; testes em `MochaKit/Tests/MochaDaemonCoreTests/Codex/` e fixtures em `MochaKit/Fixtures/codex/`.
- Cliente App Server em actor, reconciliação pane–thread, conversão de itens/eventos, ações, decisões, uso, arquivos, subagentes e diagnóstico. O daemon usa socket local, não JSONL. Aceite: fixtures unitárias sem rede, Herdr ou Codex reais; integração real somente com tag `.integration`.

### WP-C2-wiring: ligar o CodexService no mochad

- **Dono**: o mesmo do WP-C2, mais `App/DaemonRuntime.swift`, `App/Doctor*.swift`, `mochad/StatusCommand.swift` e o uso por provedor em `App/Sources/AppShell/` e `App/Sources/AgentDetail/`. Branch `wp/C2-wiring`.
- O WP-C2 entregou as peças sem ligá-las ao daemon. Este WP faz o `mochad` subir e supervisionar o App Server, liga o `CodexService` ao `SessionHub` (árvore, status, chat, ações, pendentes, push), abre a nova tab Codex com `codex --remote`, associa pane e thread por `thread/started` (§13.1) e põe o item Codex no `doctor`. Aceite: `scripts/test.sh` verde, com testes do `CodexPaneMatcher`; `scripts/build-daemon.sh` e `scripts/build-app.sh` compilam. O teste real fica no WP-XC.

### WP-C3: Codex no app e no demo

- **Dono**: `App/Sources/`, `MochaKit/Sources/MochaClient/Presentation/`, `MochaKit/Sources/MochaClient/Pending/`, `MochaKit/Sources/MochaDemo/`, `docs/design/` e testes correspondentes. Mudanças em `project.yml` e `MochaProtocol` são propostas ao orquestrador.
- Estender o mock em `docs/design/` antes da UI, com imagens de referência 3x. Mostrar Codex na Home, gaveta, Detalhe, chat, nova tab, Uso, inbox, alertas e Live Activity, inclusive estado indisponível e capacidade limitada do CLI antigo. Aceite: capturas comparadas ao mock e testes de navegação e apresentação.

### WP-XC: integração do CLI

- **Checklist do João**: uma tab Codex criada no Herdr com associação pane–thread comprovada; conversa única entre terminal e iPhone; prompt e imagem; interrupção; aprovação nos dois sentidos e pergunta em Plan mode vencidas ora no terminal, ora no iPhone; queda e volta do App Server, inclusive com ação em trânsito; uso, subagentes, push e Live Activity; Claude segue funcionando. Usar `scripts/test.sh`, `scripts/build-app.sh` e `scripts/build-device.sh` (este último após oferta de teste no iPhone).

### WP-CD: leitura do Codex desktop

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Codex/`, `App/Sources/Home/`, `App/Sources/Drawer/`, `App/Sources/Chat/` e testes correspondentes. Propor alterações no protocolo ao orquestrador.
- Listar e paginar threads desktop sem retomá-las, até 20 recentes na Home e todas na gaveta. Estado desconhecido quando o App Server não comprova atividade. Preparar o diff exato dos hooks para revisão do João antes de instalar; a leitura funciona sem eles. Aceite: nenhuma ação de controle aparece para conversa desktop.

## Fase início: Início, Histórico e gaveta só no chat

Branch `fase/inicio`, criada de `main`. Um WP só, feito direto pelo orquestrador a pedido do João. Daemon e protocolo não mudam.

### WP-H1: Início, Nova sessão, Histórico e gaveta só no chat

- **Dono**: `App/Sources/Home/`, `App/Sources/NewSession/`, `App/Sources/AppShell/`, `App/Sources/Drawer/`, `App/Sources/Chat/`, `App/Sources/DesignSystem/ChatHeaderBar.swift`, `MochaKit/Sources/MochaClient/Presentation/` e testes.
- A Home vira o Histórico, a Início nova (§6.3) fica à direita dele num paginador, a folha Nova sessão substitui o `+` da gaveta, a gaveta só abre no chat pela borda esquerda e a bússola fica desabilitada. Aceite: `scripts/test.sh` e `scripts/build-app.sh` passam; o João confere gestos e a criação de uma tab no iPhone.

## Fase preview-web: servidores web do Mac no iPhone

Branch `fase/preview-web`, criada de `fase/header` a pedido do João. Ondas: contrato (orquestrador) → WP-W1 ∥ WP-W2 ∥ WP-W3 → contrato da chave do host → WP-W3b ∥ WP-W4 → WP-W5. SPEC §5.3 (`listWebServers`, `webServers`), §6.3 (cápsula do header, Servidores web, Navegador) e §9.3. Referência visual: `docs/referencias/moshi/servidores-web.jpg`, sem o card de usos grátis. Bloqueio B5 só no WP-W5. O WP-W1 e o WP-W4 adiantam o WP-T1 e o WP-T3 da Fase 2: a conexão SSH e a chave são as mesmas, e na Fase 2 falta só o PTY com `herdr agent attach`.

### Contrato (orquestrador)

- Protocolo e fixtures (`WebServer`, `listWebServers`, `webServers`), tratamento mínimo no demo e no daemon (lista vazia), `NSAllowsLocalNetworking` no `App/Info.plist`, SPEC e este bloco.

### WP-W1, spike: SSH com a chave da Secure Enclave e `direct-tcpip`

- **Dono**: `docs/spikes/W1.md` e `App/Sources/Debug/SSHProbe*`.
- Confere na API do Citadel: autenticação `ecdsa-sha2-nistp256` com `SecureEnclave.P256.Signing.PrivateKey` (ou um delegate próprio), abertura de canal `direct-tcpip` e cópia de bytes nos dois sentidos, e um `NWListener` em `127.0.0.1` repassando cada conexão por um canal. Com o B5 feito, carrega um Vite do Mac num `WKWebView` com HMR; sem ele, fica compilado com a chamada real num botão da tela de Debug.
- **Aceite**: `W1.md` com a API exata do Citadel usada, os tipos e o que muda em §9.1/§9.3 ("Impacto").

### WP-W2: descoberta de servidores no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/WebServers/`, o caso `listWebServers` em `SessionHubConnection.swift` e `MochaKit/Tests/MochaDaemonCoreTests/WebServers/`.
- `WebServerScanner` como em §9.3: processos por `libproc`, filtros, sonda HTTP com timeout e `<title>`. A leitura de processos e a sonda ficam atrás de protocolos injetáveis; os testes usam falsos (nada de rede real). Um teste `.integration` sobe um `HttpServer` do próprio MochaKit numa porta efêmera e confere que ele aparece.
- **Aceite**: `scripts/test.sh` verde; parse do `<title>` com entidades, sem título, HTML grande e sem HTML; timeout; porta duplicada; portas do `mochad` excluídas.

### WP-W3: cápsula do header e folha Servidores web

- **Dono**: `App/Sources/Home/RootHeader.swift`, `App/Sources/WebPreview/` (menos `Browser*`), o estado da lista em `App/Sources/AppShell/AppSession*` (só o necessário: `showWebServers()`, pedir e guardar a resposta) e o `listWebServers` do demo em `MochaKit/Sources/MochaDemo/` (dois servidores como no print).
- Cápsula de vidro com sino (só com pedido), globo e engrenagem; folha Servidores web da §6.3 com estados carregando, vazia e sem conexão; `-open-web-servers` só em Debug para a captura. Tocar numa linha chama `WebPreviewOpener.open(_:)`, que por enquanto não faz nada.
- **Aceite**: `scripts/test.sh` e `scripts/build-app.sh` verdes; capturas da Início e da folha comparadas ao print, com as diferenças listadas.

### Contrato da chave do host (orquestrador, antes da onda 2)

- `HostInfo.sshUser` e `HostInfo.sshHostKeys`, `SSHHostIdentity` no daemon, `server.helloOk.ssh.json` e SPEC §5.2 e §9.1. Decisão do João: fixar a chave do host pelo `helloOk`, sem confiar na primeira conexão.

### WP-W3b: painel próprio para Servidores web

- **Dono**: `App/Sources/WebPreview/` (menos `Browser*`) e a apresentação em `App/Sources/AppShell/AppShellView.swift`.
- Decisão do João: a folha do sistema sai (fica recuada das bordas no iOS 26) e entra o mesmo painel da folha de Uso (`UsagePanelLayer` em `App/Sources/Usage/`), colado às bordas, com o topo em ~50% da tela como no print. Generalizar o painel do Uso sem mudar o visual dele. O puxar para recarregar sai (conflita com arrastar para fechar): a lista recarrega ao abrir e quando a conexão volta.
- **Aceite**: `scripts/build-app.sh` verde; captura com `-demo -open-web-servers` comparada ao print (bordas, altura do topo, tipos) e a do Uso sem regressão.

### WP-W4: sessão SSH, túnel e Navegador

- **Dono**: `App/Sources/Terminal/Session/`, `App/Sources/Settings/SSH*`, `App/Sources/WebPreview/Browser*` e `WebPreviewOpener`.
- Conexão SSH única (§9.1) com a chave da Secure Enclave, a chave pública em Ajustes (copiar), `PortForwarder` e o Navegador da §6.3, com reabertura ao voltar do background (§9.3). Parte do `docs/spikes/W1.md` e do código `App/Sources/Debug/SSHProbe*`. Usuário e chave do host vêm do `helloOk` (§9.1). O `SSHProbe*` sai no fim do WP, substituído pelo código de produção.
- **Aceite**: `scripts/test.sh` (o `PortForwarder` com canal falso) e `scripts/build-app.sh` verdes; captura do Navegador com uma página local servida pelo próprio teste.

### WP-W5: checklist no iPhone

- Com o B5: a folha lista os servidores reais; "Portal do cliente" abre; uma edição no código atualiza a página por HMR; fechar e reabrir; mandar o app para o background e voltar recarrega.

## Fase controles: modelo, effort, modo e painel do chat

Branch `fase/controles`, criada de `main`. Ondas: S8 → WP-K1 → WP-K3 → WP-K4. Sem mock nem capturas (decisão do João): a referência visual é o print do seletor do Moshi e os componentes que o app já tem. Decisões do João (2026-09-28):

- **Header do chat**: o toque no título abre o seletor de modelo e effort; o long press abre o detalhe do agente; o anel de contexto aparece no header.
- **Menu `↻`**: vira painel de controles com contexto, uso (5 h e semanal), modo (Edição / Auto / Plano), subagentes e workflows da sessão, `/compact` e `/clear`. `/context` e `/cost` saem.
- **Botão de enviar**: com o campo vazio, sem anexo e com o agente trabalhando, vira parar (`interrupt`). "Interromper" sai do menu.

A SPEC §6.3 muda no fim do S8: cai a regra "`/model` fica fora".

### S8: modelo, effort e modo pelo Herdr

- **Dono**: `docs/spikes/S8.md` e o laboratório `mocha-lab-S8` (`~/Developer/mocha-lab/S8/`). O Claude de teste roda com `claude --setting-sources project,local --settings <arquivo>`.
- **Perguntas**:
  - **Shift+Tab**:
    - qual nome de tecla o `agent.send_keys` aceita (`shift+tab`, `btab`, `S-Tab`)?
    - a API do Herdr lê o rodapé do pane (`⏵⏵ accept edits on`, `⏸ plan mode on`, `⏵⏵ auto mode on`)?
    - um laço "Shift+Tab, ler, repetir até o modo alvo, no máximo 5 vezes" fecha em menos de 1,5 s?
  - **`/model <alias>` via `agent.prompt` com cache quente**: a confirmação aparece? Um hook `PreModelSwitch` com `permissionDecision: "allow"` a elimina?
  - **Agente trabalhando**: `/model` e `/effort <nível>` entram na fila ou voltam `agent_blocked`?
  - **Hooks**: o hook `Stop` real traz `effort.level` e `permission_mode`? O `PostModelSwitch` traz o modelo novo?
  - **Padrão global**: existe forma com argumento de trocar o modelo só na sessão? Sem ela, a troca muda o padrão das próximas sessões.
- **Aceite**: `S8.md` com as respostas, os comandos exatos e o "Impacto" em §4, §5 e §6.3 e nos WP-K1 e WP-K3.

### WP-K1: modelo, effort e modo no protocolo e no daemon

- **Dono**: `MochaKit/Sources/MochaDaemonCore/` (Gateway, Hooks, Herdr), `MochaKit/Sources/MochaHerdr/` e testes. O protocolo e as fixtures ficam com o orquestrador, antes da onda.
- **Protocolo**:
  - `effort` no resumo do agente e no `ChatMeta`;
  - `permissionMode` e `model` atualizados pelos hooks, sem esperar o transcript;
  - mensagens `setModel`, `setEffort` e `setMode`, validadas contra listas fixas.
- **Daemon**:
  - `setModel` e `setEffort` valem só para a sessão (decisão do João, 2026-09-28): abrem o seletor (`/model` ou `/effort`), leem com `pane.read`, andam com `up`/`down` ou `left`/`right` e confirmam com `s`. A forma digitada fica proibida, porque grava no `~/.claude/settings.json`;
  - `setMode` é o laço `shift+tab` + `pane.read` do rodapé, com detecção de mudança (S8, Decisões 1);
  - antes de cada `agent.prompt`, seletor ou diálogo na tela contam como bloqueio;
  - `pane.read` entra no `HerdrRequest`/`HerdrClient` e no `FakeHerdrServer`;
  - `PreModelSwitch` condicional (allow só com `setModel` pendente no pane) e `PostModelSwitch` entram no `install-hooks`;
  - `Stop`, `PreToolUse` e `PostModelSwitch` atualizam `model`, `effort` e `permissionMode`.
- **Aceite**: `scripts/test.sh` verde, com `FakeHerdrServer` (rodapés e seletores de fixture) e as amostras de hook do S8 como fixtures. Detalhes em `docs/spikes/S8.md` ("Impacto").

### WP-K3: controles no app

- **Dono**: `App/Sources/Composer/`, `App/Sources/DesignSystem/ChatHeaderBar.swift`, `App/Sources/DesignSystem/ComposerBar.swift`, `App/Sources/Chat/ChatScreen.swift`, `MochaKit/Sources/MochaDemo/` e testes.
- **Header**: toque → seletor; long press → `showDetail`; `ContextRing` no header.
- **Painel**: o `SlashMenu` vira o painel de controles, que lê `session.usages` e `contextLeftPercent` e lista os subagentes e workflows da sessão (reúso de `App/Sources/AgentDetail/AgentSubagentsSection.swift`). Tocar num subagente abre o chat dele, como o card faz.
- **Composer**: o botão de enviar ganha o estado parar.
- **Seletor**:
  - mostra o valor escolhido até o daemon confirmar pelo rodapé ou pelo hook;
  - no Haiku, `auto` fica cinza com a legenda "Indisponível no Haiku" e o effort some.
- **Aceite**: `scripts/test.sh` e `scripts/build-app.sh` verdes. A conferência visual é no iPhone, no WP-K4.

### WP-K4: checklist no iPhone

- Trocar o modelo e o effort, girar os três modos, abrir um subagente pelo painel, `/compact`, `/clear` e parar pelo botão de enviar. Tudo aparece no terminal e no app em até 2 s.

## Fase 2: terminal SSH

Branch `fase/2`, criada a partir de `fase/1b`. Ondas: WP-T1 → WP-T2 ∥ WP-T3 → WP-X4.

- **WP-T1**, spike: chave da Secure Enclave no Citadel (autenticação `ecdsa-sha2-nistp256` com o Mac) e `herdr agent attach <pane>` por SSH num PTY. Dono: `docs/spikes/T1.md` e, se o spike precisar de código, `App/Sources/Debug/SSHProbe*`. Bloqueio B5: sem ele, o spike confere a API do Citadel e compila a autenticação com testes, e a conexão real com o Mac vai para o checklist do WP-X4.
- **WP-T2**: folha de terminal (`SwiftTerm`) sobre o chat, barra de teclas de §9.1 e as entradas: "Abrir terminal" no Detalhe do agente e as tabs de shell da gaveta. Dono: `App/Sources/Terminal/View/`, o botão em `App/Sources/AgentDetail/` e o toque de shell em `App/Sources/Drawer/`. Aceite: captura comparada a `15-terminal`.
- **WP-T3**: conexão SSH, reanexar ao reconectar, gestão da chave e exibição da pública em Ajustes. Dono: `App/Sources/Terminal/Session/`, `App/Sources/Settings/SSH*`.
- **WP-X4**, checklist: abrir o terminal do agente atual, digitar, usar o prefixo do Herdr, trocar de rede e ver reanexar.

## Fase 3: Mosh

Branch `fase/3`, criada a partir de `fase/2`. Ondas: WP-T4 → WP-T5 → WP-X5.

- **WP-T4**: build do mosh e do protobuf para iOS como xcframework (a partir de `blinksh/build-mosh`), com script reproduzível em `scripts/`. Dono: `Vendor/mosh/`, `scripts/build-mosh.sh`.
- **WP-T5**: transporte Mosh na tela de terminal (§9.2). Dono: `App/Sources/Terminal/Mosh*`.
- **WP-X5**, checklist: a sessão sobrevive a 5 min de app em background e à troca de rede, sem reanexar.

---

## Status

Atualizado só pelo orquestrador, depois do commit de cada WP.

| WP | Status | Commit |
|---|---|---|
| WP0.1 | feito | f5adafc |
| WP0.2 | feito | 51ead39, 8bad988 |
| WP0.3 | feito | 6213de7 |
| S1 | feito | ce6ff4f |
| S2 | feito | 4648a76 |
| S3 | feito | 0c0c24c |
| S4 | feito | 51ef5f9, 86de9d4, bd5db4e |
| S5 | feito | 2fe94d0, 42ebb0f, 5c65255 |
| WP-D1 | feito | 393ec96, 0ecf4d2, f1045ef |
| WP-M1 | feito | a95f3c7, c54fabd, 146201b, 1303675 |
| WP-M2 | feito | b34bf17, 7f55ad2, 0ea19a6, 52dbc30 |
| WP-I1 | feito (arrastar da borda fica no checklist do WP-X1) | d09483f, fd07098, cab25c6, 1941ba0, e986b09, 8b040f3, 71bf186, 6dcadf6, cb378a0, merge cec977f, 9e28bea |
| Passo 1 (escopo B) | feito | 2fba5f9, be6bd8b, 5434975, d59f9d8 e os commits do protocolo |
| WP-D2 | feito | 83ff272, 6f35dc0, bc10208, merge cb5a698 |
| WP-M2b | feito (medição de 50 MB pendente numa janela sem build) | d8ab1b4, f13a3e4, 739718f, merge 97e13b4 |
| WP-M3 | feito (os READMEs de `Fixtures/` citam `docs/spikes/` e ficam como exceção do critério do `spike`) | 1b379f5, 7c9d306, f1bf707, merge 3f52771 |
| WP-I12 | feito (gestos no checklist do WP-X1) | 70ce184, a2713c0, 3508650, caa6aa4, 02b7c4f, merge 03a8201 |
| WP-I4 | feito; o critério de 16 ms passou a ser só dos blocos visíveis (medir com o WP-I5 numa janela sem build) | e93e84e, 2d28456, merge 4716495 |
| WP-M4 | feito (RSS de 10 min pendente numa janela sem build) | b17f5fc, a35700c, d044872, a4ae669, merge 953aa1f |
| WP-I3 | feito (arrastar para fechar no checklist do WP-X1) | 49d329d, d44971b, 6b51ad2, merge 63d873a |
| WP-I5 | feito (signpost dos 2.000 itens numa janela sem build; gestos no checklist do WP-X1) | 118affb, f8fd224, f621510, merge b0a067f |
| WP-I2 | feito (QR pela câmera, Keychain real e pareamento com o `mochad` no checklist do WP-X1) | dd92fce, 1f73158, 06354de, 147a24c, 0690dff, 4090942, merge 7d574b1 |
| WP-M10 | feito (plano, conta e `doctor` real no checklist do WP-X1) | e80cfe8, 78b0bce, bb172cb, 2d7b8c5, merge f8b3aea |
| WP-X1 | feito (aprovado pelo João no iPhone em 2026-09-26; correção do card de ferramenta `49520ac`) | 3c95e82, 49520ac |
| WP-M11 | feito | fe805ff, fdd4a93, 51fa807, merge 2ae5ac4 |
| WP-I13 | feito (fotos, câmera e colar no iPhone ficam no checklist do WP-X1) | ba007da, 51dd365, 5b7f1f5, 5635c99, 74488dc, merge 51cbacf |
| WP-M5 | feito (o `install-hooks` real fica para o WP-X2) | 955b277, 1913d7b, 80fcd6d, f680732, 90ac833, 1b0d0b3, ca1306c, merge 703c834 |
| WP-M6 | feito (`mochad apns test` real no iPhone fica no checklist do WP-X2) | f1e793c, d36734a, b656fdf, 7a74bff, 4be4a0e, c4d3540, merge ed8f2a1 |
| WP-I6 | feito (os três estados de abertura, o `apns-collapse-id` e o time-sensitive no iPhone ficam no checklist do WP-X2) | 4edb3b5, 361288d, ee32e67, 19d4f6c, merge 4a19f28 |
| WP-I7 | feito (`/compact` e `/clear` reais no checklist do WP-X2) | e4e6cdf, 1d31ff8, 082bf8c, d368311, merge 80ed3a9 |
| WP-I11 | feito (o `+` real, contra o daemon, no checklist do WP-X2 depois do WP-M12) | 4697966, ce21252, merge 3c11fdb |
| WP-M12 | feito (o `+` real, contra o Herdr, no checklist do WP-X2) | bd8cecf, 1dacb64, merge d97c1da |
| WP-X2 | feito (aprovado pelo João no iPhone em 2026-09-26) | 0c5e708 |
| Mock dos subagentes | feito | 95f2616, 0829b2f, merge 67347d0 |
| WP-M13 | feito | b4074ea, 95aed66, d83465c, merge 8a9388e |
| WP-D3 | feito | 050f7f9, 3de4a2d, merge 9b12d42 |
| WP-M14 | feito (exceção de dono: `MochaTranscript/Parsing/SubagentSignals.swift`, para o daemon reaproveitar o parser; o transcript principal é acompanhado enquanto a sessão tem subagente ou workflow rodando, com leitura incremental a cada evento de diretório da sessão) | 1d2c5f8, 4e1999b, 8f5a339, da14d05, c3bfd8b, 4ed4348, merge a877bdd |
| WP-I14 | feito (sem capturas: o João pediu só testes e build; exceção de dono: `MochaClient/Presentation/SubagentText.swift`, textos e tempos "1m 02s" do mock, reaproveitado pelo I15; `AppSession` guarda a pilha de chats com gerações por rota; nome da ferramenta na atividade do card sem negrito, como no mock) | 9db9da6, 81aef9d, 5edf9d0, merge 61b355b |
| WP-I15 | feito (sem capturas: o João pediu só testes e build; "N RODANDO" em caixa alta, como o `.dlab` do mock) | 48c7139, 57712b9, merge b187453 |
| WP-X6 | pulado por decisão do João (2026-09-27): checklist fica para o teste do app com ele | |
| WP-M7 | feito (a rota `respond` fica no `Gateway` ao lado da `live-activity`; sem `PendingStore`, `respond` devolve `unknownType`; pushes secundários calados enquanto há pedido pendente; `blocked` só conta depois da criação do pedido; pedido de subagente não vigia o transcript principal; decisões para o João revisar) | 11ef79a, 61443c3, ebf141d, merge 1964e95 |
| WP-M8 | feito (fora do dono: `Devices/DeviceStore.swift` ganha `setLiveActivity(_:for:)`, que tira os mesmos tokens de outros aparelhos; `invalidToken` → 400 na rota do WP-M9 e `invalidPayload` no WS; sem push-to-start com o app em primeiro plano; refresh p5 a cada 10 min enquanto há agente ocupado; o `start` não leva `stale-date` e a renovação de uma atividade adotada depois de reiniciar o daemon conta 7 h 50 min a partir da adoção) | f97e451, c8b5d9d, 92976ea, merge 8ce7514 |
| S6 | parte do Mac feita (pt-BR suportado, preset progressivo, 16 kHz mono); iPhone no WP-X3 | 4de4248 |
| WP-I8 | feito sem device (sem capturas: o João pediu só testes e build; exceção de dono: `MochaClient/Pending/`, com testes de contrato contra o `PendingHookReply` real; sino só com pedido pendente e conexão; sem `cwd:` na caixa do comando porque o `PendingRequest` não tem o campo; verbos "quer ler/editar/…" escolhidos pelo subagente; o `MochaDemo` não manda `pending`; o orquestrador alinhou o push de pergunta à §7.2 em `69d7b16`) | 3b2c6b9, 2e8440a, 89e815d, a418d63, merge 0b3d3b7, 69d7b16 |
| WP-I9 | feito sem device, com as ações da atividade (sem capturas: o João pediu só testes e build; exceções de dono: `project.yml` com `Shared/LiveActivity` nos dois alvos, `MOCHA_WIDGETS` e o widget ligado ao `MochaClient`, e `MochaClient/LiveActivity/`; subtítulo só "Mocha", porque o `ContentState` não traz o host; timer em SF Mono no widget; Dynamic Island só no simulador de um Pro) | 9e4beb6, 1314097, a548b8a, c88d363, 885f7c3, merge 47dc9a4 |
| WP-M15 | feito (agente com pedido conta como `blocked`; pedido de agente fora da árvore é ignorado; o `start` também leva o `pending`; o orquestrador acrescentou o orçamento de 3.200 bytes para o `pending` codificado: acima disso a pergunta vai como prévia sem opções) | 7942c30, 87c2b64, merge 1d1ed12 |
| WP-M16 | feito (`preview` só do assistente, ajuste do orquestrador; orçamento de 3.840 bytes com descarte dos campos opcionais; resta o caso extremo de `title`/`workspaceLabel` com emoji de 8 bytes somados a um `pending` perto de 3.200 bytes, que passa de 4 KB) | cd2b311, c925b30, merge d96e192 |
| WP-I16 | feito (linha 2 repete o texto em cinza quando a linha 1 corta; cores da SPEC, mais fortes que as do Moshi; atividade iniciada pelo app só ganha modelo/contexto no primeiro update do daemon; base visual do card por agente) | 1e1b4f6, ca6f061, 8a15786, merge 06c9352 |
| WP-M17 | feito (alerta também em `blocked` sem pedido; encaixe do payload inteiro em 4 KB fecha o caso extremo do WP-M16; token recusado espera o próximo turno para reiniciar) | 1e7a0ae, 4bb7670, 804f6b4, b2bfa88, merge 844d58a |
| WP-I17 | feito (`MochaAgentsAttributes` fica só para encerrar atividades agregadas antigas; compacta mostra o projeto; conferência no iPhone pendente) | e0a6228, 0985dc1, bcdd56d, merge 844d58a |
| WP-I10 | feito sem device (parcial numa linha sob o campo, porque o `TextField` de `String` não pinta só um trecho; o modelo é sempre pedido pela `assetInstallationRequest`, que reserva o locale; o ditado começa sozinho depois do download; conferência no iPhone no WP-X3) | 24f6934, e76d990, c9e046a, 35f6e3a, merge c087148 |
| WP-M9 | feito (rota ligada ao `LiveActivityRegistering`; o `DaemonRuntime` passa o componente real do WP-M8 no merge dele; corpo inválido → 400) | 85a3967, merge 95d1574 |
| WP-X3 | todo | |
| WP-M18 | feito (alertas que o card não mostra saem pela §7.1 via `LiveActivityAlertFallback`, guardados até 60 s; com o app aberto o card atualiza sem alerta; `PushServiceTests.blockedWithoutARequestAlertsAfterTheGraceOnlyForClaude` segue instável, corrida do teste anterior à fase) | 3d3941b, 3199f2c, deeb05c, merge 2f6625e |
| WP-I18 | feito (foco local pelo pedido visto primeiro, senão a última mudança de status; o daemon corrige no primeiro update) | ed1484e, 17bff10, merge d297c23 |
| WP-M19 | feito (causa: `allow` sem `updatedInput` no `ExitPlanMode`, ignorado pelo Claude; aprovar manda o input original + `setMode` `auto`; pedido de subagente não fecha o do agente principal; 404 avisa; fixture de entrada sintetizada pela doc) | fix(daemon), fix(app), test(daemon), merge |
| WP-XF | feito (aprovado pelo João no iPhone em 2026-09-27) | |
| S7 | gate aprovado para escopo ajustado; casos secundários no WP-XC | 26067bd, merge e704dcb |
| WP-C1 | feito (73 testes do protocolo passaram; pacote completo aguarda C2/C3 para tratar os novos casos) | d166607, 8fe544f, merge 1361c9f |
| WP-C2 | feito (peças sem a ligação no daemon; ver WP-C2-wiring) | 3ce45c9, 22f5a52, merge f8d43da |
| WP-C3 | feito | 2f44cfb, 1e74585, f8defbf, 9a65999, df1e7e4, e01a435, merge c62b69d; correções 66d0821, 826fafa, 9f88a98, 7e16e2b |
| WP-C2-wiring | feito (testes e builds passaram; sem teste real, que fica no WP-XC) | merge em `fase/codex` |
| WP-XC | todo | |
| WP-CD | todo | |
| WP-H1 | feito sem device (testes e build passaram; gestos e tab real a conferir no iPhone) | `fase/inicio` |
| WP-W1 | feito (build passou; conexão real depende do B5, no WP-W5) | deedcf1 |
| WP-W2 | feito (testes do WP e integração passaram; suíte completa com 1 falha de latência fora do WP, sob carga) | 990f09a |
| WP-W3 | feito com pendência visual (folha recuada das bordas; decisão do João) | d49ccf2 |
| WP-W3b | done | `32b5b7f` (painel próprio; test.sh com 2 falhas de tempo sob carga a reconferir) |
| WP-W4 | done | `80e683d` (SSH e Navegador; conexão real no WP-W5 com o B5) |
| WP-W5 | done | ok do João no iPhone: lista, túnel, Navegador, bússola por workspace e anéis |
| S8 | feito (troca de modelo e effort só na sessão, decisão do João) | 949040c |
| WP-K1 | todo | |
| WP-K2 | cancelado (sem mock, decisão do João) | |
| WP-K3 | feito sem device (test.sh com 1 falha de tempo conhecida em TranscriptStoreFollowTests; conferência visual no WP-K4) | 73eb388, e43991d, df7aa3b, 214d648, merge 540bb71 |
| WP-K4 | todo | |
| WP-T1 | todo | |
| WP-T2 | todo | |
| WP-T3 | todo | |
| WP-X4 | todo | |
| WP-T4 | todo | |
| WP-T5 | todo | |
| WP-X5 | todo | |
