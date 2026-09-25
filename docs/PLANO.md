# Mocha: plano de execução

Este plano é executado por **um agente orquestrador** que distribui pacotes de trabalho (WPs) entre subagentes. O **quê** e o **como** estão em `docs/SPEC.md` (fonte da verdade). As regras de trabalho estão em `AGENTS.md`. O prompt de partida está em `prompts/orquestrador.md`.

## Como o orquestrador trabalha

1. Lê `AGENTS.md`, a SPEC inteira e a fase atual deste plano.
2. Confere os bloqueios (`Bx`) da fase. O que depende do João é pedido **no começo da fase**, junto, não no meio.
3. Executa os WPs em **ondas**: dentro de uma onda, os WPs rodam em paralelo, um subagente por WP. A próxima onda começa quando a anterior foi revisada e commitada.
4. Para cada WP, o subagente recebe: o bloco do WP deste plano, as §§ da SPEC citadas, os arquivos que já existem e são relevantes, e as regras de subagente de `AGENTS.md`.
5. O orquestrador revisa o diff de cada WP contra os critérios de aceite, roda a validação (ou delega a um subagente de validação, §Builds), faz os commits e só então marca o WP como feito na tabela de status (fim deste arquivo).
6. Ao fim de cada marco, roda o WP de integração com o João (teste no iPhone real).

**Paralelismo seguro**
- Cada WP tem um **diretório dono**. Dois WPs da mesma onda nunca têm donos sobrepostos.
- Arquivos compartilhados são **do orquestrador**: `MochaKit/Package.swift`, `project.yml`, `MochaKit/Sources/MochaProtocol/**`, `MochaKit/Fixtures/protocol/**`, `docs/SPEC.md`, `docs/PLANO.md` e `docs/HANDOFF.md`. Um subagente que precisar mudar algum deles descreve a mudança (diff) no relatório, e o orquestrador aplica antes de integrar.
- No máximo **3 subagentes simultâneos**, spikes incluídos (M1 com 8 GB; builds do Xcode são pesados).
- Quando dois WPs da mesma onda precisam do mesmo diretório, o bloco de cada WP diz quais **arquivos** são dele. Um WP que precisar mexer num arquivo do outro propõe o diff no relatório.

**Builds**
- `swift build`/`swift test` de subagentes paralelos usam `--scratch-path MochaKit/.build/<WP>` para não disputar o lock do SwiftPM.
- `xcodebuild` roda **um de cada vez** na máquina. O orquestrador serializa, e cada WP de app usa `-derivedDataPath build/DerivedData-<WP>`.

## Visão das fases

| Fase | Resultado | Marco de integração |
|---|---|---|
| 0 | Repositório, contratos, servidor HTTP e todas as incertezas técnicas resolvidas por spikes | — |
| 1a-core | Parear, ver a gaveta, ler e mandar mensagem, interromper. Uso diário possível | WP-X1 |
| 1a-final | Push de turno concluído e de agente bloqueado; slash commands | WP-X2 |
| 1b | Inbox e ações na notificação, Live Activity, voz, imagem, nova tab | WP-X3 |
| 2 | Terminal SSH | WP-X4 |
| 3 | Mosh | WP-X5 |

## Bloqueios externos (ações do João)

| Código | O que o João faz | Necessário em |
|---|---|---|
| B1 | Confirmar a conta Apple Developer paga ativa e informar o **Team ID** (developer.apple.com › Membership) | S4, WP-I1 (assinatura no device) |
| B2 | Criar uma chave **APNs** (developer.apple.com › Certificates, IDs & Profiles › Keys › "+" › Apple Push Notifications service), baixar a `.p8` e informar o **Key ID**. A importação é feita com `mochad apns import` | S4 |
| B3 | iPhone com **Modo de Desenvolvedor** ligado (Ajustes › Privacidade e Segurança) e pareado com o Xcode (Window › Devices and Simulators), no mesmo Wi-Fi ou por cabo | S4, WP-X1 |
| B4 | Os certificados HTTPS do tailnet já estão ativos. Resta **autorizar** o comando `tailscale serve` quando o S5 pedir (ele altera a config do Tailscale do Mac) | S5 |
| B5 | Ligar o **Login Remoto** (Ajustes do Sistema › Geral › Compartilhamento › Login Remoto) e adicionar a chave pública do app em `~/.ssh/authorized_keys` | Fase 2 |
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
  4. `project.yml` com os targets `Mocha` (iOS 26, bundle `com.joaoalves.mocha`, dependências de §2.2) e `MochaWidgets` (extensão de widget com Live Activity, bundle `com.joaoalves.mocha.widgets`). `swift-markdown` com a versão estável mais recente, fixada com `exactVersion` e registrada na §11. Assinatura automática com `DEVELOPMENT_TEAM` vindo de `Config/Signing.xcconfig`.
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

- **Dono**: `docs/spikes/S5.md`, `MochaKit/Sources/MochaDaemonCore/Gateway/` (protótipo), `MochaKit/Sources/mochad/` (subcomando temporário `spike-gateway`, removido no WP-M4), `App/Sources/Debug/GatewayProbe*`.
- **Depende de**: WP0.1, WP0.3, B4 (autorização). A parte no iPhone também precisa de B1 e B3; sem eles, o S5 testa no simulador e o teste no iPhone fica para o WP-X1.
- **SPEC a atualizar**: §4.5.
- **Faz**:
  1. Servir `/v1/health` e um WS de eco (com o `HttpServer` do WP0.3) atrás de `tailscale serve --bg --https=443`, testando os alvos `unix:<socket>` e `http://127.0.0.1:47421`. Confirmar que os headers (`Authorization`) chegam, se a query string é descartada, e se o Tailscale standalone consegue abrir o socket em `~/Library/Application Support/Mocha/`.
  2. Cliente de teste iOS (simulador e iPhone) com `URLSessionWebSocketTask`: conexão, envio, queda de Wi-Fi/4G e retorno, e ida e volta de background.
  3. Registrar o comando final do `serve-setup` e como desfazê-lo (`tailscale serve reset` só se não houver outras configs; hoje não há nenhuma).
- **Aceite**:
  - [ ] `S5.md` com o alvo escolhido, os comandos, as latências medidas e o comportamento de reconexão.
  - [ ] Seção "Impacto" com o texto novo da §4.5 da SPEC, pronto para o orquestrador aplicar.

---

## Fase 1a-core: uso diário mínimo

**Ondas**
- **Onda 1.A**, em paralelo: WP-M1 · WP-M2 · WP-I1.
- **Onda 1.B**, em paralelo: WP-M3 · WP-I4 · WP-I3.
- **Onda 1.C**, em paralelo: WP-M4 · WP-I2 · WP-I5.
- **Onda 1.D**: WP-X1 (integração).

### WP-M1: `HerdrClient` e `HerdrBridge`

- **Dono**: `MochaKit/Sources/MochaHerdr/`, `MochaKit/Sources/MochaDaemonCore/Herdr/` e os testes correspondentes.
- **Depende de**: WP0.2, S2.
- **SPEC**: §3.1, §4.1.
- **Faz**: cliente com duas conexões (requisições e eventos), reconexão, snapshot, inscrições por pane, árvore derivada (§3.1.4, com `HEAD` do git lido direto e `isDirty` com cache), comandos `prompt`/`interrupt`, e publicação de mudanças por `AsyncStream`.
- **Aceite**:
  - [ ] Testes com um servidor de socket falso que reproduz as fixtures do S2: árvore correta, aninhamento de worktree ligado, status por pane, reconexão depois de o socket cair.
  - [ ] Teste `.integration` (só com `MOCHA_INTEGRATION=1`) lendo o Herdr real sem enviar input.

### WP-M2: parser e `TranscriptStore`

- **Dono**: `MochaKit/Sources/MochaTranscript/`, `MochaKit/Sources/MochaDaemonCore/Transcript/` e os testes.
- **Depende de**: WP0.2, S1.
- **SPEC**: §3.2, §5.4.
- **Faz**: parser de linha → itens (§3.2.2), com resolução de `tool_result` em `toolCall`, índice de offsets, página pelo fim, cursor, acompanhamento com `DispatchSource` e buffer de linha incompleta, troca de sessão.
- **Aceite**:
  - [ ] Cada fixture do S1 gera a lista de `ChatItem` esperada (snapshots JSON em `Fixtures/transcripts/expected/`).
  - [ ] A fixture de 50 MB responde a primeira página em < 300 ms (teste `.integration` medido).
  - [ ] Append simulado (escrever no arquivo durante o teste) gera `chatAppend`/`chatUpdate` em < 300 ms.
  - [ ] Linha corrompida é descartada sem derrubar a sessão.

### WP-M3: gateway, `SessionHub`, pareamento e aparelhos

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Gateway/`, `Pairing/` e `Devices/`, e os testes.
- **Depende de**: WP0.2, WP0.3, S5.
- **SPEC**: §4.5, §4.6, §5.
- **Faz**: rotas `/v1` e `/v1/health`, handshake `hello` com código ou token, `unpair`, `DeviceStore`, `SessionHub` (clientes, chats abertos, primeiro plano) e o roteamento das mensagens de §5.3 da 1a-core para interfaces `HerdrBridging`/`TranscriptProviding`, que o WP-M4 liga às implementações reais.
- **Aceite**:
  - [ ] Teste de ponta a ponta com um cliente WS de teste: pareamento → token → reconexão com token → `tree` → `openChat` → `chatAppend` (com os fakes de Herdr e de transcript).
  - [ ] Token errado → `unauthorized`; três falhas → conexão fechada.
  - [ ] `devices.json` com permissão 0600 e só com o hash do token.

### WP-M4: `mochad`: composição, CLI, LaunchAgent e `doctor`

- **Dono**: `MochaKit/Sources/mochad/`, `MochaKit/Sources/MochaDaemonCore/App/`.
- **Depende de**: WP-M1, WP-M2, WP-M3.
- **SPEC**: §4.2, §4.3, §4.7.
- **Faz**: liga os componentes reais e implementa os comandos da 1a-core: `run`, `install`, `uninstall`, `pair` (QR no terminal), `devices`, `serve-setup`, `status` e `doctor`.
- **Aceite**:
  - [ ] `mochad install` sobe o LaunchAgent, e `launchctl print gui/$UID/com.joaoalves.mochad` mostra o serviço rodando.
  - [ ] `mochad doctor` lista os itens de §4.2 com o estado real.
  - [ ] Parado por 10 min: RSS < 30 MB (medido com `footprint` ou `ps`).
  - [ ] `mochad pair` exibe um QR legível pela câmera do iPhone.

### WP-I1: design system, shell do app e modo demo

- **Dono**: `App/Sources/DesignSystem/`, `App/Sources/AppShell/`, `App/Resources/`.
- **Depende de**: WP0.1, WP0.2.
- **SPEC**: §6.1, §6.2.
- **Faz**:
  1. Tokens de cor e tipografia (identificando a fonte mono do print), componentes base (header de vidro, botão redondo de vidro, composer vazio, card de ferramenta, bolha), navegação raiz (gaveta sobre o chat) e deep links.
  2. **Modo demo**: com o argumento de launch `-demo`, o app usa o `DemoServerConnection` do `MochaDemo` (WP0.2) no lugar da conexão real. O esquema do Xcode já passa `-demo` nos WPs de UI.
- **Aceite**:
  - [ ] Capturas do simulador (`xcrun simctl io booted screenshot`) lado a lado com `docs/referencias/moshi/chat-conversa.png` e `gaveta-workspaces.png`, com as diferenças listadas no relatório e corrigidas até ficarem só as ditadas pelo conteúdo.
  - [ ] Cores exatamente as da tabela de §6.2.
- **Nota**: por ser UI, o orquestrador oferece ao João testar no iPhone antes de rodar verificações pesadas.

### WP-I4: renderizador de markdown

- **Dono**: `App/Sources/Markdown/`.
- **Depende de**: WP-I1 (tokens).
- **SPEC**: §11 (lista de elementos) e §6.2.
- **Faz**: AST do `swift-markdown` → views SwiftUI, com seleção de texto nos parágrafos, código inline em `link`, blocos de código com rolagem horizontal, listas aninhadas e tabelas.
- **Aceite**:
  - [ ] Tela de preview (só em debug) com um documento de teste cobrindo todos os elementos, capturada no simulador.
  - [ ] Parse + layout de uma mensagem de 20 KB abaixo de 16 ms no simulador (medido com `signpost`).

### WP-I3: gaveta

- **Dono**: `App/Sources/Drawer/`.
- **Depende de**: WP-I1.
- **SPEC**: §6.3 (Gaveta), §3.1.4.
- **Faz**: busca, Recentes/Árvore, aninhamento, estados, seleção e gesto de abrir pela borda. Tudo contra o modo demo.
- **Aceite**:
  - [ ] Captura no simulador comparada a `gaveta-workspaces.png`.
  - [ ] A busca filtra workspace, tab e título.
  - [ ] Um `treeChanged` com um worktree novo aparece sem recarregar a tela.

### WP-I2: conexão, pareamento e ajustes

- **Dono**: `MochaKit/Sources/MochaClient/`, `MochaKit/Tests/MochaClientTests/`, `App/Sources/Connection/`, `App/Sources/Pairing/`, `App/Sources/Settings/`.
- **Depende de**: WP0.2, WP0.3, S5, WP-I1.
- **SPEC**: §2.3 (Reconexão), §4.5, §6.1, §6.3 (Pareamento, Ajustes).
- **Faz**: `ConnectionManager` (actor, em `MochaClient`) com backoff e `TokenStore` injetado; `KeychainTokenStore` no app; `scenePhase`; leitura de QR com `DataScannerViewController`; link colado; estados de erro; tela de Ajustes com estado da conexão, versões e desparear.
- **Aceite**:
  - [ ] `MochaClientTests` contra um servidor WS de teste montado com o `HttpServer` (WP0.3): pareamento por código → token salvo no `TokenStore` → reconexão com token, queda do servidor e sequência de backoff.
  - [ ] No simulador, com `-demo`, as telas de pareamento e Ajustes aparecem e navegam. O pareamento contra o `mochad` real acontece no WP-X1.

### WP-I5: chat e composer

- **Dono**: `App/Sources/Chat/`, `App/Sources/Composer/`.
- **Depende de**: WP-I1, WP-I4 (pode começar com um `Text` simples no lugar do markdown e trocar no fim), WP0.2.
- **SPEC**: §6.3 (Chat, Composer), §5.3, §5.4.
- **Faz**: lista com todos os tipos de item, agrupamento de ferramentas consecutivas, expansão, paginação para cima mantendo a posição, grudar no fim, botão ↓, indicador de "trabalhando", bolha "enviando", enviar e parar.
- **Aceite**:
  - [ ] Capturas no modo demo comparadas a `chat-conversa.png` e `chat-recap.png`.
  - [ ] Rolagem a 60 fps num chat de 2.000 itens (Instruments ou `signpost`, medido no simulador; no device, no WP-X1).
  - [ ] Paginação sem salto visível.

### WP-X1: integração da 1a-core

- **Dono**: orquestrador. Correções pequenas em qualquer diretório, commitadas separadamente.
- **Depende de**: todos os WPs da 1a-core e os bloqueios B1, B3, B4 e B8.
- **Faz**: instala o `mochad` (LaunchAgent), configura o `serve` e instala o app no iPhone pelo Xcode. Depois o João percorre o checklist.
- **Checklist do João** (no iPhone, pelo tailnet):
  - [ ] Pareia pelo QR do `mochad pair`.
  - [ ] A gaveta mostra os workspaces, tabs e agentes reais, com branch e `*`.
  - [ ] Pedir a um agente para criar um worktree faz o workspace novo aparecer aninhado na gaveta sem recarregar.
  - [ ] Abrir um chat longo mostra a última página em menos de 1 s, e a rolagem pra cima carrega o histórico.
  - [ ] Enviar um prompt pelo celular faz o Claude responder, e a resposta aparece no chat.
  - [ ] Parar interrompe o agente.
  - [ ] Fechar o app, mandar um prompt pelo Mac e reabrir: o chat está atualizado.
  - [ ] Trocar Wi-Fi ↔ 4G com o app aberto: reconecta sozinho.
  - [ ] O visual bate com os prints do Moshi (ok visual do João).

---

## Fase 1a-final: push e slash

**Ondas**
- **Onda 2.A**, em paralelo: WP-M5 · WP-I6 · WP-I7.
- **Onda 2.B**: WP-M6.
- **Onda 2.C**: WP-X2.

### WP-M5: `HookServer` e `install-hooks`

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Hooks/`, o comando `install-hooks`/`uninstall-hooks` em `mochad`.
- **Depende de**: WP0.3, WP-M4, S3.
- **SPEC**: §3.3.
- **Faz**: rotas `/hooks/<evento>` no listener local, validação do segredo, tradução dos payloads (fixtures do S3) em eventos internos, merge idempotente no `settings.json` com backup, e detecção do moshi-hook.
- **Aceite**:
  - [ ] Testes com as fixtures do S3.
  - [ ] Teste do merge sobre uma cópia do `settings.json` real do João (em diretório temporário): preserva hooks de terceiros, é idempotente e o uninstall remove só o que é do Mocha.
  - [ ] `PermissionRequest` responde `{}` na hora (sem decidir) nesta fase.

### WP-M6: `PushService` (alertas)

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Push/`, o comando `apns` em `mochad`, e o tratamento de `setPreferences` em `Gateway/`/`Devices/` (único WP da onda).
- **Depende de**: S4, WP-M5.
- **SPEC**: §7.1, §4.6.
- **Faz**: JWT com cache e renovação, cliente HTTP/2, escolha de ambiente por aparelho, os dois tipos de alerta, supressão por primeiro plano e por preferência, deduplicação e limpeza de token inválido.
- **Aceite**:
  - [ ] Testes do JWT (formato e assinatura verificável com a chave pública), da montagem de payloads e das regras de supressão e deduplicação, com cliente APNs falso.
  - [ ] `mochad apns test` entrega no iPhone.

### WP-I6: notificações no app

- **Dono**: `App/Sources/Notifications/`, o campo `apns` do `hello` em `App/Sources/Connection/` e `MochaKit/Sources/MochaClient/` (único WP da onda que mexe ali), e o item de notificações em `App/Sources/Settings/`.
- **Depende de**: S4, WP-I2.
- **SPEC**: §7.1, §6.1 (deep links), §6.3 (Ajustes).
- **Faz**: pedido de permissão (`.alert`, `.sound`, `.badge`; o time-sensitive vem do entitlement do WP0.1 e do `interruption-level` do payload), registro do token com `env` no `hello`, `setForeground`, categorias `TURN_DONE`/`NEEDS_INPUT`, o toque abrindo o chat certo (com o app encerrado, em background ou aberto em outro chat), e o controle "Avisar quando o Claude terminar" em Ajustes (`setPreferences`).
- **Aceite**:
  - [ ] Os três estados de abertura testados no device (checklist no relatório).
  - [ ] Nada de alerta do agente que está aberto na tela.

### WP-I7: menu de slash

- **Dono**: `App/Sources/Composer/SlashMenu*`.
- **Depende de**: WP-I5.
- **SPEC**: §6.3 (Menu `↻`), §5.3 (`slash`).
- **Aceite**:
  - [ ] Os comandos da lista enviam `slash`; `/clear` pede confirmação.
  - [ ] Depois de `/clear`, o chat troca para a sessão nova (depende do WP-M2 e do S1).

### WP-X2: integração da 1a-final

- **Checklist do João**:
  - [ ] Com o app fechado, um turno longo termina e chega o push "Claude terminou · <workspace>" com a prévia.
  - [ ] Tocar no push abre o chat certo.
  - [ ] Um pedido de permissão no Mac gera o push "precisa de você" em menos de 5 s.
  - [ ] Com o chat do agente aberto, nenhum push desse agente.
  - [ ] `/compact` e `/clear` pelo menu funcionam.
  - [ ] Com o VPN On Demand ligado (B6), o app conecta sem abrir o Tailscale.
- **Depois do WP-X2**: o João decide quando executar o B7 (remover o moshi-hook). A fase 1b não começa antes disso.

---

## Fase 1b: completar o MVP

**Ondas**
- **Onda 3.A**, em paralelo: WP-M7 · S6.
- **Onda 3.B**, em paralelo: WP-M8 · WP-M9.
- **Onda 3.C**, em paralelo: WP-I8 · WP-I9 · WP-I10.
- **Onda 3.D**: WP-I11.
- **Onda 3.E**: WP-X3.

### WP-M7: pedidos pendentes

- **Dono**: `MochaKit/Sources/MochaDaemonCore/Pending/`, extensões em `Hooks/`, rota `POST /v1/respond`.
- **Depende de**: S3, WP-M5, WP-M6, B7.
- **SPEC**: §8, §5.3 (`respond`, `pending`), §5.5, §7.1 (`PERMISSION`/`QUESTION`).
- **Aceite**:
  - [ ] Testes dos três desfechos de §8.1: resposta do celular, resposta pelo terminal e timeout.
  - [ ] Testes do mecanismo de perguntas escolhido no S3.
  - [ ] Push com as categorias certas.

### WP-M8: Live Activity no daemon, e nova tab

- **Dono**: `MochaKit/Sources/MochaDaemonCore/LiveActivity/`, o envio `liveactivity` em `Push/`, a extensão do `HerdrBridge` para `newAgentTab`, e o tratamento das mensagens WS `registerLiveActivity`/`newAgentTab` no `SessionHub`. Não mexe em rotas HTTP (são do WP-M9 nesta onda).
- **Depende de**: S4, WP-M6.
- **SPEC**: §7.3, §5.3 (`registerLiveActivity`, `newAgentTab`), §3.1.2.
- **Aceite**:
  - [ ] Testes da máquina de estados: início, atualização com o limite de 10 s, prioridade 10 só na transição para bloqueado, fim depois de 60 s ocioso, renovação às 7 h 50 min.
  - [ ] `newAgentTab` cria a tab no workspace e responde com o `agentId`.

### S6: voz em pt-BR

- **Dono**: `docs/spikes/S6.md`.
- **Faz**: confirma `SpeechTranscriber.supportedLocales` com pt-BR no iPhone, o download do modelo, a latência de resultados parciais e a qualidade com termos técnicos.
- **Aceite**:
  - [ ] `S6.md` com o resultado e as configurações recomendadas.

### WP-I8: inbox e ações de notificação

- **Dono**: `App/Sources/Inbox/`, extensões em `App/Sources/Notifications/`.
- **Depende de**: WP-M7.
- **SPEC**: §6.3 (Inbox), §7.2.
- **Aceite**:
  - [ ] Aprovar pelo inbox, pela notificação com o app encerrado (Face ID pedido), e negar.
  - [ ] Responder uma pergunta de opção única pela notificação e uma com várias perguntas pelo app.

### WP-I9: Live Activity no app

- **Dono**: `Widgets/`, `App/Sources/LiveActivity/`.
- **Depende de**: WP-M8.
- **SPEC**: §7.3.
- **Aceite**:
  - [ ] Tela bloqueada e Dynamic Island (compacta, mínima e expandida) capturadas no device.
  - [ ] Início por push-to-start com o app encerrado.

### WP-I10: voz

- **Dono**: `App/Sources/Voice/`, e o botão de microfone no composer.
- **Depende de**: S6, WP-I5.
- **SPEC**: §6.4.
- **Aceite**:
  - [ ] Ditado em pt-BR no device, com parcial e final no campo, sem envio automático.

### WP-M9: upload no daemon

- **Dono**: a rota HTTP `/v1/upload` em `Gateway/` e a limpeza de `uploads/`. Não mexe no tratamento de mensagens WS (é do WP-M8 nesta onda).
- **Depende de**: WP-M3.
- **SPEC**: §5.5, §10.
- **Aceite**:
  - [ ] Testes de tipo aceito, limite de 20 MB, nome gerado pelo daemon e limpeza depois de 7 dias.

### WP-I11: imagem e nova tab no app

- **Dono**: `App/Sources/Composer/Attachments*`, e o `+` da gaveta.
- **Depende de**: WP-M9, WP-M8.
- **SPEC**: §6.5, §6.3 (Gaveta, 1b).
- **Aceite**:
  - [ ] Foto do rolo e print colado chegam ao Claude, que descreve a imagem.
  - [ ] "Nova tab com Claude" abre o chat do agente novo.

### WP-X3: integração da 1b

- **Checklist do João**:
  - [ ] Aprovação e pergunta pelo inbox e pela notificação.
  - [ ] Live Activity com 2 agentes trabalhando e 1 bloqueado.
  - [ ] Ditado em pt-BR.
  - [ ] Imagem.
  - [ ] Nova tab.
  - [ ] Um dia inteiro de uso sem abrir o Moshi.

---

## Fase 2: terminal SSH

Ondas: WP-T1 → WP-T2 ∥ WP-T3 → WP-X4.

- **WP-T1**, spike: chave da Secure Enclave no Citadel (autenticação `ecdsa-sha2-nistp256` com o Mac) e `herdr agent attach <pane>` por SSH num PTY. Dono: `docs/spikes/T1.md`. Bloqueio B5.
- **WP-T2**: tela de terminal (`SwiftTerm`), barra de teclas de §9.1 e botão `>_` no composer. Dono: `App/Sources/Terminal/View/`, o botão em `App/Sources/Composer/`. Aceite: captura comparada a `terminal.png`.
- **WP-T3**: conexão SSH, reanexar ao reconectar, gestão da chave e exibição da pública em Ajustes. Dono: `App/Sources/Terminal/Session/`, `App/Sources/Settings/SSH*`.
- **WP-X4**, checklist: abrir o terminal do agente atual, digitar, usar o prefixo do Herdr, trocar de rede e ver reanexar.

## Fase 3: Mosh

Ondas: WP-T4 → WP-T5 → WP-X5.

- **WP-T4**: build do mosh e do protobuf para iOS como xcframework (a partir de `blinksh/build-mosh`), com script reproduzível em `scripts/`. Dono: `Vendor/mosh/`, `scripts/build-mosh.sh`.
- **WP-T5**: transporte Mosh na tela de terminal (§9.2). Dono: `App/Sources/Terminal/Mosh*`.
- **WP-X5**, checklist: a sessão sobrevive a 5 min de app em background e à troca de rede, sem reanexar.

---

## Status

Atualizado só pelo orquestrador, depois do commit de cada WP.

| WP | Status | Commit |
|---|---|---|
| WP0.1 | feito | f5adafc |
| WP0.2 | todo | |
| WP0.3 | todo | |
| S1 | todo | |
| S2 | todo | |
| S3 | todo | |
| S4 | todo | |
| S5 | todo | |
| WP-M1 | todo | |
| WP-M2 | todo | |
| WP-M3 | todo | |
| WP-M4 | todo | |
| WP-I1 | todo | |
| WP-I2 | todo | |
| WP-I3 | todo | |
| WP-I4 | todo | |
| WP-I5 | todo | |
| WP-X1 | todo | |
| WP-M5 | todo | |
| WP-M6 | todo | |
| WP-I6 | todo | |
| WP-I7 | todo | |
| WP-X2 | todo | |
| WP-M7 | todo | |
| WP-M8 | todo | |
| S6 | todo | |
| WP-I8 | todo | |
| WP-I9 | todo | |
| WP-I10 | todo | |
| WP-M9 | todo | |
| WP-I11 | todo | |
| WP-X3 | todo | |
| WP-T1 | todo | |
| WP-T2 | todo | |
| WP-T3 | todo | |
| WP-X4 | todo | |
| WP-T4 | todo | |
| WP-T5 | todo | |
| WP-X5 | todo | |
