# Mocha: especificação

Fonte da verdade do projeto. `docs/PLANO.md` diz **em que ordem** construir; este documento diz **o quê** e **como**. `AGENTS.md` rege o processo (papéis, git, testes). Em conflito técnico entre PLANO, AGENTS, prompt e SPEC, vale a SPEC. Quem mudar um contrato daqui atualiza a SPEC no mesmo commit.

Seções são citadas como `§N.M`.

---

## §1 Produto

### §1.1 O que é

Mocha é um app iOS pessoal que mostra, como **chat nativo**, as sessões do Claude Code que rodam no Herdr do MacBook. Pelo celular dá pra acompanhar, mandar prompts, interromper, aprovar e responder o agente, e receber push quando ele termina ou precisa de atenção.

São duas peças:

- **Mocha** (iPhone): SwiftUI, iOS 26+.
- **mochad** (Mac): daemon Swift que roda como LaunchAgent. Fala com o Herdr, lê os transcripts do Claude Code, recebe os hooks do Claude e manda push direto para o APNs.

A tela inicial é a **Home** (central de agentes): os agentes Claude do Herdr agrupados por estado, com o contexto livre de cada um e o uso do plano. Cada agente abre um **chat nativo** por cima da Home. O terminal é secundário e entra só na fase 2.

O visual de todas as telas está no mock aprovado, `docs/design/mock.html`, com uma captura 3x de cada tela em `docs/design/mock/` (§6.2).

### §1.2 Ambiente fixo

| Item | Valor |
|---|---|
| Host | Um único MacBook (Apple M1, 8 GB, macOS 27). Não existe suporte a vários hosts |
| Multiplexador | Herdr 0.9.1 (`/opt/homebrew/bin/herdr`), sessão padrão |
| Agente | Claude Code 2.1.x (CLI), rodando dentro de panes do Herdr |
| Rede | Tailscale 1.98 no Mac (app standalone) e no iPhone. O iPhone só alcança o Mac pelo tailnet. Nome MagicDNS do Mac: `mac-mini.tail1234.ts.net` (certificados HTTPS do tailnet já ativos) |
| Toolchain | Xcode 27, Swift 6.4, XcodeGen (`/opt/homebrew/bin/xcodegen`) |
| Distribuição | Conta Apple Developer paga do time da empresa (B1), uso pessoal, **sem App Store**. Instalação pelo Xcode (perfil de desenvolvimento, validade de ~1 ano, APNs **sandbox**) ou TestFlight interno (build de 90 dias, APNs **produção**) |
| Identificadores | App `com.example.mocha`, extensão `com.example.mocha.widgets`, LaunchAgent `com.joaoalves.mochad`. O Team ID é definido no bloqueio B1 (`docs/PLANO.md`). Tudo o que é registrado na conta Apple (App IDs, App Groups e afins) usa nomes discretos com o prefixo `com.example.mocha` e nunca leva "mocha" nem "joaoalves"; os identificadores locais do Mac (LaunchAgent, Keychain, log, filas) continuam `com.joaoalves.*` |

### §1.3 Escopo por fase

| Funcionalidade | Fase |
|---|---|
| Pareamento iPhone ↔ Mac por QR | 1a-core |
| Home (central de agentes): seções por estado, prévia da última mensagem, última ferramenta, anel de contexto livre | 1a-core |
| Detalhe do agente (folha) | 1a-core |
| Uso do plano (janelas de 5h e 7d) na Home e no detalhe | 1a-core |
| Sessões arquivadas persistentes, arquivar pelo card, chat só de leitura de sessão encerrada | 1a-core |
| Gaveta de workspaces, tabs e agentes do Herdr, ao vivo (inclui os worktrees do Herdr criados pelos agentes) | 1a-core |
| Chat do agente: histórico paginado, atualização ao vivo, markdown, cards de ferramenta | 1a-core |
| Enviar prompt, interromper (Esc) | 1a-core |
| Daemon como LaunchAgent, `doctor` | 1a-core |
| Push de turno concluído e de agente bloqueado, com deep link | 1a-final |
| Slash commands rápidos | 1a-final |
| Inbox de aprovações e perguntas (sino na Home e card no chat); ações na notificação | 1b |
| Live Activity agregada / Dynamic Island | 1b |
| Ditado por voz on-device | 1b |
| Anexar imagem ao prompt | 1a-core |
| Abrir nova tab com Claude num workspace existente | 1a-final |
| Card vivo de cada subagente (`Agent`) no chat, que abre o transcript do subagente só de leitura | subagentes |
| Selo de subagentes rodando no card da Home e lista de subagentes no Detalhe do agente | subagentes |
| Card de workflow com as fases e os agentes de cada fase | subagentes |
| Terminal SSH (`herdr agent attach`) | 2 |
| Transporte Mosh no terminal | 3 |

### §1.4 Fora de escopo

Nada disto entra em nenhuma fase acima: outros agentes além de Claude e Codex (Antigravity e demais), vários hosts, diff viewer, preview de dev server, temas, fontes e atalhos configuráveis, Apple Watch, iPad, criação de worktree pelo app, relay em nuvem, publicação na App Store, Android. Codex entra na fase Codex (§13).

### §1.5 Glossário

- **Workspace**: workspace do Herdr (`workspace_id`, ex.: `w17`, `w1A`; ids opacos, nunca reaproveitados). Pode ser um worktree git ligado a outro workspace do mesmo repositório.
- **Tab**: tab do Herdr (`tab_id`, ex.: `w17:t1`).
- **Pane**: pane do Herdr (`pane_id`, ex.: `w17:p1`). Um pane movido para outro workspace ganha id novo (evento `pane_moved`), e o agente muda de `AgentID`.
- **Agente**: um pane onde o Herdr detectou o Claude Code. No protocolo, a identidade do agente é o `pane_id` (`AgentID`).
- **Sessão**: sessão do Claude Code (`session_id`, UUID). Um agente troca de sessão com `/clear`, que cria um arquivo de transcript novo; `/compact` mantém a sessão e o arquivo.
- **Turno**: do prompt do usuário até o Claude parar (hook `Stop`).
- **Pedido pendente**: aprovação de ferramenta ou pergunta (AskUserQuestion) esperando resposta (1b).
- **Subagente**: agente que o Claude Code abre com a ferramenta `Agent` (antes `Task`), inclusive os aninhados e os agentes de um workflow. Roda em background, com transcript próprio, e é identificado pelo `agentId` (§3.5).
- **Workflow**: execução da ferramenta `Workflow` do Claude Code, um script que abre agentes em fases, identificada pelo `runId` (§3.5.3).

---

## §2 Arquitetura

### §2.1 Visão geral

```
┌──────────── iPhone ────────────┐
│ Mocha.app (SwiftUI)            │
│ MochaWidgets (Live Activity)   │
└───────────────┬────────────────┘
                │ wss://mac-mini.tail1234.ts.net/v1
                │ (tailnet, TLS com certificado do Tailscale)
┌───────────────▼──────────────── MacBook ───────────────────────────┐
│ tailscale serve  ──►  gateway (127.0.0.1:47421)                    │
│                        │                                           │
│                 ┌──────▼──────────── mochad ─────────────────────┐ │
│                 │ Gateway · Pairing · SessionHub                 │ │
│                 │ HerdrBridge ── socket Unix ──► Herdr server    │ │
│                 │ TranscriptStore ── lê ~/.claude/projects/**    │ │
│                 │ HookServer ◄── HTTP 127.0.0.1 ◄── Claude Code  │ │
│                 │ PushService ── HTTP/2 ──► APNs (Apple)         │ │
│                 └────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

Princípios:

1. O Mac é a fonte da verdade. O app não guarda histórico de chat entre execuções: ele pede de novo ao daemon.
2. Nenhuma porta do daemon fica aberta fora de `127.0.0.1`. A exposição ao iPhone é só pelo `tailscale serve`.
3. Não existe servidor em nuvem. O push sai do Mac direto para o APNs.
4. Com o app em background não há conexão viva: o que acontece nesse período chega por push, e o app sincroniza ao voltar.

### §2.2 Repositório

```
~/Developer/mocha/
  AGENTS.md  CLAUDE.md  README.md
  project.yml                     XcodeGen: targets Mocha (app) e MochaWidgets (extensão)
  Config/
    Signing.example.xcconfig      DEVELOPMENT_TEAM vazio (versionado)
    Signing.xcconfig              cópia local com o Team ID (fora do git; criado pelo bootstrap.sh)
  App/
    Sources/                      código do app (§6)
    Resources/                    Assets.xcassets, fontes, Localizable (pt-BR)
    Info.plist  Mocha.entitlements
  Widgets/
    Sources/  Info.plist          Live Activity (§7.3)
  MochaKit/                       Swift Package local
    Package.swift
    Sources/
      MochaProtocol/              tipos compartilhados app ↔ daemon (§5), o protocolo ServerConnection e, só no iOS, MochaAgentsAttributes (§7.3). Sem dependências
      MochaClient/                cliente WS do app: ConnectionManager, reconexão, TokenStore (§6.1) e a lógica pura de apresentação (Presentation/)
      MochaDemo/                  ServerConnection em processo com dados de demonstração (Resources/*.json)
      MochaTranscript/            parser do JSONL do Claude Code → ChatItem (§3.2)
      MochaHerdr/                 cliente do socket do Herdr (§3.1)
      MochaDaemonCore/            serviços do daemon (§4)
      mochad/                     executável (CLI + run loop)
      MochaTestSupport/           fakes e helpers de teste do pacote (daemon e cliente), um subdiretório por área (Herdr/, Transcript/, Http/, …)
    Tests/
      MochaProtocolTests/  MochaDemoTests/  MochaClientTests/  MochaTranscriptTests/  MochaHerdrTests/  MochaDaemonCoreTests/
    Fixtures/
      transcripts/  herdr/  hooks/  protocol/  usage/
  scripts/
    bootstrap.sh                  xcodegen generate
    test.sh                       swift test --package-path MochaKit
    build-app.sh                  xcodebuild do app para o simulador
    build-device.sh               xcodebuild assinado do app para o iPhone (-allowProvisioningUpdates)
    build-daemon.sh               swift build -c release --product mochad
    lib/xcode-lock.sh             trava que build-app.sh e build-device.sh pegam antes do xcodebuild (um por vez na máquina)
    run-daemon.sh                 roda o mochad em primeiro plano com log no stdout
  docs/                           SPEC, PLANO, HANDOFF, spikes, referencias/moshi/ e design/ (mock.html e mock/NN-nome.png)
  prompts/
```

`Package.swift`: `platforms: [.iOS(.v26), .macOS(.v26)]`.

| Target | Plataformas | Depende de |
|---|---|---|
| `MochaProtocol` | iOS, macOS | — |
| `MochaClient` | iOS, macOS | `MochaProtocol` |
| `MochaDemo` | iOS, macOS | `MochaProtocol` (dados de demo em `Sources/MochaDemo/Resources/`, declarados como recurso do target) |
| `MochaTranscript` | macOS | `MochaProtocol` |
| `MochaHerdr` | macOS | — |
| `MochaDaemonCore` | macOS | `MochaProtocol`, `MochaTranscript`, `MochaHerdr` |
| `mochad` (executável) | macOS | `MochaDaemonCore` |
| `MochaTestSupport` | macOS | `MochaProtocol`, `MochaHerdr`, `MochaTranscript`, `MochaDaemonCore` |
| `MochaClientTests` | macOS | `MochaClient`, `MochaDaemonCore` (usa o `HttpServer` real como servidor WS de teste), `MochaTestSupport` |
| `MochaDemoTests` | macOS | `MochaDemo` |
| `MochaHerdrTests` | macOS | `MochaHerdr`, `MochaTestSupport` |
| `MochaTranscriptTests` | macOS | `MochaTranscript`, `MochaTestSupport` |

Os test targets acham `MochaKit/Fixtures/` por um helper `Fixtures` baseado em `#filePath`, porque o SwiftPM não aceita recurso fora do diretório do target.

O app (`project.yml`) depende de `MochaProtocol`, `MochaClient`, `MochaDemo` e `swift-markdown`. A extensão `MochaWidgets` depende só de `MochaProtocol`. O modo demo liga com o argumento de launch `-demo`: o app usa `DemoServerConnection` (de `MochaDemo`) no lugar da conexão real. Junto com `-demo`, o argumento `-demo-script` liga um roteiro de eventos (árvore mudando, troca de sessão, append contínuo, queda e volta da conexão), usado nos WPs de UI. O projeto tem um esquema "Mocha Demo" que passa `-demo`.

**Subagentes no demo** (fase subagentes): o chat de `receitas-api` termina como na tela 16 (o `Explore` "Mapear uso de OFFSET" concluído e o `general-purpose` "Teste de carga /receitas" rodando, com a ferramenta atual), e acima da parte visível traz os cards dos outros subagentes da tela 18 ("Gerar fixtures de carga" concluído e o `Plan` "Revisar o índice de receitas" com falha e motivo). O aninhado "Achar o script de carga" é filho do que roda e aparece como card concluído no transcript dele, logo depois de "Pensou" (tela 16b). O `openChat` de cada um responde com o transcript dele: o que roda como na tela 16b e o concluído como na 16c. O `receitas-api` vai com `runningSubagents: 1`, e o `demo-app` fica em CONCLUÍDOS com `runningSubagents: 2` e o chat da tela 19 (workflow `auditoria-a11y` rodando, com as fases e os agentes da captura), como na tela 17. O `listSubagents` do `receitas-api` devolve a lista da tela 18; o chat de `login-social` ganha, no histórico, um card de subagente parado e um card de workflow concluído (recolhido, como no estado concluído abaixo da tela 19). Os horários são relativos ao lançamento, como no resto do demo. No roteiro `-demo-script`, o subagente que roda termina: o card vira `completed` por `chatUpdate`, o transcript aberto recebe o `chatMeta` com o fim, o `treeChanged` zera o selo do `receitas-api`, e o `listSubagents` passa a devolvê-lo como `completed`.

### §2.3 Fluxos principais

**Abrir o app (1a-core)**
1. O app lê a URL e o token do Keychain, abre o WebSocket e envia `hello` (§5.3).
2. O daemon valida o token e responde `helloOk` seguido de `tree`, `archived`, `usage` (quando o cache de uso existe, §3.4) e, na 1b, `pending`.
3. O app mostra a Home. Um deep link `mocha://agent/<paneId>` abre o chat desse agente por cima dela.

**Abrir um chat (1a-core)**
1. O app envia `openChat{agentId, limit: 60}` para um agente vivo, ou `openChat{sessionId, limit: 60}` para uma sessão arquivada (chat só de leitura, §5.3.1).
2. O daemon resolve o arquivo da sessão (§3.2.1), monta a última página e responde `chatPage`.
3. Enquanto o chat está aberto, novas entradas no arquivo viram `chatAppend` ou `chatUpdate` para esse cliente.
4. Rolar até o topo pede `openChat{<mesmo alvo>, before: cursor}`.

**Home ao vivo (1a-core)**
1. O daemon acompanha o transcript de todo agente `working` ou `blocked`, mesmo sem chat aberto (§3.2.3), e recompõe o `AgentSummary` (prévia, ferramenta, contexto e horários do turno, §4.1.2).
2. Cada mudança sai num `treeChanged` com debounce de 150 ms. O app reclassifica as seções com o relógio local (§6.3, Home).
3. Quando uma sessão termina (`/clear`, pane fechado, Claude encerrado), o daemon a grava em `sessions.json` e manda `archived` (§4.9).

**Enviar prompt (1a-core)**
1. O app envia `sendPrompt{agentId, text}`.
2. O daemon chama `agent.prompt` no Herdr.
3. A resposta ao cliente é `ack` ou `error` (ex.: `agentBlocked`).
4. O prompt aparece no chat quando o Claude o grava no transcript, não antes. Enquanto isso, o app mostra a bolha em estado "enviando".

**Turno concluído com o app em background (1a-final)**
1. O hook `Stop` chega ao `HookServer` com `last_assistant_message` e o pane no header.
2. O `PushService` manda um alerta para os aparelhos pareados, exceto quando o app está em primeiro plano nesse agente (§7.1).
3. O toque na notificação abre `mocha://agent/<paneId>`.

**Pedido pendente (1b)**
1. `PermissionRequest` (aprovação de ferramenta ou pergunta do AskUserQuestion) chega ao `HookServer`. O daemon cria um `PendingRequest`, faz broadcast de `pending` e manda um push time-sensitive com ações.
2. A resposta chega pelo app (`respond`) ou pela ação da notificação (HTTP, §5.5), e o daemon responde o hook segurado (§8.2).
3. Se a resposta vier pelo terminal do Mac, o daemon percebe (conexão do hook fechada, status do Herdr saindo de `blocked` ou `tool_result` no transcript) e retira o pedido (§8.3).

**Reconexão**
- O app reconecta com backoff exponencial enquanto está em primeiro plano: 0,5 s, 1 s, 2 s, 4 s e depois 8 s. Cada espera é multiplicada por um jitter de 0,8–1,2 e limitada a 8 s, e a contagem zera a cada conexão aberta. Se o `NWPathMonitor` informa caminho `.satisfied` durante uma espera, a tentativa sai na hora. Ao reconectar, o app reenvia `hello`, recebe `tree` e reabre o chat visível com `openChat` (página nova; o app substitui a lista).
- **A troca de rede não derruba a conexão**: o WebSocket passa dentro do túnel do Tailscale, que troca Wi-Fi por 4G sem fechar o TCP. No S5 (iPhone 14), Wi-Fi → 4G e 4G → Wi-Fi seguraram o tráfego por ~6,9 s e ~8,5 s, e depois tudo chegou, sem reconexão. Por isso o app não fecha nem reabre o WebSocket quando a rede muda.
- **Heartbeat**: com o app em primeiro plano, o `ConnectionManager` manda um ping de WebSocket (`sendPing`) a cada 5 s, e um logo depois de cada mudança de caminho, sempre com um `receive()` pendente (sem ele o pong não é processado; WP0.3). Um ping sem pong por 15 s marca a conexão como morta: o app cancela a tarefa e segue o backoff. O servidor não manda ping (§4.4). Referência medida: eco de WebSocket com mediana de 12 ms no Wi-Fi e 36 ms no 4G; volta do background em 1 tentativa, com handshake de 87–203 ms.
- O daemon reconecta ao socket do Herdr a cada 2 s se o Herdr cair, e reconstrói o estado com `session.snapshot` e as inscrições, na ordem de §3.1.3.

---

## §3 Fontes de dados no Mac

### §3.1 Herdr

#### §3.1.1 Conexão

- **Socket**, em ordem de resolução: `HERDR_SOCKET_PATH` → `HERDR_SESSION=<nome>` (`~/.config/herdr/sessions/<nome>/herdr.sock`) → `~/.config/herdr/herdr.sock` (modo `0600`). O LaunchAgent não herda as variáveis dos panes, então na prática usa o caminho padrão. O `mochad` aceita `--herdr-socket <path>` para sobrescrever.
- **Protocolo**: JSON delimitado por `\n` sobre socket Unix. A requisição é `{"id":"<string>","method":"<nome>","params":{…}}`; `id` precisa ser string e `params` é obrigatório (`{}` quando vazio). A resposta é `{"id":…,"result":{"type":"<tipo>",…}}` ou `{"id":…,"error":{"code":"<código>","message":"…"}}`. Todo `result` tem o discriminador `type`.
- **Uma requisição por conexão**: o servidor responde uma linha e fecha. O `HerdrClient` abre uma conexão por requisição (conectar, escrever a linha com `\n`, ler uma linha, fechar). Requisições concorrentes usam conexões concorrentes; não há multiplexação. Uma linha sem `\n` fica sem resposta, então toda requisição tem timeout: 5 s por padrão, 10 s para `agent.prompt`, e `timeout_ms` + 2 s para chamadas com espera.
- **Erros**: erro de parse ou validação (`invalid_request`: método desconhecido, campo faltando, tipo errado, JSON malformado) volta com `"id":""`; os demais ecoam o `id`. Códigos tratados: `invalid_request`, `pane_not_found`, `agent_not_found`, `agent_blocked`, `agent_not_ready`, `agent_prompt_stalled`, `invalid_key`, `timeout`. Código desconhecido vira erro genérico.
- **Parâmetros**: o Herdr **ignora campos desconhecidos em silêncio**, e método com alvo opcional usa o pane **focado** quando o alvo falta. Os tipos de parâmetro do `MochaHerdr` usam os nomes exatos do schema (ex.: `pane.split` usa `target_pane_id`) e sempre informam o alvo. O daemon nunca chama métodos de foco (`*.focus`), `pane.split`, `layout.*` nem escrita de workspace.
- **Versão**: ao conectar e a cada reconexão, `ping` → `{"type":"pong","version":"0.9.1","protocol":22,"capabilities":{…}}`. Com protocolo diferente de 22, o daemon registra erro, `doctor` e `status` avisam, e ele segue em melhor esforço.
- **Decodificação**: campos opcionais vêm **omitidos**, não `null` (`agent`, `agent_session`, `worktree`, `name`, `terminal_title*`, `foreground_cwd`, `tokens`). Campos e tipos desconhecidos são ignorados. `tokens` são metadados de plugins do usuário e não são usados.
- **Inscrições** (`events.subscribe`): a conexão envia **uma** linha `{"id":…,"method":"events.subscribe","params":{"subscriptions":[…]}}`, recebe o ack `{"id":…,"result":{"type":"subscription_started"}}` e daí em diante só recebe eventos, sem replay do que veio antes. Qualquer escrita depois do ack faz o servidor fechar a conexão: o conjunto de uma conexão é imutável, e cancelar é fechar. O servidor não fecha a conexão quando o pane, a tab ou o workspace inscrito some; quem fecha é o cliente.
- Os formatos exatos (respostas, erros, eventos, fluxos reais e o schema completo `herdr-api.schema.json`) estão em `MochaKit/Fixtures/herdr/`. Os tipos de `MochaHerdr` seguem essas fixtures.

#### §3.1.2 Métodos usados

| Método | Parâmetros | Resultado (`type`) | Uso | Fase |
|---|---|---|---|---|
| `ping` | `{}` | `pong` (`version`, `protocol`) | Checagem de versão no connect | 1a-core |
| `session.snapshot` | `{}` | `session_snapshot` (`workspaces`, `tabs`, `panes`, `agents`, `layouts`, `focused_*`, `version`, `protocol`) | Bootstrap e reconciliação da árvore | 1a-core |
| `agent.list` | `{}` | `agent_list` (`pane_id`, `tab_id`, `workspace_id`, `agent`, `agent_status`, `agent_session{value}` = `session_id` do Claude, `cwd`, `foreground_cwd`, `terminal_title_stripped`, `name`) | Reconciliação de sessão (§3.1.3) e `doctor` | 1a-core |
| `agent.get` | `{target}` (pane id ou nome do agente) | `agent_info` | Reconsulta de um agente (sessão, título, status) | 1a-core |
| `workspace.list`, `tab.list`, `pane.get` | `{}`, `{workspace_id?}`, `{pane_id}` | `workspace_list`, `tab_list`, `pane_info` | `doctor` e diagnóstico | 1a-core |
| `agent.prompt` | `{target, text}` | `agent_prompted` (`AgentInfo` do momento do envio) | Enviar prompt ou slash command (texto + Enter, ~300 ms). Com o agente `blocked`, devolve `agent_blocked` sem enviar nada | 1a-core |
| `agent.send_keys` | `{target, keys: [String]}` | `ok` | `["Escape"]` interrompe. Tecla inválida → `invalid_key`, nada é enviado | 1a-core |
| `tab.create` | `{workspace_id, cwd, label?, focus: false}` | `tab_created` (`tab`, `root_pane`) | Nova tab | 1a-final |
| `agent.start` | `{name, kind: "claude", pane_id, args: [String], timeout_ms?}` | `agent_started` (`argv`, `agent` com `launch_pending: true`) | Digita `claude <args>` no shell do pane e volta na hora. A prontidão chega por `pane.agent_status_changed` (`idle`) ou `agent.wait`. `name` único, `[a-z][a-z0-9_-]{0,31}` | 1a-final |
| `agent.wait` | `{target, until: [status], timeout_ms}` | `agent_info` ou erro `timeout` | Esperar a prontidão depois do `agent.start` | 1a-final |
| `agent.read` | `{target, source: "recent_unwrapped", lines}` | `pane_read` (`read.text`) | Diagnóstico (`doctor`) | 1b |

#### §3.1.3 Eventos

- **Envelope**: eventos de ciclo de vida chegam como `{"event":"<nome_com_underscore>","data":{"type":"<nome_com_underscore>",…}}` (a inscrição `workspace.created` produz `workspace_created`). Eventos por pane chegam como `{"event":"pane.agent_status_changed","data":{…}}`, com ponto e sem `data.type`. O decodificador discrimina pelo campo `event`.
- **Conexão global** (tipos sem `pane_id`): `workspace.created`, `workspace.updated`, `workspace.renamed`, `workspace.moved`, `workspace.reordered`, `workspace.closed`, `worktree.created`, `worktree.opened`, `worktree.removed`, `tab.created`, `tab.closed`, `tab.renamed`, `tab.moved`, `pane.created`, `pane.closed`, `pane.updated`, `pane.moved`, `pane.exited`, `pane.agent_detected`. Um `pane_id` nesses tipos é ignorado. Não são usados: `*.focused`, `workspace.metadata_updated` e `layout.updated`.
- **Conexão por pane**: uma conexão por pane com agente, só com `{"type":"pane.agent_status_changed","pane_id":…}`. O `data` traz `pane_id`, `workspace_id`, `agent_status` e, havendo agente, `agent`. O `HerdrBridge` abre a conexão no bootstrap e em `pane_agent_detected` sem `released`; depois do ack, chama `agent.get` para cobrir a janela entre a detecção e a inscrição. Fecha a conexão quando o pane sai do snapshot, em `pane_closed`, `pane_exited` e `pane_agent_detected` com `released: true`; em `pane_moved`, reabre com o id novo. Um `pane_id` inexistente derruba a inscrição (`pane_not_found`, id `"<id>:sub:<índice>:probe"`), por isso cada pane tem a sua conexão.
- **Status**: vem só de `pane.agent_status_changed`, `agent.get` e `session.snapshot`. `idle` e `done` significam pronto (`done` = ainda não visto no Herdr; o daemon não marca como visto, porque isso exige `agent.focus` e move o foco do João). `blocked` cobre diálogo de permissão, pergunta e o diálogo de confiança da pasta na partida. `unknown` = sem agente ou não classificado. O `pane_updated` também traz `agent_status`, mas chega depois e pode ficar defasado. O `agent_status` agregado de tab e workspace prioriza atenção (`done` + `working` → `done`), então o daemon calcula o agregado dele a partir dos agentes.
- **Árvore**: o Herdr não emite cascata (`tab_closed` e `workspace_closed` não trazem `pane_closed` dos panes; o shell que sai emite só `pane_exited`, e a tab que fica vazia some sem `tab_closed`). Eventos estruturais (`workspace_created`, `workspace_closed`, `workspace_moved`, `workspace_reordered`, `workspace_updated`, `worktree_*`, `tab_created`, `tab_closed`, `tab_moved`, `pane_created`, `pane_closed`, `pane_exited`, `pane_moved`, `pane_agent_detected`) disparam, com debounce de 150 ms, um `session.snapshot`, que é comparado ao estado anterior. Rótulos vêm direto do payload: `workspace_renamed`, `tab_renamed`, e `pane_updated` quando muda `terminal_title_stripped`, `cwd`, `foreground_cwd` ou `agent_session`. Toda mudança dispara `treeChanged` para os clientes, com debounce de 150 ms.
- **Troca de sessão**: o Herdr **não emite evento** quando `agent_session.value` muda (`/clear`, `claude` novo no pane). Ele atualiza o valor pelo próprio hook `SessionStart`, sem mudar a `revision` do pane, e o `pane_updated` do mesmo instante (troca de título) ainda traz a sessão antiga. O `HerdrBridge` detecta a troca por: (a) `agent_session.value` diferente em `pane_updated`, `agent.get` ou snapshot; (b) `agent.get` 1 s depois de cada `pane_updated` de pane com agente, e 1 s e 3 s depois de `pane_agent_detected`, até aparecer `agent_session`; (c) `agent.list` a cada 5 s enquanto algum cliente tem chat aberto ou algum agente está `working`/`blocked`; (d) a partir da 1a-final, o hook `SessionStart` do Mocha (`source` `startup`, `resume`, `clear` ou `compact`, com `session_id` e `transcript_path`) como sinal principal, seguido de `agent.get`. Quando a sessão muda, o `TranscriptStore` troca o arquivo acompanhado e o daemon emite `treeChanged` (o `sessionId` do `AgentSummary` muda).
- **`pane_moved`**: o pane ganha id novo (`pane.pane_id`), e `previous_pane_id` é o antigo. O `HerdrBridge` guarda o mapa antigo → novo para traduzir hooks (§3.3.1) e publica o agente com o id novo.
- **Bootstrap e reconexão**: (1) abrir a conexão global e esperar o ack, guardando os eventos que chegarem; (2) `ping` e `session.snapshot`; (3) montar o estado e aplicar os eventos guardados em ordem; (4) abrir as conexões por pane. Se a conexão global receber EOF ou uma requisição falhar ao conectar, o daemon fecha todas as conexões, marca o Herdr indisponível (`herdrUnavailable`) e tenta de novo a cada 2 s, repetindo do passo 1.

#### §3.1.4 Árvore (derivação)

- Os workspaces seguem a ordem de `number`.
- **Diretório do workspace**: `worktree.checkout_path` quando existe; senão, o `cwd` do primeiro pane da tab ativa (`active_tab_id`). O workspace não tem `cwd` próprio.
- `worktree` só aparece em workspaces de um grupo de worktree do Herdr (criados ou abertos por `herdr worktree`, e o workspace principal do repositório). Um workspace aberto num repositório git comum vem sem ele.
- Um workspace com `worktree.is_linked_worktree == true` fica **aninhado** sob o workspace não-ligado de mesmo `repo_key`. Sem pai aberto, ele fica na raiz.
- Um worktree criado pelo agente dentro do próprio pane (ex.: `.claude/worktrees/<nome>`) não vira workspace: aparece só no `foreground_cwd` do pane. Só os worktrees do Herdr são aninhados na gaveta.
- **Branch do agente**: `AgentSummary.branch` é a branch do `foreground_cwd` do pane (`HEAD` lido direto, como acima). A gaveta a mostra na linha do agente só quando ela difere da branch do workspace (ex.: agente num worktree criado dentro do pane).
- **Branch**: ler `HEAD` do git do diretório do workspace direto do arquivo, sem subprocesso. Para worktree ligado, `.git` é um arquivo `gitdir: …`; seguir esse caminho. Com `HEAD` destacado, a branch mostrada são os 7 primeiros caracteres do SHA.
- **`isDirty`**: `git --no-optional-locks -C <diretório> status --porcelain=v1 --untracked-files=normal`, saída não vazia. Sem `--no-optional-locks`, o `status` pega o `index.lock` e pode fazer falhar um `git commit` que um agente esteja rodando no mesmo repositório. Roda no máximo a cada 15 s por workspace, com cache, e é recalculado depois de cada `Stop` do agente desse workspace.
- Tabs sem agente aparecem como shell (ícone `>_`, `label` da tab).
- Uma tab pode ter mais de um agente (panes divididos). Cada agente vira uma linha própria sob a tab.
- Agentes que não são Claude Code (`agent != "claude"`) aparecem com ícone genérico e o nome do agente, mas não abrem chat. O toque mostra "Chat disponível só para Claude Code".

### §3.2 Transcript do Claude Code

#### §3.2.1 Localização

- Arquivo da sessão: `~/.claude/projects/<cwd codificado>/<session_id>.jsonl`.
- Resolução: procurar só `~/.claude/projects/*/<session_id>.jsonl` (um nível), com cache do resultado. **Não** reimplementar a codificação do diretório. Quando o hook traz `transcript_path`, ele tem precedência, mas só vale se, sem `.`/`..` e com os symlinks resolvidos (quando o arquivo ainda não existe, resolve-se o ancestral existente mais próximo), cair dentro de `~/.claude/projects/` (também resolvido) e se chamar exatamente `<session_id>.jsonl`. Senão, é ignorado como se não viesse: vale a busca por `session_id`, com log debug sem o caminho.
- O diretório do projeto também tem `memory/`, `<session_id>/tool-results/`, `<session_id>/subagents/` e `.jsonl` de plugins (ex.: `vercel-plugin/skill-injections.jsonl`, sem `type`). Nunca varrer `**/*.jsonl`.
- **Criação**: numa sessão nova, o arquivo só nasce na primeira mensagem, e o `transcript_path` do `SessionStart` pode apontar para um arquivo que ainda não existe. O diretório do projeto também pode não existir ainda (primeira sessão naquele `cwd`). O `TranscriptStore` trata arquivo inexistente como sessão vazia e observa o diretório do projeto (ou `~/.claude/projects/`, se ele também não existir) até o arquivo aparecer. Depois de `/clear`, o arquivo novo nasce na hora, já com as linhas do `/clear`.
- **Sessões**: `/clear` cria um `session_id` novo e um arquivo novo; o antigo só recebe metadados depois disso. `/compact` mantém o `session_id` e o arquivo.
- **Identidade**: vale `sessionId`. O campo `session_id` (snake_case), presente em parte das linhas, pode trazer a sessão anterior ao `/clear` e é ignorado.
- **Subagentes e workflows**: ficam em `<session_id>/subagents/` e `<session_id>/workflows/` (§3.5). No arquivo principal, cada `Agent` vira um card de subagente e cada `Workflow`, um card de workflow (§3.2.2). O transcript de um subagente (`agent-<agentId>.jsonl`, todas as linhas com `isSidechain: true` e `agentId`) é lido pelo mesmo parser, no modo subagente. Linhas com `isSidechain: true` no arquivo principal são ignoradas por garantia.

#### §3.2.2 Formato e mapeamento (Claude Code 2.1.283)

Uma entrada JSON por linha, com o campo `type`. O formato não é documentado pela Anthropic. As fixtures de `MochaKit/Fixtures/transcripts/` cobrem cada caso, e o README delas traz a sequência esperada. O parser ignora campos desconhecidos, trata tipos desconhecidos pela política abaixo e nunca falha a sessão inteira por causa de uma linha ruim: a linha é descartada e contada.

Cada linha `assistant` tem **um** bloco em `message.content`. Uma resposta da API vira várias linhas com o mesmo `message.id` e `apiBlockIndex` 0, 1, 2… Linhas `user` com `tool_result` podem vir entre blocos da mesma `message.id` (ferramentas em paralelo).

As regras são avaliadas em ordem; vale a primeira que casar.

| Entrada | Condição | Vira |
|---|---|---|
| qualquer | JSON inválido ou sem `type` string | descartada (contador `dropped`) |
| qualquer | `isSidechain == true` | ignorada (aceita no modo subagente, abaixo) |
| `ai-title` | — | `ChatMeta.title` (o último vence); não vira item |
| `permission-mode` | — | `ChatMeta.permissionMode` (o último vence; vistos: `default`, `acceptEdits`, `plan`, `auto`) |
| `mode`, `atis-latch`, `last-prompt`, `agent-name`, `queue-operation`, `file-history-snapshot`, `file-history-delta`, `worktree-state`, `relocated`, `cost-state`, `pr-link`, `frame-link`, `fork-context-ref`, `bridge-session`, `continued-in` | — | ignorados |
| `attachment` | `attachment.type == "queued_command"`, `commandMode == "prompt"`, `origin.kind` ausente ou `human`, sem `isMeta` | `userPrompt`: prompt enviado com o Claude trabalhando. `prompt` é string ou blocos `text`/`image` |
| `attachment` | `queued_command` com `commandMode == "task-notification"` | notificação de tarefa (abaixo), com o texto de `attachment.prompt` |
| `attachment` | demais | ignorado |
| `user` | `origin.kind == "peer"` (mensagem de outra sessão, inclusive o relatório de handback de um subagente) | ignorado |
| `user`, content string | `origin.kind == "task-notification"`, com ou sem `isMeta` (no arquivo do subagente, a notificação de um aninhado vem com `isMeta: true`) | notificação de tarefa (abaixo) |
| `user` | `isMeta == true` | ignorado (caveat de comando local, `turnCompanion`, "[Image: original …]") |
| `user` | `isCompactSummary == true` | ignorado (resumo do `/compact`) |
| `user`, content string | contém `<command-name>/x</command-name>` | `slashCommand(name: "/x", args: <command-args>)`. Se o último `slashCommand` tem o mesmo `promptId` e o mesmo nome, não cria item (eco do `/compact`) |
| `user`, content string | começa com `<local-command-stdout>` ou `<local-command-stderr>` | `output` do último `slashCommand`, sem as tags e sem códigos ANSI → `chatUpdate` |
| `user`, content string | começa com `<bash-input>` (comando `!` do terminal) | `slashCommand(name: "!", args: <comando>)` |
| `user`, content string | começa com `<bash-stdout>` ou `<bash-stderr>` | `output` do último `slashCommand` (stdout, e stderr se não vazio) → `chatUpdate` |
| `user`, content string | o texto é `/compact` ou `/compact <instruções>` | `slashCommand(name: "/compact", args: …)`: a linha crua que o Claude grava antes de compactar |
| `user`, content string | demais | `userPrompt(text, imageCount: 0)` |
| `user`, content array | tem bloco `tool_result` | atualiza o item de `tool_use_id` → `chatUpdate`. Num `toolCall`: `failed` se `is_error == true`, senão `succeeded`, com `resultPreview`. Num `subagent` ou `workflow`: regras de card (abaixo). `tool_use_id` desconhecido: ignorado e contado |
| `user`, content array | um único bloco `text` igual a `[Request interrupted by user]` ou `[Request interrupted by user for tool use]` | `notice("Interrompido pelo usuário")` |
| `user`, content array | blocos `text`/`image` | `userPrompt(text: textos unidos por "\n", imageCount: nº de blocos image)`; outros blocos (ex.: `document`) não contam |
| `assistant` | `isApiErrorMessage == true` ou `message.model == "<synthetic>"` | `notice` com o texto do bloco (ex.: "API Error: …"); não atualiza modelo nem branch |
| `assistant`, bloco `text` | texto não vazio depois de aparar espaços | `assistantText(markdown)` |
| `assistant`, bloco `thinking` | — | `thinking(text:)`, com `nil` quando `thinking == ""` (o caso comum) |
| `assistant`, bloco `redacted_thinking` | — | `thinking(text: nil)` |
| `assistant`, bloco `tool_use` | `name` é `Agent` ou `Task` | `subagent` (card de subagente, abaixo) |
| `assistant`, bloco `tool_use` | `name == "Workflow"` | `workflow` (card de workflow, abaixo) |
| `assistant`, bloco `tool_use` | demais | `toolCall` com `status: running`, `summary` (abaixo) e `inputJSON` do `input` truncado em 4.000 caracteres |
| `assistant`, outro bloco | — | ignorado e contado |
| `system` / `turn_duration` | `durationMs` | `turnFooter(durationMs)`. Turno interrompido não tem `turn_duration`. No modo subagente, ignorado |
| `system` / `away_summary` | `content` | `recap(text)` |
| `system` / `local_command` | `content` com `<command-name>` | `slashCommand`, pela mesma regra de `user` |
| `system` / `local_command` | `content` com `<local-command-stdout>` ou `<local-command-stderr>` | `output` do último `slashCommand` |
| `system` / `compact_boundary` | — | `notice("Conversa compactada")` |
| `system` / `informational`, `model_consent_fallback`, `api_error` | `content` | `notice(content)` |
| `system` / `stop_hook_summary`, `bridge_status`, `agents_killed` | — | ignorados |
| `system`, outro `subtype` | — | ignorado e contado |
| outro `type` | — | ignorado e contado |

**Marcadores de imagem do Mocha** (§6.5): no texto de todo `userPrompt` (content string, blocos `text` ou `prompt` do `queued_command`), cada linha que é exatamente `[imagem: <caminho>]`, com `<caminho>` absoluto dentro de `~/Library/Application Support/Mocha/uploads/`, sai do `text` e soma 1 no `imageCount`. As linhas vazias que sobram no fim do texto são aparadas. Um marcador com caminho fora de `uploads/` fica no texto.

`toolCall.summary` (uma linha, até 120 caracteres):

| Ferramenta | `summary` |
|---|---|
| `Bash` | primeira linha de `command` |
| `Read`, `Write`, `Edit`, `NotebookEdit` | `file_path` (no `NotebookEdit`, `notebook_path`), relativo ao `cwd` da linha quando está dentro dele |
| `Grep`, `Glob` | `pattern` |
| `WebFetch` | `url` |
| `WebSearch`, `ToolSearch` | `query` |
| `Agent`, `Task` | `description` |
| `AskUserQuestion` | `questions[0].question` |
| `ExitPlanMode` | primeira linha não vazia de `plan` |
| `Skill` | `skill` |
| `TaskOutput`, `TaskStop` | `task_id` |
| demais, inclusive `mcp__*` | primeiro valor string não vazio do `input` |

`toolCall.resultPreview`, truncado em 2.000 caracteres no daemon:
- `content` string: como está.
- `content` array: os `text` unidos por `\n`; `image` vira `[imagem]`, `tool_reference` vira o `tool_name` e `document` vira `[documento]`.
- `AskUserQuestion` com `toolUseResult.answers`: uma linha `pergunta → resposta` por pergunta (`multiSelect` vem com os rótulos separados por vírgula).
- Pedido negado (`toolDenialKind` `user-rejected`, `automode-blocked` ou `automode-unavailable`) e Esc com a ferramenta rodando chegam com `is_error: true` e viram `failed`.

**Card de subagente** (`subagent(SubagentCall)`, fase subagentes; dados em §3.5):
- `tool_use` `Agent` ou `Task`: `toolUseId` = `id`; `description` = `input.description`; `agentType` = `input.subagent_type` sem o prefixo de plugin (o texto depois do último `:`, ex.: `feature-dev:code-reviewer` → `code-reviewer`), ou `general-purpose` quando falta; `status: running`, `toolUses: 0` e o resto `nil`. Cada chamada é um item próprio.
- `tool_result` desse `tool_use`:
  - `toolUseResult.status == "async_launched"` (lançamento em background, o caso de toda chamada observada na 2.1.283): só preenche `agentId` com `toolUseResult.agentId`;
  - resultado síncrono (`toolUseResult` com `totalToolUseCount` e `totalDurationMs`): `completed`, com `agentId`, `toolUses` = `totalToolUseCount` e `durationMs` = `totalDurationMs`;
  - `is_error == true`: `failed`, com `failureReason` = o texto do resultado (regra do `resultPreview`).
- O parser só conhece o lançamento, o resultado síncrono e as notificações de tarefa. A ferramenta atual, a contagem, o início e o fim ao vivo vêm do daemon, que os sobrepõe ao item (§4.1.2).

**Card de workflow** (`workflow(WorkflowCall)`):
- `tool_use` `Workflow`: `name` = o `name` do `meta` do `input.script` (§3.5.3); sem script inline ou sem `name`, o nome do arquivo de `input.scriptPath` sem a extensão e sem o sufixo `-wf_<runId>`; sem os dois, "Workflow". `status: running`, `phases: []`, `agentCount: 0`, `toolUses: 0` e `startedAt` = `timestamp` da linha.
- `tool_result`: com `toolUseResult.status == "async_launched"`, preenche `runId` e troca o `name` por `toolUseResult.workflowName`; o parser guarda o `toolUseResult.taskId` para casar a notificação. Com `is_error == true`, `failed`.
- Fases, agentes e contagens ao vivo vêm do daemon (§3.5.3, §4.1.2).

**Notificação de tarefa**: linha `user` com `origin.kind == "task-notification"` ou `attachment` `queued_command` com `commandMode == "task-notification"`. A detecção é só por esses campos: a string `<task-notification>` também aparece em `queue-operation`, `prompt_snapshot` e `deferred_tools_record`, que não geram nada. O texto pode ter mais de um bloco `<task-notification>…</task-notification>` (com as tags `<task-id>`, `<tool-use-id>` opcional, `<status>`, `<summary>`, `<note>`, `<result>` e `<usage>`), e cada bloco é tratado à parte, pelo `<task-id>`:
- `^a[0-9a-f]{16}$` (agente): atualiza o `subagent` cujo `toolUseId` é o `<tool-use-id>` ou, sem ele, cujo `agentId` é o `<task-id>` → `chatUpdate`, sem gerar item. `<status>` `completed` → `completed`; `failed` → `failed`, com `failureReason` = o texto do `<summary>` depois de `failed: `; `killed` → `stopped`. Um `<note>` com "stopped with background work of its own still running" (resultado interino) mantém `running`. `<usage>` preenche `toolUses` (`<tool_uses>`) e `durationMs` (`<duration_ms>`).
- `^w[0-9a-z]{8}$` (workflow): atualiza o `workflow` do `<tool-use-id>` ou do `taskId` guardado → `chatUpdate`, sem gerar item. `completed` → `completed`, `failed` → `failed`, `killed` → `stopped`; `<usage>` preenche `agentCount` (`<agent_count>`), `toolUses` e `durationMs`.
- demais (Bash e Monitor, `^b…`, e bloco sem `<task-id>`): `notice` com o `<summary>`.
- agente ou workflow sem card carregado (outra página, ou o `tool_use` numa sessão anterior): o bloco não gera nada.
- texto sem nenhum bloco (ex.: "2 background agents were stopped by the user: …", visto na 2.1.252): `notice` com o texto.
- Assim, o aviso `Agent "…" finished` não aparece no chat: o card mostra o fim. Com mais de um `notice` na mesma linha, os ids seguem a regra `<uuid>#<índice>`.
- A leitura dos blocos é pública, em `MochaTranscript`: `TaskNotification.parse(_ text: String) -> [TaskNotification]`, com `taskId`, `toolUseId`, `status`, `summary`, `note`, `toolUses`, `durationMs` e `agentCount`. O daemon usa a mesma função nos sinais (b) e (c) da §3.5.2.

**Modo subagente** (transcript `agent-<agentId>.jsonl`, aberto pelo chat de subagente, §5.3.1): a entrada é `TranscriptParseMode.subagent(forkToolUseId: String?)`, em `MochaTranscript` (o padrão é `.main`), que o `TranscriptStore` monta a partir do `SubagentTranscript` (§4.1.1). Valem as mesmas regras, com estas diferenças:
- linhas com `isSidechain == true` são aceitas;
- a primeira linha `user` com `parentUuid == null` vira `task(text:)` (a tarefa que o pai passou), com o id da linha;
- **fork** (`meta.isFork`, fronteira em `meta.toolUseId`): tudo até a linha `user` que traz o `tool_result` de `tool_use_id == meta.toolUseId` é pulado (o `fork-context-ref`, ou as linhas copiadas do pai-subagente num fork aninhado, e a cópia do `tool_use`). Essa linha vira `task(text:)` com o texto do bloco `text` depois de `Your directive: ` (o bloco inteiro, se o marcador faltar);
- `Agent` e `Task` dentro dele viram `subagent` (aninhado), pelas regras acima;
- `system`/`turn_duration` não gera `turnFooter`: o rodapé do fim e o motivo da falha vêm do `ChatMeta.subagent` (§5.2), e o app os desenha (§6.3);
- o título do chat vem do daemon (§4.1.2), não de `ai-title`.

Regras:

- **Ordem**: a do arquivo. `timestamp` não é monotônico (no `/compact`, linhas gravadas depois têm hora anterior) e só alimenta `ChatItem.at`.
- **Ids**:
  - O id do item é `<uuid da linha>`, ou `<uuid>#<índice do bloco>` se uma linha trouxer mais de um bloco (não observado até a 2.1.283). Um `userPrompt` de `queued_command` usa o `uuid` da linha `attachment`.
  - Linhas que só atualizam outro item não geram id: saída de comando, `tool_result` e eco do `/compact`.
- **`tool_result`**: vem sempre depois do `tool_use`, em até 50 linhas no corpus (99 % em até 3). Um `tool_use` sem resultado fica `running` (AskUserQuestion esperando resposta ou sessão encerrada).
- **Header**:
  - Modelo e branch vêm da última linha `assistant` que não seja `<synthetic>` (`message.model`, `gitBranch`).
  - `gitBranch == "HEAD"` (pasta sem git ou HEAD destacado) vira `nil`. O modelo pode ter sufixo de data (`claude-haiku-4-5-20251001`).
  - O título vem do último `ai-title`, que começa como frase e depois vira o nome em kebab-case (igual ao título do terminal). Na falta dele, vem de `terminal_title_stripped` do Herdr.
- **Meta da Home** (campos do `TranscriptMeta`, §4.1.1, derivados dos mesmos itens da tabela acima):
  - `preview`: o último item `userPrompt` (autor `user`) ou `assistantText` (autor `assistant`) do arquivo. O texto passa por `PlainText.preview(fromMarkdown:)` (`MochaTranscript`): tira cercas e crases de código, marcadores de ênfase, `#` de título, marcadores de lista e de citação, troca `[texto](url)` por `texto`, junta todos os espaços e quebras num espaço só e corta em 200 caracteres, sem reticências. Um `userPrompt` só com imagens vira `[imagem]`. Sem nenhum desses itens (sessão nova ou recém-limpa), `nil`.
  - `prompt`: o texto do último `userPrompt` do arquivo (inclusive `queued_command`), com a mesma limpeza e o mesmo corte do `preview` (`[imagem]` quando só tem imagens). Fica mesmo depois que o assistente responde; sem nenhum, `nil`. Só alimenta a Live Activity (§7.5) e não entra no `AgentSummary`.
  - `activity`: o último `toolCall` com `status == running`; sem nenhum rodando, o último `toolCall` do arquivo. Leva `name`, `summary` e `status`. Os itens `subagent` e `workflow` não são `toolCall` e não entram aqui.
  - `contextTokens`: `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` do `message.usage` da última linha `assistant` que não seja `<synthetic>` nem erro de API (sem `output_tokens`; sidechain já é ignorada).
  - `sessionStartedAt`: o `timestamp` da primeira linha do arquivo que tem `timestamp`.
  - `turnStartedAt`: o `timestamp` do último `userPrompt` vindo de uma linha `user` (o `queued_command` não abre turno).
  - `turnEndedAt`: o `timestamp` da última linha `system`/`turn_duration`. Turno interrompido não tem `turn_duration`, então `turnEndedAt` pode ficar anterior ao `turnStartedAt`.
- **Escrita**:
  - O Claude grava cada bloco completo, sem streaming por token. Enquanto o status for `working`, o app mostra o indicador de "trabalhando".
  - Os metadados (`last-prompt`, `ai-title`, `mode`, `permission-mode`, `atis-latch`) são regravados em grupo durante o turno, então `permissionMode` pode atrasar alguns segundos em relação ao terminal.
- **Comando local**: a saída pode ter códigos ANSI (`\u001b[2m…`), removidos antes de enviar. Quebras de linha nas pontas são aparadas; espaços iniciais ficam (saída de `git status`).

Política para tipos novos:

1. `type`, `subtype` ou tipo de bloco desconhecido: a linha (ou o bloco) é ignorada e contada por nome (`type:<x>`, `subtype:<x>`, `block:<x>`), com um aviso no log por nome e por arquivo, não por linha. Anexos que não são `queued_command` são ignorados sem contagem (o corpus tem dezenas de tipos de `attachment`).
2. Campos desconhecidos são sempre ignorados. Campos esperados ausentes usam o padrão: `is_error` ausente é sucesso, `thinking` ausente é vazio.
3. O `doctor` mostra, por sessão acompanhada, a versão do Claude (`version` da última linha), as linhas descartadas e os desconhecidos por nome. Ele avisa quando a versão é maior que a última validada: 2.1.283, conferida pelo WP-M2 com as fixtures e 149 transcripts reais (2.1.263 a 2.1.283), sem linhas descartadas nem tipos desconhecidos.
4. Um tipo novo que precise aparecer no chat entra nesta tabela junto com uma fixture e o snapshot esperado.

#### §3.2.3 Leitura e desempenho

- Os arquivos passam de dezenas de MB em sessões longas, e uma linha pode passar de 1 MB (imagem colada em base64; a maior vista tinha 1,8 MB).
- **Primeira abertura**:
  - Varredura única do arquivo, montando um índice de offsets de linha; a última linha sem `\n` fica fora do índice.
  - Página inicial = últimos `limit` itens, lidos a partir do fim.
  - Ao montar qualquer página, as até 64 linhas anteriores servem de contexto (eco do `/compact`), e os `tool_result` e as saídas de comando das até 64 linhas seguintes ao fim dela são aplicados aos itens da página.
  - Meta: `chatPage` em < 300 ms para um arquivo de 50 MB no M1 (fixture de `scripts/gen-big-transcript.swift`).
- **Acompanhamento**: `DispatchSource.makeFileSystemObjectSource` (`.extend`, `.write`, `.rename`, `.delete`), lendo de `lastOffset` até o fim. Linha incompleta (sem `\n`) fica em buffer até completar.
- **Arquivo que ainda não existe** (sessão nova sem mensagem): observar o diretório do projeto, ou `~/.claude/projects/` se ele também não existir, até o arquivo aparecer.
- **Cursor de paginação**: opaco para o app. Internamente é `<sessionId>:<offset>`, com o offset da primeira linha da página que gera item, que precisa ser o início de uma linha do índice. No chat de subagente, é `<sessionId>/<agentId>:<offset>`, no arquivo do subagente. Linhas sem item entre duas páginas (resultados, saídas) ficam na página mais antiga. `hasMore` é `true` quando existe uma linha com item antes da página; sem ele, `before` vem `nil`. Cursor de outra sessão, de outro subagente ou fora do índice é inválido (§5.3.1).
- O daemon só acompanha arquivos de sessões com chat aberto em algum cliente, com agente `working`/`blocked` (necessário para a Home ao vivo, o push e a Live Activity) ou com subagente ou workflow `running` (§3.5). Fora disso, fecha o descritor.
- **Meta sem acompanhamento**: com a sessão acompanhada, o `TranscriptMeta` sai do estado já montado. Fora disso, `meta(forSession:)` lê o fim do arquivo de trás para a frente, em blocos, até achar todos os campos ou ler 8 MB (o que faltar fica `nil`), e a primeira linha para o `sessionStartedAt`. O resultado fica em cache por tamanho e mtime.

### §3.3 Hooks do Claude Code

#### §3.3.1 Instalação

`mochad install-hooks` faz merge em `~/.claude/settings.json` (JSON; backup em `settings.json.mocha-bak` antes da primeira escrita). O bloco exato está em `MochaKit/Fixtures/hooks/settings.install-hooks.proposed.json`.

- **`PermissionRequest`**: uma entrada `type: "http"`, sem `matcher` (cobre as ferramentas e o AskUserQuestion), com `url: "http://127.0.0.1:47420/hooks/PermissionRequest"`, `headers: {"X-Mocha-Pane": "$HERDR_PANE_ID", "X-Mocha-Hook-Secret": "<segredo literal>"}`, `allowedEnvVars: ["HERDR_PANE_ID"]` e `timeout: 590`. É o único evento que precisa segurar a resposta.
- **`SessionStart`, `UserPromptSubmit`, `Stop` e `Notification`**: uma entrada `type: "command"` por evento, com `async: true`, `timeout: 5` e o comando
  `/usr/bin/curl -s -m 3 -o /dev/null -X POST -H 'Content-Type: application/json' -H "X-Mocha-Pane: $HERDR_PANE_ID" -H 'X-Mocha-Hook-Secret: <segredo literal>' --data-binary @- http://127.0.0.1:47420/hooks/<Evento> || true`.
  - O Claude Code não aceita hook `http` no `SessionStart` e ignora a entrada em silêncio.
  - Com o daemon parado, hook `http` que falha mostra "<Evento> hook error · connect ECONNREFUSED" no terminal a cada turno. O comando com `|| true` falha em silêncio. No `PermissionRequest`, a falha do `http` já é silenciosa, e o diálogo segue.
  - `-o /dev/null` é obrigatório: no `SessionStart` e no `UserPromptSubmit`, a saída em texto vira contexto do Claude.
  - Com `async: true`, o Claude não espera o comando e não aplica o `timeout`; quem limita o tempo é o `-m 3` do `curl`. O `$HERDR_PANE_ID` é expandido pelo shell do hook, que herda o ambiente do pane.
- `HERDR_PANE_ID` existe no ambiente de todo processo dentro de um pane do Herdr, junto com `HERDR_TAB_ID` e `HERDR_WORKSPACE_ID`. Hook de Claude fora do Herdr chega com o header vazio e é ignorado. Esses valores são fixados quando o processo nasce. Depois de um `pane_moved` entre workspaces, o Claude continua mandando o `HERDR_PANE_ID` antigo; o `HookServer` traduz pelo mapa `previous_pane_id → pane.pane_id` do `HerdrBridge`.
- O segredo é o `hookSecret` do `config.json`, escrito literalmente no header e no comando. O `HookServer` responde 401 sem ele. O segredo fica em texto no `settings.json` e aparece na linha de comando do `curl` enquanto o hook roda; isso é aceito num Mac de um usuário só. Por isso o `install-hooks` grava o `settings.json` e o `settings.json.mocha-bak` em 0600, qualquer que seja a permissão anterior.
- **`HookServer`**:
  - rotas `POST /hooks/<Evento>`, respondendo 200 com JSON (`{}` quando não decide), ou 401 sem o segredo;
  - o cliente dos hooks `http` é o `axios`, com `Connection: keep-alive`. O `HttpServer` (§4.4) responde sempre com `Connection: close`, e o axios abre outra conexão no hook seguinte; fechar sem esse header faz o hook seguinte falhar com `ECONNRESET`, visível no terminal;
  - campos opcionais vêm omitidos: `model` (ausente no `clear`), `prompt_id`, `title`, `scratchpad_dir`, `permission_suggestions`, `agent_id` e `agent_type`. Campos desconhecidos são ignorados.
- Nunca altera nem remove hooks de terceiros. O hook `herdr-agent-state.sh` do Herdr no `SessionStart` **deve continuar**, porque é ele que informa ao Herdr o `session_id` de cada pane. Sem esse hook, `agent_session` não existe no Herdr.
- É idempotente: as entradas do Mocha são reconhecidas por `127.0.0.1:47420/hooks/` na `url` ou no `command`, e rodar de novo não duplica nada. `mochad uninstall-hooks` remove só essas entradas.

| Evento | Tipo | Uso | Timeout | Fase |
|---|---|---|---|---|
| `SessionStart` | comando | pane → `session_id`/`transcript_path`/`source` (`startup`, `resume`, `clear`, `compact`, `fork`). O `compact` mantém o `session_id`, e o `clear` traz sessão nova. O `transcript_path` pode apontar para um arquivo que ainda não existe. `model` pode faltar | 5 s | 1a-final |
| `UserPromptSubmit` | comando | Início do turno (`prompt`, `prompt_id`). Não dispara para `/clear`, `/compact` e `/exit` | 5 s | 1a-final |
| `Stop` | comando | Turno concluído → push; `last_assistant_message`. Não dispara em turno interrompido (Esc, "No" no diálogo) | 5 s | 1a-final |
| `Notification` | comando | Sinal secundário: `permission_prompt` (~6 s depois de um diálogo ou seletor sem tecla; cada tecla adia), `idle_prompt` (~60 s depois do fim do turno sem tecla), `elicitation_dialog` (formulário MCP) | 5 s | 1a-final |
| `PermissionRequest` | `http` | Aprovação e pergunta (§8). Na 1a-final, responde `{}` na hora, só para notificar | 590 s | 1a-final (notifica), 1b (decide) |

#### §3.3.2 Coexistência com o moshi-hook

O Mac tem o `moshi-hook` (Homebrew, serviço `sh.brew.moshi-hook`) instalado com hooks em `Notification`, `PermissionRequest`, `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `Stop` e `UserPromptSubmit`. Dois hooks que decidem `PermissionRequest` competem entre si.

- `mochad doctor` e `install-hooks` detectam entradas com `moshi-hook` no `settings.json` e avisam, mostrando o comando de remoção: `moshi-hook uninstall` e depois `brew services stop moshi-hook`.
- Antes da 1b (quando o Mocha passa a decidir), o `moshi-hook` precisa estar desinstalado (bloqueio B7).

### §3.4 Uso do plano e contexto

- **Cache do plugin `herdr-agent-usage`**: `~/.local/state/herdr/plugins/herdr-agent-usage/claude-statusline.json`, gravado pelo plugin do Herdr do João a partir do stdin do statusLine do Claude Code, a cada turno. O plugin grava por rename, então o daemon observa o **diretório** (`DispatchSource` `.write`) e reabre o arquivo a cada mudança, com debounce de 500 ms. Formato usado (o resto é ignorado):
  - `fetched_at_unix`: segundos Unix da última gravação;
  - `windows[]`: `{kind: "five_hour" | "weekly", used_percent, remaining_percent, resets_at}` (`resets_at` em segundos Unix). Outros `kind` são ignorados;
  - `session_contexts.<sessionId>.used_percent`: contexto usado da sessão, em %;
  - `session_models.<sessionId>`: nome de exibição do modelo da sessão (ex.: `"Opus 5.5 (1M context)"`).
  - Fixture sintética em `MochaKit/Fixtures/usage/claude-statusline.json`.
- **Plano e conta**: o daemon lê de `~/.claude.json` só `oauthAccount.organizationRateLimitTier` e `oauthAccount.emailAddress`, com cache por mtime, e nunca grava nem registra no log o conteúdo desse arquivo. O plano vem do tier: contém `max_20x` → "Max 20x"; contém `max_5x` → "Max 5x"; contém `pro` → "Pro"; outro valor → `nil`. A conta é o e-mail mascarado: primeira letra do usuário + `•••` + `@` + primeira letra do domínio + `•••` + o último rótulo com o ponto (`dev@example.com` → `d•••@e•••.com`). Fixture sintética em `MochaKit/Fixtures/usage/claude.json`, com só essas duas chaves. **Os nomes das chaves e os valores de tier são inferidos e precisam da conferência do João** (a leitura de `~/.claude.json` pelos agentes é bloqueada).
- **Contexto livre** (`AgentSummary.contextLeftPercent`, 0–100, arredondado):
  1. `100 − session_contexts.<sessionId>.used_percent` do cache do plugin, quando a sessão está lá;
  2. senão, `100 − contextTokens × 100 / janela`, com `contextTokens` do `TranscriptMeta` (§3.2.2) e a janela pelo modelo do transcript (`ContextWindow.size(forModel:)` em `MochaTranscript`): 1.000.000 para `claude-opus-4-7` ou mais novo, `claude-opus-5*`, `claude-fable*` e `claude-sonnet-5*`; 200.000 para os demais;
  3. sem os dois, `nil`.
- **Sem cache**: arquivo ausente ou inválido → sem `usage` para os clientes (o app esconde a pílula de uso) e contexto só pelo transcript. O `doctor` mostra o item Uso: ✅ com a idade do cache, ⚠️ sem o arquivo.

### §3.5 Subagentes e workflows

Fase subagentes. Formatos conferidos no Claude Code 2.1.283, cobertos pelas fixtures redigidas de `MochaKit/Fixtures/transcripts/`. Nada disto é documentado pela Anthropic: a leitura é tolerante como a da §3.2.2, e campos desconhecidos são ignorados.

#### §3.5.1 Arquivos e ligação

```
~/.claude/projects/<proj>/
  <sessionId>.jsonl                          transcript principal
  <sessionId>/
    subagents/
      agent-<agentId>.jsonl                  transcript do subagente (append)
      agent-<agentId>.meta.json              sidecar (reescrito inteiro, com inode novo)
      workflows/
        wf_<runId>/                          um por workflow; pode ser symlink (§3.5.3)
          journal.jsonl                      progresso (append)
          agent-<agentId>.jsonl, .meta.json  agentes do workflow
    workflows/
      wf_<runId>.json                        estado final (escrito uma vez, no fim)
      scripts/<nome>-<runId>.js              script de um Workflow com script inline
```

- **Ids**: `agentId` = `a` + 16 hex; `runId` = `wf_` + 8 hex + `-` + 3 hex; `taskId` de workflow = `w` + 8 alfanuméricos; o de Bash e Monitor, `b` + 8.
- **O que é subagente**: cada `tool_use` `Agent` (ou `Task`, o nome antigo) do transcript principal; os aninhados (`meta.spawnDepth == 2`, `meta.parentAgentId`), com o arquivo no mesmo `subagents/` e o `tool_use` dentro do arquivo do pai; e os agentes de workflow (`meta.agentType == "workflow-subagent"`, arquivo em `workflows/wf_<runId>/`, sem `tool_use` próprio). O fork (`agentType: "fork"`, `isFork: true`) é um subagente comum. A skill que roda como agente (meta com `name` e sem `toolUseId`) é ignorada.
- **Ligação**: `tool_use.id` = `meta.toolUseId`; `toolUseResult.agentId` do `tool_result` = `<task-id>` da notificação = o `<agentId>` do nome do arquivo. A chave confiável é o `agentId`. O workflow liga pelo `toolUseResult.runId` e pelo `toolUseResult.taskId` do `tool_result` do `Workflow`.
- **`meta.json`**: campos usados `agentType`, `description`, `toolUseId`, `parentAgentId`, `spawnDepth`, `isFork`, `workflowPhase`, `name` e `stoppedByUser`; os outros são ignorados. Ele não tem estado nem horários. O tipo exibido é o `agentType` sem o prefixo de plugin (o texto depois do último `:`), e o daemon já o manda assim.
- **Escrita**:
  - os `.jsonl` crescem por append: leitura incremental por offset, com a última linha parcial em buffer (§3.2.3);
  - o `meta.json` é reescrito inteiro com inode novo: é relido pelo caminho a cada evento do diretório, nunca por um descritor aberto;
  - o `.jsonl` e o `meta.json` nascem em qualquer ordem: um `.jsonl` sem meta é aceito, e o meta completa os campos quando chega;
  - em `subagents/`, tudo o que não é `agent-<id>.jsonl`, `agent-<id>.meta.json` ou `workflows/` é ignorado, inclusive os sidecars `*.forked-skill*.json`. Nunca varrer `**/*.jsonl`: o `journal.jsonl` também é `.jsonl`.

#### §3.5.2 Estado de um subagente

`SubagentStatus` (§5.2): `running`, `completed`, `failed` e `stopped` (parado pelo Claude com `TaskStop` ou pelo usuário). O estado é o do sinal mais recente, e os sinais chegam nesta ordem:

**(a) Fim no próprio arquivo**, pela última linha que não é `attachment`:

| Última linha | Estado |
|---|---|
| `assistant` com bloco `text` e `stop_reason == "end_turn"` (com ou sem o `SubagentHandback` antes) | `completed` |
| `assistant` com `isApiErrorMessage == true` (modelo `<synthetic>`) | `failed`; motivo = o texto do bloco |
| `user` com o bloco `text` `[Request interrupted by user]` | `stopped` |
| agente de workflow: `user` com o `tool_result` do `tool_use` `StructuredOutput` | `completed` |
| qualquer outra | `running` |

`meta.stoppedByUser == true` também vale `stopped`.

**(b) `queue-operation` com `operation == "enqueue"`** no transcript principal, com o texto da notificação do agente. É gravado no instante do fim, inclusive para os aninhados, cuja notificação é entregue no transcript do pai-subagente.

**(c) Notificação entregue** no transcript principal (`attachment` `queued_command` com `commandMode == "task-notification"`, ou `user` com `origin.kind == "task-notification"`), com o `<status>` e o `<usage>` finais. Uma notificação já aplicada pelo `enqueue` não muda o estado; só completa o que faltava.

- Os blocos de (b) e (c) seguem a notificação de tarefa da §3.2.2: `completed` → `completed`, `failed` → `failed`, `killed` → `stopped`, e a nota interina ("stopped with background work of its own still running") → `running`.
- Uma linha nova que não seja `attachment` no arquivo do subagente depois de um fim (retomado por `SendMessage`, com `origin.kind: "coordinator"`) volta para `running`. Um `attachment` depois do fim (ex.: `prompt_snapshot` depois do `end_turn`) não muda o estado.
- Sem marcador de fim, o estado fica `running`, mesmo que o processo do Claude tenha caído. Numa saída normal do Claude, os subagentes ganham `[Request interrupted by user]`.
- Na primeira leitura de uma sessão (daemon iniciando, sessão nova no conjunto observado), os sinais já gravados são comparados pelo `timestamp`: vale o mais recente entre a última linha do arquivo do subagente e as notificações dele.

**Métricas**, do arquivo do subagente (num fork, só depois da fronteira da §3.2.2):
- `activity` (ferramenta atual): o último `tool_use` sem `tool_result`, com o `summary` da §3.2.2; `nil` sem ferramenta pendente e fora de `running`.
- `toolUses`: número de blocos `tool_use`.
- `startedAt`: `timestamp` da primeira linha que tem `timestamp` (num fork, o da linha da fronteira).
- `durationMs`, só no fim: `<usage><duration_ms>` da notificação; sem ela, o `timestamp` da última linha menos o `startedAt`.
- `failureReason`, só em `failed`: quando a última linha do arquivo do subagente (fora os `attachment`) é o erro sintético, o texto dele ("API Error: …"), que não muda quando a notificação chega; senão, o texto do `<summary>` depois de `failed: ` ("Agent terminated early due to an API error: …"). Fica no original, em inglês, sem tradução.
- Tokens não entram no protocolo.

#### §3.5.3 Workflows

- **Lançamento**: `tool_use` `Workflow` com `input` `{args, script}` ou `{args, scriptPath}`. O `tool_result` traz `toolUseResult` com `status: "async_launched"`, `runId` (`wf_…`), `taskId` (`w…`), `workflowName`, `transcriptDir` e `scriptPath`.
- **Ao vivo**: `subagents/workflows/wf_<runId>/journal.jsonl`, sem timestamps, com três tipos de linha: `{"type":"launched"}`, `{"type":"started","key","agentId","label","phase"}` e `{"type":"result","key","agentId","result"}`. Uma nova tentativa grava outro `started` com a mesma `key` e outro `agentId`: vale o último. Cada agente tem o `meta.json` (`description` = `label`, `workflowPhase` = `phase`) e o transcript, como na §3.5.1.
- **Fases**: vêm do literal `export const meta = { …, phases: [{title, detail?}, …] }` do script: o `input.script` ou o arquivo de `input.scriptPath` (ou do `toolUseResult.scriptPath`), lido até 1 MB. O parser (`WorkflowScriptMeta`, em `MochaTranscript`) é tolerante: acha o objeto `meta`, lê o `name` e a chave `phases`, e em cada objeto do array lê `title` e `detail` como literal de string (aspas simples, duplas ou crase sem `${`). Qualquer outra forma é falha, sem erro, e as fases passam a ser as vistas no journal, na ordem da primeira aparição.
- **Agentes de uma fase**: os `started` do journal com aquela `phase` (a última tentativa de cada `key`), na ordem do journal. O estado de cada um segue a §3.5.2, e a linha `result` do journal confirma `completed`.
- **Estado da fase** (`WorkflowPhaseStatus`): `pending` sem agente; `running` com algum agente `running`; `failed` sem nenhum `running` e com algum `failed` ou `stopped`; `completed` nos demais.
- **Contagens ao vivo**: `agentCount` = número de `key` distintas; `toolUses` = soma do `toolUses` da última tentativa de cada `key`; `startedAt` = `timestamp` da linha do `tool_use`.
- **Fim**, pelo que chegar primeiro:
  - `workflows/wf_<runId>.json`, escrito uma vez no fim, procurado no `workflows/` da sessão e, se não estiver lá, no de outra sessão do mesmo projeto: `status` (`completed`, `failed`, `killed` → `stopped`), `phases` (com `detail`; substituem as extraídas do script), `agentCount`, `totalToolCalls` (→ `toolUses`), `durationMs` e `workflowProgress` (estado final de cada agente: `done` → `completed`, `error` → `failed`);
  - a notificação `Dynamic workflow "…" completed` (`<task-id>` `^w…`), pela §3.2.2.
- `WorkflowStatus`: `running`, `completed`, `failed` e `stopped`.
- **Workflow retomado em outra sessão**: `subagents/workflows/wf_<runId>` pode ser um symlink para o diretório de outra sessão. O daemon segue o link e deduplica pelo caminho real.

#### §3.5.4 Leitura no daemon

- O `SubagentStore` (§4.1.1) observa as sessões atuais dos agentes Claude da árvore e as sessões dos chats abertos. Por sessão:
  - `DispatchSource` de diretório em `<sessionId>/subagents/`, `subagents/workflows/`, cada `wf_<runId>/` e `<sessionId>/workflows/`, para ver arquivos novos e o `meta.json` reescrito. Enquanto um deles não existe, observa o ancestral existente mais próximo, até o diretório do projeto;
  - `DispatchSource` de arquivo (`.extend`, `.write`, `.rename`, `.delete`) e leitura incremental em cada `agent-<id>.jsonl` `running` e em cada `journal.jsonl` de workflow `running`. O descritor fecha no fim;
  - leitura do transcript principal, só para os sinais (b) e (c) da §3.5.2 e para o `tool_use` e o `tool_result` de `Workflow` (script, nome e `runId`):
    - na primeira observação, do fim para trás, em blocos, até 8 MB (como o meta sem acompanhamento, §3.2.3). Um subagente cujos sinais ficaram antes disso vale só pelo sinal (a), e as fases de um workflow lançado antes vêm do journal;
    - depois, incremental a partir do último offset lido, com `DispatchSource` de arquivo próprio, nas mesmas condições do acompanhamento da §3.2.3 (chat aberto, agente `working`/`blocked` ou subagente ou workflow `running`). Fora delas, fecha o descritor e retoma do último offset quando a sessão volta a ser acompanhada;
    - só são decodificadas as linhas que passam por um pré-filtro de texto; a detecção em si é pelos campos da §3.2.2.
- O estado de um arquivo terminado fica em cache por tamanho e mtime e não é relido.

---

## §4 mochad (daemon do Mac)

### §4.1 Componentes

Todos são `actor`s ou tipos `Sendable`, com Swift 6 e strict concurrency completo.

| Componente | Responsabilidade |
|---|---|
| `HerdrClient` (`MochaHerdr`) | Conexões com o socket, requisições com id, stream de eventos (`AsyncStream`) que termina no EOF |
| `HerdrBridge` | Snapshot inicial, inscrições e reconexão (§3.1.3), árvore derivada (§3.1.4), comandos (prompt, Esc, teclas, nova tab) |
| `TranscriptStore` | Resolução de arquivo, índice de offsets, páginas, acompanhamento, deltas por sessão |
| `SubagentStore` | Subagentes e workflows das sessões observadas: estado, métricas, contagem dos que rodam e resolução do arquivo do subagente (§3.5) |
| `SessionHub` | Clientes conectados, chats abertos por cliente, primeiro plano por cliente, broadcast |
| `UsageMonitor` | Cache de uso do plugin e plano da conta (§3.4); contexto usado por sessão |
| `SessionArchive` | Sessões encerradas e arquivamento pelo usuário, persistidos em `sessions.json` (§4.9) |
| `HttpServer` | HTTP/1.1 mínimo sobre `NWListener` (§4.4) |
| `Gateway` | Rotas do app sobre o `HttpServer`: WebSocket `/v1` e HTTP de ações e upload (§5) |
| `HookServer` | Rotas `/hooks/<evento>` no listener local, validação do segredo, tradução em eventos internos |
| `PendingStore` | Pedidos pendentes (1b), timeouts e resolução |
| `PushService` | APNs: JWT, alertas, Live Activity, escolha de ambiente (§7) |
| `DeviceStore` | Aparelhos pareados (§4.6) |
| `Pairing` | Emissão do código de pareamento e troca por token (§4.5) |
| `LocalControl` | Canal local da CLI no socket Unix (§4.8) |

#### §4.1.1 Interfaces internas

Esboço normativo, como a §5.2. Nomes valem como estão; a implementação pode acrescentar.

**`HerdrBridging`**: declarado em `MochaDaemonCore/Herdr/` e implementado pelo `HerdrBridge`.

```swift
public protocol HerdrBridging: Sendable {
    func events() -> AsyncStream<HerdrBridgeEvent>
    var isAvailable: Bool { get async }
    func tree() async -> [WorkspaceNode]
    func agent(_ id: AgentID) async -> HerdrAgent?
    func resolve(_ id: AgentID) async -> AgentID
    func prompt(_ id: AgentID, text: String) async throws
    func interrupt(_ id: AgentID) async throws
    func setOpenChats(_ ids: Set<AgentID>) async
    func refreshAgent(_ id: AgentID, expectingSession sessionId: String) async
    func refreshDirtyState(ofAgent id: AgentID) async
    func newAgentTab(in workspaceId: WorkspaceID) async throws -> AgentID
    var serverInfo: HerdrServerInfo? { get async }
}

public struct HerdrServerInfo: Sendable, Equatable {
    public var version: String             // do último ping
    public var protocolVersion: Int
}

public enum HerdrBridgeEvent: Sendable {
    case snapshot(tree: [WorkspaceNode], available: Bool)
    case treeChanged([WorkspaceNode])
    case agentStatus(AgentID, AgentStatus, title: String?)
    case sessionChanged(AgentID, sessionId: String?)
    case availability(Bool)
    case paneMoved(from: AgentID, to: AgentID)
}

public struct HerdrAgent: Sendable, Equatable {
    public var paneId: AgentID
    public var workspaceId: WorkspaceID
    public var kind: String                // campo `agent` do Herdr
    public var status: AgentStatus
    public var sessionId: String?          // agent_session.value
    public var cwd: String?
    public var foregroundCwd: String?
    public var terminalTitle: String?      // terminal_title_stripped
}

public enum HerdrBridgeError: Error, Sendable, Equatable {
    case unavailable
    case agentNotFound
    case agentBlocked
    case workspaceNotFound
    case herdr(code: String, message: String)
}
```

- `events()`: cada chamada cria um assinante novo. O primeiro elemento é o estado atual (`.snapshot`); depois vêm os eventos.
- O buffer de cada assinante é `.bufferingNewest(256)`. Um assinante lento não trava os outros.
- `agent(_:)` devolve o agente como o Herdr o vê: pane, workspace, tipo, status, sessão, `cwd`, `foreground_cwd` e título do terminal.
- `resolve(_:)` traduz um id antigo pelo mapa do `pane_moved` (§3.1.3). Um id sem tradução volta igual.
- `prompt` usa `agent.prompt` e `interrupt` usa `agent.send_keys` com `["Escape"]` (§3.1.2). Os dois lançam `HerdrBridgeError`.
- `setOpenChats` recebe os agentes com chat aberto em algum cliente e alimenta a reconciliação (c) da §3.1.3.
- `refreshAgent(_:expectingSession:)` é chamado no `SessionStart` do hook (§3.1.3 d): repete o `agent.get` do pane em 0; 0,5; 1,5 e 3,5 s até o Herdr informar a sessão do hook, sem aplicar a sessão do hook direto, para o estado não alternar entre as duas. Não bloqueia quem chama.
- `refreshDirtyState(ofAgent:)` é chamado no `Stop`: invalida o cache de `isDirty` do workspace do agente (§3.1.4) e reagenda a árvore.
- `newAgentTab(in:)` segue a §5.3.1 e devolve o `pane_id` do pane novo. Espera pelo `pane.agent_status_changed` do pane novo (inscrição aberta antes do `agent.start`) e pelo `agent.wait` ao mesmo tempo, com prazo de 30 s; o primeiro sinal de pronto vence, e qualquer desfecho da espera devolve o id. Antes de devolver, relê o `session.snapshot` para o agente já estar na árvore. Um nome `mocha-<n>` em uso por outra chamada em andamento fica reservado até ela terminar. `workspaceNotFound` vira `invalidPayload`.
- `serverInfo` é a versão e o protocolo do último `ping` (§3.1.1), `nil` antes do primeiro. Alimenta o `status`, o `doctor` e o `/local/status`.

**`TranscriptProviding`**: declarado em `MochaDaemonCore/Transcript/` e implementado pelo `TranscriptStore`.

```swift
public protocol TranscriptProviding: Sendable {
    func open(session: TranscriptSession, limit: Int) async throws -> TranscriptSubscription
    func page(session: TranscriptSession, before: String, limit: Int) async throws -> TranscriptPage
    func meta(forSession session: TranscriptSession) async -> TranscriptMeta?
    func stats(forSession session: TranscriptSession) async -> TranscriptStats?
}

public struct TranscriptSession: Sendable, Hashable {
    public var sessionId: String
    public var transcriptPath: String?     // do hook, quando existe (§3.2.1)
    public var subagent: SubagentTranscript?   // transcript de subagente: parser no modo subagente (§3.2.2)
}

public struct TranscriptPage: Sendable {
    public var items: [ChatItem]
    public var before: String?             // cursor (§3.2.3)
    public var hasMore: Bool
    public var meta: TranscriptMeta
}

public struct TranscriptSubscription: Sendable {
    public var page: TranscriptPage
    public var deltas: AsyncStream<TranscriptDelta>
    public func cancel()
}

public enum TranscriptDelta: Sendable {
    case append([ChatItem])
    case update([ChatItem])
    case meta(TranscriptMeta)
}

public struct TranscriptMeta: Sendable, Equatable {
    public var title: String?              // último ai-title
    public var model: String?
    public var branch: String?             // gitBranch
    public var permissionMode: String?
    public var claudeVersion: String?
    public var lastModified: Date?         // mtime do arquivo
    public var preview: MessagePreview?    // §3.2.2, meta da Home
    public var prompt: String?             // §3.2.2, último pedido do usuário
    public var activity: ToolActivity?
    public var contextTokens: Int?
    public var sessionStartedAt: Date?
    public var turnStartedAt: Date?
    public var turnEndedAt: Date?
}

public struct TranscriptStats: Sendable, Equatable {
    public var dropped: Int
    public var orphanResults: Int
    public var unknown: [String: Int]      // tipo desconhecido → linhas
    public var claudeVersion: String?
}

public enum TranscriptError: Error, Sendable, Equatable {
    case invalidCursor
}
```

- `open` é atômico: devolve a última página e um stream com os deltas a partir do fim dela, sem perder nem duplicar linhas gravadas entre a leitura e a inscrição.
- Com `subagent`, o arquivo é o `subagent.path` (não se resolve pelo `sessionId`), o parser roda no modo subagente com a fronteira de fork `subagent.forkToolUseId`, e o cursor é o do chat de subagente (§3.2.3).
- Contagem de referência por assinante: o arquivo é acompanhado enquanto houver ao menos uma inscrição viva. Cancelar uma inscrição (`cancel()` ou fim da `Task` consumidora) não afeta as outras.
- `page`: cursor inválido ou de outra sessão lança `TranscriptError.invalidCursor`.
- `meta(forSession:)` é lido do fim do arquivo, sem índice completo, com cache por tamanho e mtime. Devolve `nil` se o arquivo não existe.
- `stats(forSession:)` alimenta o `doctor` (§4.2) pelo `/local/status` (§4.8). Ele varre o arquivo inteiro, com cache por tamanho e mtime.
- O delta `.meta` sai quando qualquer campo do `TranscriptMeta` muda, menos o `lastModified` sozinho, e leva o `lastModified` do momento. O `SessionHub` manda `chatMeta` só quando muda um campo do `ChatMeta` (§4.1.2), e `treeChanged` quando muda um campo do `AgentSummary`.
- Erro de E/S no `open` vira log e sessão vazia, sem lançar.

**`UsageProviding`**: declarado em `MochaDaemonCore/Usage/` e implementado pelo `UsageMonitor` (§3.4).

```swift
public protocol UsageProviding: Sendable {
    func events() -> AsyncStream<UsageSnapshot?>   // o primeiro elemento é o estado atual
    var snapshot: UsageSnapshot? { get async }
    func contextUsedPercent(forSession sessionId: String) async -> Double?
}
```

**`SessionArchiving`**: declarado em `MochaDaemonCore/Sessions/` e implementado pelo `SessionArchive` (§4.9).

```swift
public protocol SessionArchiving: Sendable {
    func events() -> AsyncStream<[ArchivedSession]>  // o primeiro elemento é a lista atual
    var sessions: [ArchivedSession] { get async }
    func session(_ sessionId: String) async -> ArchivedSession?
    func sessionEnded(_ session: ArchivedSession) async
    func archive(sessionId: String, at date: Date) async
    func archivedAt(sessionId: String) async -> Date?
    func turnStarted(sessionId: String, at date: Date) async
    func sessionResumed(sessionId: String) async
}
```

**`SubagentProviding`**: declarado em `MochaDaemonCore/Subagents/` e implementado pelo `SubagentStore` (§3.5, fase subagentes).

```swift
public protocol SubagentProviding: Sendable {
    func events() -> AsyncStream<SubagentEvent>
    func observe(sessions: Set<String>) async
    func runningCount(session sessionId: String) async -> Int
    func subagents(session sessionId: String) async -> [SubagentSummary]
    func state(_ agentId: String) async -> SubagentState?
    func workflow(_ runId: String) async -> WorkflowState?
    func transcript(session sessionId: String, agentId: String) async -> SubagentTranscript?
}

public struct SubagentTranscript: Sendable, Hashable {
    public var agentId: String
    public var path: String                // agent-<agentId>.jsonl, com os symlinks resolvidos
    public var forkToolUseId: String?      // meta.toolUseId de um fork: a fronteira (§3.2.2)
}

public struct SubagentState: Sendable, Equatable {
    public var agentId: String
    public var sessionId: String
    public var toolUseId: String?          // meta.toolUseId
    public var parentAgentId: String?      // aninhado
    public var runId: String?              // agente de workflow
    public var agentType: String           // sem o prefixo de plugin
    public var description: String         // no agente de workflow, o label
    public var status: SubagentStatus
    public var activity: ToolActivity?
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?
    public var failureReason: String?
}

public struct WorkflowState: Sendable, Equatable {
    public var runId: String
    public var sessionId: String
    public var toolUseId: String?
    public var name: String?               // workflowName ou o name do meta do script
    public var status: WorkflowStatus
    public var phases: [WorkflowPhase]
    public var agentCount: Int
    public var toolUses: Int
    public var durationMs: Int?
}

public enum SubagentEvent: Sendable {
    case subagent(SubagentState)
    case workflow(WorkflowState)
    case runningCount(sessionId: String, count: Int)
}
```

- `events()`: cada chamada cria um assinante novo, com buffer `.bufferingNewest(256)`. Cada mudança no estado de um subagente ou de um workflow sai uma vez, e `runningCount` sai quando a contagem de uma sessão muda.
- `observe(sessions:)` recebe o conjunto de sessões observadas (§3.5.4), que o `SessionHub` atualiza a cada árvore e a cada chat aberto ou fechado. Uma sessão que sai do conjunto tem os descritores fechados, e o cache fica.
- `runningCount(session:)`: subagentes `running` da sessão, contando os de `Agent`, os aninhados e os agentes de workflow (a última tentativa de cada `key`).
- `subagents(session:)`: só os de `Agent`, inclusive os aninhados, na ordem de `listSubagents` (§5.3.1). Os agentes de workflow ficam no card do workflow.
- `state(_:)` e `workflow(_:)` devolvem `nil` para agente ou workflow fora das sessões observadas.
- `transcript(session:agentId:)` procura `~/.claude/projects/*/<sessionId>/subagents/agent-<agentId>.jsonl` e depois `~/.claude/projects/*/<sessionId>/subagents/workflows/wf_*/agent-<agentId>.jsonl`, lê o `meta.json` para a fronteira do fork e devolve `nil` sem arquivo. Vale também para sessão não observada.
- Erro de E/S vira log e estado vazio, sem lançar.

**Fakes**: `FakeHerdrBridge` (`MochaTestSupport/Herdr/`), `FakeTranscriptProvider` (`MochaTestSupport/Transcript/`), `FakeUsageProvider` (`MochaTestSupport/Usage/`), `FakeSessionArchive` (`MochaTestSupport/Sessions/`) e `FakeSubagentProvider` (`MochaTestSupport/Subagents/`) implementam os protocolos e são controlados pelo teste: emitem eventos, fixam a árvore, as páginas, o uso, as sessões e os subagentes e contam as chamadas.

#### §4.1.2 Composição

O `SessionHub` junta o `HerdrBridging`, o `TranscriptProviding` e, na fase subagentes, o `SubagentProviding` no que vai para os clientes.

- **Fronteira**: o `HerdrBridge` monta a árvore inteira com o que vem do Herdr e do git (ids, rótulos, `number`, `repoName`, `branch`, `isDirty`, tabs, agentes com `kind`, `status`, `sessionId`, `branch` e o `title` do terminal, e o `agentStatus` agregado). O `SessionHub` sobrescreve em cada `AgentSummary` com sessão: `title`, `model`, `lastActivityAt`, `preview`, `activity`, `sessionStartedAt`, `turnStartedAt` e `turnEndedAt` (do `TranscriptMeta`), `contextLeftPercent` (§3.4, primeiro o `UsageProviding`, depois o `contextTokens`) e `archivedAt` (do `SessionArchiving`).
- **Home ao vivo**: o `SessionHub` mantém uma inscrição no `TranscriptProviding` (`open`) para cada agente `working` ou `blocked`, mesmo sem chat aberto, e a solta 30 s depois de o agente sair desses estados (o `turn_duration` chega logo depois do `Stop`). Para os demais agentes, usa `meta(forSession:)` a cada `tree` recomposto.
- `AgentSummary.title`: `TranscriptMeta.title` (ai-title) quando existe; senão, o título do terminal do Herdr (`terminal_title_stripped`); senão, o `label` da tab; senão, "Claude Code". `ChatMeta.title` segue a mesma ordem. `AgentSummary.model` vem de `TranscriptMeta.model`.
- `AgentSummary.branch`: `HEAD` do `foreground_cwd` (§3.1.4). `ChatMeta.branch`: `gitBranch` do transcript (§3.2.2).
- `WorkspaceNode.agentStatus`: agregado dos agentes das tabs do próprio workspace (os worktrees filhos têm o agregado deles), com a prioridade `blocked` > `working` > `done` > `idle` > `unknown`. Workspace sem agente fica `unknown`.
- `WorkspaceNode.repoName` = `worktree.repo_name`; sem `worktree`, `nil`. `AgentSummary.lastActivityAt` = `TranscriptMeta.lastModified`. `HostInfo.hostName` = nome do Mac (`Host.current().localizedName`). `HostInfo.sshUser` = `NSUserName()` e `HostInfo.sshHostKeys` = as linhas de `/etc/ssh/ssh_host_ed25519_key.pub` e `ssh_host_ecdsa_key.pub` que existirem, só tipo e base64, sem o comentário (`SSHHostIdentity`, lido uma vez na subida do daemon); sem nenhuma, `[]`.
- `ChatMeta`: `title`, `model`, `branch` e `permissionMode` vêm do transcript; `workspaceLabel` e `status`, do Herdr.
- **Eventos para os clientes**:
  - mudança de status gera `agentStatus` na hora e `treeChanged` com debounce de 150 ms;
  - mudança de um campo do `AgentSummary` vindo do `TranscriptMeta`, do uso ou do arquivamento gera `treeChanged` com o mesmo debounce;
  - `chatMeta` sai só quando muda um campo do `ChatMeta` de um chat aberto;
  - troca de sessão gera `treeChanged`, e o chat aberto passa para o arquivo novo;
  - mudança no `UsageProviding` gera `usage`; no `SessionArchiving`, `archived`; na disponibilidade do Herdr, `herdrStatus`.
- **Chat de sessão arquivada** (`ChatTarget.session`): `ChatMeta.title`, `model`, `branch` e `permissionMode` vêm do `TranscriptMeta` da sessão; `workspaceLabel` vem da `ArchivedSession` (vazio sem registro); `status` é `unknown`.
- **Arquivamento**: a cada `turnStartedAt` novo de uma sessão, o `SessionHub` chama `SessionArchiving.turnStarted`, que apaga o `archivedAt` anterior a ele. Quando a sessão de um agente muda, a antiga vai para `sessionEnded` com `reason: cleared`; quando o agente some da árvore (pane fechado, pane que saiu, Claude encerrado), a sessão dele vai com `reason: ended`. O registro leva o último `AgentSummary` conhecido.
- **`pane_moved`**: mensagens com o id antigo são traduzidas por `resolve`. O app reaponta o chat aberto pelo `sessionId` que vem no `treeChanged` (§6.1).
- **Herdr indisponível**: o `SessionHub` continua servindo a última árvore conhecida e responde `herdrUnavailable` a `sendPrompt` e `interrupt`. `helloOk.host.herdrConnected` reflete o estado no momento do `hello`, e cada mudança depois dele sai em `herdrStatus`. Enquanto o Herdr está indisponível, nenhuma sessão vai para o arquivo por sumir da árvore.
- **Subagentes e workflows** (fase subagentes):
  - o `SessionHub` passa ao `SubagentProviding.observe(sessions:)` as sessões atuais dos agentes Claude da árvore e as dos chats abertos;
  - **cards ao vivo**: em todo `chatPage`, `chatAppend` e `chatUpdate`, um item `subagent` com `agentId` conhecido recebe `status`, `activity`, `toolUses`, `startedAt`, `durationMs` e `failureReason` do `state(agentId)`, e um item `workflow` com `runId` recebe `status`, `phases`, `agentCount`, `toolUses` e `durationMs` do `workflow(runId)` (o `startedAt` do parser fica). Sem estado no `SubagentProviding`, vale o do parser;
  - um evento do `SubagentProviding` que muda um card de chat aberto gera `chatUpdate` com o item sobreposto, no máximo 1 por card a cada 1 s; mudança de `status` sai na hora. Um agente de workflow atualiza o card do workflow dele;
  - `AgentSummary.runningSubagents` = `runningCount(session:)` da sessão atual do agente; a mudança gera `treeChanged`, com o debounce de sempre;
  - um agente com `runningSubagents > 0` é acompanhado como um `working` na Home ao vivo, mesmo `idle`: o `SessionHub` mantém a inscrição do transcript e a solta 30 s depois de a contagem zerar;
  - `listSubagents` responde com `subagents(session:)` da sessão atual do agente (§5.3.1);
  - **chat de subagente** (`ChatTarget.subagent`): o arquivo vem de `transcript(session:agentId:)` e é aberto pelo `TranscriptProviding` com `TranscriptSession.subagent`. `ChatMeta.title` é a `description` do subagente (o `label`, no agente de workflow); `model` e `branch` vêm do transcript do subagente; `workspaceLabel` é o do chat pai (do agente atual da sessão ou da `ArchivedSession`; vazio sem nenhum dos dois); `permissionMode` é `nil`; `status` é `unknown`; e `subagent` sai do `state(agentId)`, com `parentTitle` = o título do chat pai: o do chat da sessão (regra do `ChatMeta.title` acima) para um subagente de primeiro nível ou agente de workflow, e a `description` do pai para um aninhado;
  - o `chatMeta` do chat de subagente sai quando muda o `ChatMeta.subagent`, com o mesmo limite de 1 s dos cards; mudança de `status` sai na hora.

### §4.2 CLI

| Comando | Faz |
|---|---|
| `mochad run` | Roda em primeiro plano (é o que o LaunchAgent chama) |
| `mochad install` | Copia o binário para `~/.local/bin/mochad`, escreve `~/Library/LaunchAgents/com.joaoalves.mochad.plist` (`RunAtLoad`, `KeepAlive`, logs em `~/Library/Logs/Mocha/`) e roda `launchctl bootstrap gui/$UID …` |
| `mochad uninstall` | `launchctl bootout` e remove o plist. Não apaga dados |
| `mochad pair` | Pede ao daemon em execução um código de pareamento pelo canal local (§4.8) e imprime o QR no terminal (§4.5). Sem daemon, falha com "o mochad não está rodando" e mostra `mochad install` ou `scripts/run-daemon.sh` |
| `mochad devices` | Lista os aparelhos pareados lendo `devices.json`. `--remove <id>` pede ao daemon (§4.8), que fecha as conexões do aparelho e o remove; só edita o arquivo direto se o socket recusar a conexão (`ECONNREFUSED` ou socket inexistente) |
| `mochad install-hooks` / `uninstall-hooks` | §3.3 |
| `mochad serve-setup` | Mostra o comando `tailscale serve` (§4.5); `--apply` executa, confere e aquece o certificado; `--remove` desfaz |
| `mochad apns import <arquivo.p8> --key-id <KID> --team-id <TID> [--bundle-id <id>]` | Guarda a `.p8` no Keychain de login (serviço `com.joaoalves.mocha.apns`, conta = Key ID) e grava `apns{teamId, keyId, bundleId}` no config (0600) |
| `mochad apns test [--device <id>] [--token <hex> --env sandbox\|production]` | Manda um alerta de teste para o aparelho, ou para um token cru (diagnóstico). Mostra headers, payload, status, `reason`, tempo e `apns-unique-id`; nunca o token inteiro nem o JWT |
| `mochad apns liveactivity start\|update\|end --token <hex> --env …` | Diagnóstico da Live Activity (§7.5), com `--agent`, `--status working\|blocked\|idle`, `--title`, `--workspace`, `--priority`, `--stale-in` e `--dismiss-in` |
| `mochad status` | Com o daemon (§4.8): versão, tempo no ar, estado do Herdr (versão e protocolo do `ping`), clientes conectados e o Serve. Sem o daemon: "mochad parado", o `ping` direto do Herdr e o Serve, e sai com código diferente de zero. O `doctor` também sai com código diferente de zero quando algum item é ❌ |
| `mochad doctor` | Diagnóstico com ✅/⚠️/❌: socket do Herdr, `agent.list`, hooks instalados, moshi-hook, Serve, APNs, permissões do diretório de dados, Transcript e Uso (§3.4). **Transcript**: por sessão acompanhada, a versão do Claude (`version` da última linha), as linhas descartadas e os tipos desconhecidos por nome, com aviso quando a versão passa da última validada (§3.2.2, política item 3). Os dados vêm de `/local/status` (§4.8); sem daemon, o item diz que precisa do daemon |

### §4.3 Caminhos e configuração

| Caminho | Conteúdo |
|---|---|
| `~/Library/Application Support/Mocha/config.json` | `hookPort` (47420), `gatewayPort` (47421), `apns{teamId, keyId, bundleId}`, `hookSecret` |
| `~/Library/Application Support/Mocha/devices.json` | Aparelhos (§4.6). Permissão 0600 |
| `~/Library/Application Support/Mocha/sessions.json` | Sessões arquivadas e arquivamentos do usuário (§4.9). Permissão 0600 |
| `~/Library/Application Support/Mocha/mochad.sock` | Canal local (§4.8). Permissão 0600 |
| `~/Library/Application Support/Mocha/uploads/` | Imagens recebidas (0700; arquivos 0600). Apagadas depois de 7 dias, na subida do daemon e a cada 6 h |
| `~/Library/Logs/Mocha/mochad.log` | stdout/stderr do LaunchAgent |
| Keychain (login), serviço `com.joaoalves.mocha.apns`, conta = Key ID | Conteúdo da `.p8` (senha genérica). O ACL confia no binário que criou o item pelo requisito de assinatura, e a lista de partição recebe `teamid:<TEAM>` |

**`config.json`**: todo gravador lê o arquivo, altera só as próprias chaves e preserva as desconhecidas. A gravação é atômica (arquivo temporário + rename), com 0600. O `hookSecret` (32 bytes aleatórios, base64url) é gerado por `mochad install`, `mochad run` ou `mochad install-hooks` quando falta; os demais comandos nunca o geram. O daemon relê o `config.json` quando um hook chega com um segredo diferente do que ele tem em memória.

O `mochad` é assinado com a identidade "Apple Development" do time e o identificador fixo `com.joaoalves.mochad` (`codesign --force --sign <identidade> --identifier com.joaoalves.mochad --options runtime`, no `build-daemon.sh` e no `install`). Assim, qualquer build novo lê a chave sem diálogo. Um binário sem assinatura de equipe (padrão do `swift build`) abre o diálogo "Permitir sempre" do Keychain a cada recompilação, e o LaunchAgent travaria esperando um clique.

Log: `os.Logger(subsystem: "com.joaoalves.mocha", category: <componente>)`. Tokens e segredos nunca vão para o log.

### §4.4 HttpServer

- `NWListener` TCP em `127.0.0.1`: os hooks em 47420 (§3.3) e o gateway em 47421 (§4.5), com o mesmo servidor atendendo HTTP e o upgrade de WebSocket. O binding `.unixSocket(path:)` é usado pelo canal local (§4.8), não pelo gateway (S5).
- Suporta: linha de requisição, headers, corpo com `Content-Length` (limite de 1 MB; 16 MiB nas rotas `/hooks/*`, porque o `PermissionRequest` de um `Write` traz o arquivo inteiro no `tool_input`; 20 MB só em `/v1/upload`; acima disso, 413), resposta com `Content-Length`, `Connection: close`. Sem chunked, sem keep-alive, sem HTTP/2.
- Handlers são `async` e podem segurar a resposta por até 600 s (necessário para o `PermissionRequest`, §8.1). A conexão fechada pelo cliente cancela a `Task` do handler.
- **WebSocket**: o upgrade (`Sec-WebSocket-Accept` com SHA-1 + base64) e o framing RFC 6455 são implementados no próprio `HttpServer`: frames de texto e binário, fragmentação de entrada, ping/pong automático, close, e máscara obrigatória nos frames do cliente. Sem extensões (sem `permessage-deflate`). O `NWProtocolWebSocket` fica de fora porque, no stack do listener, ele não atende HTTP comum na mesma porta.
- Resposta a método desconhecido ou path inválido: 404/405 com corpo vazio.
- **Bindings**: `.loopback(port:)` (127.0.0.1) e `.unixSocket(path:)`. O `NWListener` escuta em `NWEndpoint.unix(path:)` (confirmado no WP0.3): o servidor remove um socket antigo antes do bind (só se o caminho for socket), aplica 0600 depois do `.ready` e apaga o arquivo no `stop`.
- **Respostas do próprio servidor**: `Transfer-Encoding` (chunked ou outro) → 411; requisição malformada (linha ou header inválido, `Content-Length` inválido ou conflitante) → 400; versão diferente de 1.0/1.1 → 505; cabeçalho acima de 32 KiB → 431; cabeçalho incompleto em 30 s → fecha sem resposta; 405 leva `Allow`; erro lançado pelo handler → 500 vazio. 204, 304 e 1xx saem sem `Content-Length` (RFC 9110). O handler não sobrescreve `Content-Length`, `Connection` nem `Transfer-Encoding`. `Expect: 100-continue` não é tratado.
- **Resposta antecipada** (413, 404 ou 405 com corpo pendente): o servidor drena o corpo até `min(Content-Length, 32 MiB)` ou EOF, com limite de 10 s, antes de fechar, para o cliente receber a resposta em vez de um reset.
- **Tempo do handler**: o servidor não impõe timeout; o limite (ex.: 580 s do `PermissionRequest`, §8.3) é de quem chama. O cliente que fecha ou meio-fecha (shutdown de escrita) a conexão cancela a `Task` do handler.
- **WebSocket**: limite de mensagem de 1 MiB por padrão, configurável por rota; close com eco do código e espera de até 5 s pelo close do cliente; o servidor não manda ping periódico.

### §4.5 Exposição, pareamento e autenticação

- **Exposição**: `tailscale serve --bg --https=443 http://127.0.0.1:47421`. O gateway escuta só em TCP `127.0.0.1:47421`, e o iPhone acessa `wss://mac-mini.tail1234.ts.net/v1`. O socket Unix foi descartado no S5: a extensão de sistema do Tailscale standalone roda em sandbox e recebe `connect: operation not permitted` ao abrir um socket em `~/Library/Application Support/Mocha/` (o cliente vê 502).
  - **Desfazer**: `tailscale serve --https=443 off` remove só esse handler. `tailscale serve reset` apaga toda a config de Serve do Mac e só serve se não houver outra.
  - **Conferir**: `tailscale serve status --json` tem, em `Web["<host>:443"].Handlers["/"]`, `"Proxy": "http://127.0.0.1:47421"`.
  - **Certificado**: o primeiro HTTPS do nó emite o certificado Let's Encrypt e segura o TLS por até ~1 min. Depois disso, o Tailscale renova sozinho (validade de 90 dias). O `serve-setup --apply` aquece com `GET https://<host>/v1/health` e limite de 90 s.
  - **CLI**: o `mochad` chama `/Applications/Tailscale.app/Contents/MacOS/tailscale` pelo caminho absoluto (o `/usr/local/bin/tailscale` é um wrapper), com `TAILSCALE_BE_CLI=1` no ambiente (sob o launchd não há `TERM`, e sem a variável o binário do app abre em modo GUI e trava), e lê o host em `tailscale status --json` (`.Self.DNSName`, sem o ponto final).
  - **O que o proxy faz**:
    - repassa `Authorization`, a query string intacta e o corpo com `Content-Length`;
    - fala HTTP/1.1 com o daemon, mesmo com o cliente em h2;
    - acrescenta `X-Forwarded-For` (IP do tailnet do aparelho), `X-Forwarded-Host`, `X-Forwarded-Proto`, `Tailscale-User-Login`, `Tailscale-User-Name`, `Tailscale-User-Profile-Pic`, `Tailscale-Headers-Info` e `Accept-Encoding: gzip`;
    - repassa o upgrade de WebSocket, o ping/pong e o close com código e motivo, e não derruba conexão ociosa (testado até ~190 s);
    - transforma corpo sem tamanho conhecido em chunked, que o daemon recusa com 411 (§4.4);
    - responde 502 quando o gateway não está escutando.
- **Pareamento**:
  1. `mochad pair` pede ao daemon um código de pareamento (§4.8). O daemon gera o código (32 bytes aleatórios, base64url) e o guarda em memória, de uso único, por 10 min. O `Pairing` emite o código e a URL; a CLI renderiza o QR (CoreImage `CIQRCodeGenerator` com meio-blocos Unicode).
     - O link é `mocha://pair?url=<URL do WS, percent-encoded>&code=<código>`, montado e lido pelo tipo `PairingLink` de `MochaProtocol` (o mesmo no daemon e no app).
     - O QR sai com cores ANSI explícitas (módulos pretos em fundo branco) e margem de 4 módulos, para ser lido também em terminal escuro.
  2. O app lê o QR (câmera, `DataScannerViewController`) ou recebe o link colado.
  3. Ele conecta e envia `hello{pairingCode}`.
  4. O daemon troca o código por um **token de aparelho** (32 bytes aleatórios), devolvido uma única vez em `helloOk.deviceToken`.
  5. O app guarda o token no Keychain (`kSecAttrAccessibleAfterFirstUnlock`, necessário para ações de notificação em background).
- **Autenticação**: toda conexão WS envia `hello{deviceToken}` como **primeira mensagem**. A URL do WS nunca carrega token, porque a URL entra em logs e históricos (o Serve repassa a query intacta). Requisições HTTP do app levam `Authorization: Bearer <deviceToken>`. O daemon guarda só o SHA-256 do token e compara em tempo constante. Três falhas seguidas numa conexão encerram a conexão, e um `hello` recusado conta nessas três (§5.3.1).

### §4.6 DeviceStore

`devices.json`:

```json
[{
  "id": "UUID",
  "name": "iPhone do João",
  "tokenSha256": "hex",
  "createdAt": "ISO-8601",
  "lastSeenAt": "ISO-8601",
  "apns": {"token": "hex", "env": "sandbox|production"},
  "preferences": {"turnDoneAlerts": true},
  "liveActivity": {"pushToStartToken": "hex", "activityId": "…", "updateToken": "hex", "env": "sandbox|production"}
}]
```

- `hello` com `apns` grava o token e o `env` do aparelho; `hello` sem `apns` mantém o que já está gravado.

### §4.7 Metas de desempenho do daemon

- Parado (sem cliente e sem agente trabalhando): CPU ~0 %, RSS < 30 MB.
- Latência de evento do Herdr até `agentStatus` no app, na mesma rede: < 250 ms.
- Latência de linha nova no JSONL até `chatAppend`: < 300 ms.
- Nenhum polling abaixo de 2 s. Tudo é orientado a eventos (socket do Herdr e DispatchSource).
- Referência medida (S2): o Herdr entrega `pane.agent_status_changed` 30–100 ms depois da mudança de estado, e o `working` chega 0,5–0,7 s depois do envio do prompt (o `agent.prompt` leva ~300 ms).

### §4.8 Canal local (CLI → daemon)

- HTTP/1.1 do próprio `HttpServer` (§4.4) no socket Unix `~/Library/Application Support/Mocha/mochad.sock` (0600), sem token nem segredo: o acesso é controlado pela permissão do arquivo. Não passa pelo Serve.
- O cliente da CLI fala HTTP sobre `NWConnection` com `NWEndpoint.unix(path:)`, porque o `URLSession` não abre socket Unix. Timeout de 5 s.
- O `DeviceStore` relê `devices.json` antes de cada gravação.

| Rota | Resposta |
|---|---|
| `POST /local/pairing-code` | `{"code","url","expiresAt"}` (§4.5) |
| `GET /local/status` | JSON com `version`, `startedAt`, `herdr{available, version?, protocol?}`, `clients[{deviceId, name, connectedAt}]` e `sessions[{sessionId, agentId, claudeVersion?, dropped, orphanResults, unknown}]`, e `apns{configurationErrors[{environment, status, reason, at}]}` com a última recusa de configuração do APNs por ambiente (§7.1), que o `doctor` mostra no item APNs |
| `DELETE /local/devices/<id>` | 200 com `{}` depois de fechar as conexões do aparelho (`error{unauthorized}` e close 1008) e removê-lo de `devices.json`; 404 se o aparelho não existe |

### §4.9 SessionArchive

- **`sessions.json`**: `{"sessions": [ArchivedSession], "userArchived": {"<sessionId>": "<ISO-8601>"}}`, com o JSON de §5.2.1, gravação atômica e 0600, relido antes de cada gravação.
- **Entradas**: `sessionEnded` (do `SessionHub`, §4.1.2) grava ou substitui a `ArchivedSession` pelo `sessionId`, com `endedAt` = agora. Uma sessão que volta a ser a sessão atual de algum agente (`claude --resume`) sai da lista.
- **Retenção**: só sessões com `lastActivityAt` (ou `endedAt`) nos últimos 7 dias, no máximo 50, as mais recentes primeiro. A limpeza roda ao iniciar e a cada gravação.
- **Arquivamento pelo usuário**: `archive{sessionId}` grava `userArchived[sessionId]` = agora. `archivedAt(sessionId:)` o devolve até um `turnStarted` posterior, que o apaga. O `SessionHub` só aceita `archive` para a sessão atual de um agente da árvore (§5.3.1).
- Cada mudança na lista sai em `events()`, e o `SessionHub` a manda como `archived` para todos os clientes.

---

## §5 Protocolo v1 (`MochaProtocol`)

### §5.1 Envelope

Mensagens WebSocket de texto, JSON UTF-8. Datas em ISO-8601 com milissegundos. Chaves em camelCase.

```json
{"v": 1, "id": "c-42", "type": "sendPrompt", "payload": { … }}
```

- `v`: versão do protocolo. Um cliente com `v` diferente recebe `error{code:"protocolMismatch"}` e é desconectado.
- `id`: obrigatório em toda mensagem do cliente, gerado pelo cliente e único por conexão. O app usa `c-<n>`; o `hello` que a própria conexão manda (§6.1) usa `hello-<n>`. Toda **resposta direta** repete o `id` da requisição: `helloOk`, `tree` (a primeira, logo após `helloOk`, repete o `id` do `hello`), `chatPage`, `subagentList`, `webServers`, `ack`, `pong` e `error`. **Eventos** do servidor (`treeChanged`, `archived`, `usage`, `herdrStatus`, `agentStatus`, `chatAppend`, `chatUpdate`, `chatMeta`, `pending`) não têm `id`.
- Tipo desconhecido vindo do cliente: o daemon responde `error{code:"unknownType"}` e segue. Tipo desconhecido vindo do servidor: o app ignora a mensagem.
- `payload` ausente equivale a `{}`.

### §5.2 Tipos de domínio

Esboço normativo. Nomes e campos valem como estão; a implementação pode adicionar conformidades e inicializadores.

```swift
public typealias AgentID = String          // pane_id do Herdr
public typealias WorkspaceID = String
public typealias TabID = String

public typealias DeviceID = String        // UUID em texto
public typealias RequestID = String       // UUID em texto

public enum AgentStatus: String, Codable, Sendable { case idle, working, blocked, done, unknown }

public enum ApnsEnvironment: String, Codable, Sendable { case sandbox, production }

public struct ApnsRegistration: Codable, Sendable {
    public var token: String               // hex
    public var env: ApnsEnvironment
}

public struct DevicePreferences: Codable, Sendable {
    public var turnDoneAlerts: Bool        // padrão true
}

public struct HostInfo: Codable, Sendable {
    public var hostName: String
    public var daemonVersion: String
    public var herdrConnected: Bool
    public var sshUser: String?           // preview-web: NSUserName() do daemon
    public var sshHostKeys: [String]?     // preview-web: "<tipo> <base64>" de /etc/ssh/ssh_host_{ed25519,ecdsa}_key.pub
}

public struct WorkspaceNode: Codable, Sendable, Identifiable {
    public var id: WorkspaceID
    public var label: String
    public var number: Int
    public var repoName: String?
    public var branch: String?
    public var isDirty: Bool
    public var agentStatus: AgentStatus
    public var tabs: [TabNode]
    public var children: [WorkspaceNode]   // worktrees ligados (§3.1.4)
}

public struct TabNode: Codable, Sendable, Identifiable {
    public var id: TabID
    public var title: String
    public var agents: [AgentSummary]      // vazio = shell; mais de um = panes divididos
}

public struct AgentSummary: Codable, Sendable, Identifiable {
    public var id: AgentID
    public var kind: String                // "claude"; outros valores não abrem chat (§3.1.4)
    public var status: AgentStatus
    public var title: String               // ai-title ou título do terminal
    public var workspaceLabel: String
    public var model: String?              // ex.: "claude-opus-5-5"
    public var branch: String?
    public var sessionId: String?
    public var lastActivityAt: Date?
    public var pendingCount: Int           // 1b; 0 na 1a
    public var preview: MessagePreview?    // última mensagem (§3.2.2); nil = sessão sem mensagem
    public var activity: ToolActivity?     // última ferramenta
    public var contextLeftPercent: Int?    // 0–100 (§3.4)
    public var sessionStartedAt: Date?
    public var turnStartedAt: Date?
    public var turnEndedAt: Date?
    public var archivedAt: Date?           // arquivado pelo usuário e sem turno novo depois (§4.9)
    public var runningSubagents: Int?      // subagentes running da sessão atual (§3.5); nil ou 0 esconde o selo
    public var permissionMode: String?     // última linha `permission-mode` do transcript (`default`, `auto`, `acceptEdits`, `plan`, `bypassPermissions`); só muda no transcript quando o próximo prompt sai
}

public enum MessageAuthor: String, Codable, Sendable { case user, assistant }

public struct MessagePreview: Codable, Sendable {
    public var author: MessageAuthor
    public var text: String                // texto plano, uma linha, até 200 caracteres
}

public struct ToolActivity: Codable, Sendable {
    public var toolName: String            // nome da ferramenta no transcript ("Bash", "Read", …)
    public var summary: String             // mesma regra de ToolCall.summary
    public var status: ToolStatus
}

public enum ArchiveReason: String, Codable, Sendable { case cleared, ended, unknown }   // valor desconhecido → unknown

public struct ArchivedSession: Codable, Sendable, Identifiable {
    public var id: String                  // sessionId
    public var agentId: AgentID?           // pane onde a sessão rodou (pode não existir mais)
    public var title: String
    public var workspaceLabel: String
    public var model: String?
    public var branch: String?
    public var preview: MessagePreview?
    public var contextLeftPercent: Int?
    public var reason: ArchiveReason
    public var endedAt: Date
    public var sessionStartedAt: Date?
    public var lastActivityAt: Date?
}

public enum UsageWindowKind: String, Codable, Sendable { case fiveHour, weekly, unknown }   // valor desconhecido → unknown

public struct UsageWindow: Codable, Sendable {
    public var kind: UsageWindowKind
    public var usedPercent: Double
    public var resetsAt: Date?
}

public struct UsageSnapshot: Codable, Sendable {
    public var plan: String?               // "Max 20x" (§3.4)
    public var account: String?            // e-mail mascarado
    public var windows: [UsageWindow]      // lista tolerante
    public var fetchedAt: Date
}

public enum ChatTarget: Sendable, Hashable {
    case agent(AgentID)                    // chat vivo
    case session(String)                   // sessionId de uma sessão arquivada: só leitura
    case subagent(sessionId: String, agentId: String)   // transcript de subagente (inclusive de workflow): só leitura
}

public enum ToolStatus: String, Codable, Sendable { case running, succeeded, failed }

public struct ToolCall: Codable, Sendable {
    public var toolUseId: String
    public var name: String                // "Bash", "Read", "Edit", "Agent", …
    public var summary: String             // linha curta: comando, caminho ou descrição
    public var inputJSON: String           // input bruto, truncado em 4.000 caracteres
    public var status: ToolStatus
    public var resultPreview: String?      // truncado em 2.000 caracteres
}

public enum SubagentStatus: String, Codable, Sendable { case running, completed, failed, stopped }
public enum WorkflowStatus: String, Codable, Sendable { case running, completed, failed, stopped }
public enum WorkflowPhaseStatus: String, Codable, Sendable { case pending, running, completed, failed }

public struct SubagentCall: Codable, Sendable {
    public var toolUseId: String
    public var agentId: String?            // do tool_result; nil até o lançamento
    public var agentType: String           // sem o prefixo de plugin (§3.5.1)
    public var description: String
    public var status: SubagentStatus
    public var activity: ToolActivity?     // ferramenta atual, só em running
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?            // só no fim
    public var failureReason: String?      // só em failed; texto original, em inglês
}

public struct WorkflowCall: Codable, Sendable {
    public var toolUseId: String
    public var runId: String?              // do tool_result
    public var name: String
    public var status: WorkflowStatus
    public var phases: [WorkflowPhase]
    public var agentCount: Int
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?            // só no fim
}

public struct WorkflowPhase: Codable, Sendable {
    public var title: String
    public var detail: String?
    public var status: WorkflowPhaseStatus
    public var agents: [WorkflowAgent]
}

public struct WorkflowAgent: Codable, Sendable {
    public var agentId: String
    public var label: String
    public var status: SubagentStatus
    public var activity: ToolActivity?     // ferramenta atual, só em running
    public var durationMs: Int?            // só no fim
}

public enum ChatItemKind: Codable, Sendable {
    case userPrompt(text: String, imageCount: Int)
    case slashCommand(name: String, args: String, output: String?)   // name: "/x" ou "!" (comando de shell do terminal)
    case assistantText(markdown: String)
    case thinking(text: String?)
    case toolCall(ToolCall)
    case subagent(SubagentCall)            // chamada de Agent (§3.2.2)
    case workflow(WorkflowCall)            // chamada de Workflow (§3.2.2)
    case task(text: String)                // tarefa no topo do transcript de subagente
    case turnFooter(durationMs: Int)
    case recap(text: String)
    case notice(text: String)
    case unsupported(type: String)         // tipo desconhecido na decodificação; o app não exibe
}

public struct ChatItem: Codable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    public var kind: ChatItemKind
}

public struct ChatMeta: Codable, Sendable {
    public var title: String
    public var workspaceLabel: String
    public var model: String?
    public var branch: String?
    public var status: AgentStatus
    public var permissionMode: String?
    public var subagent: SubagentChatInfo? // só no chat de subagente
}

public struct SubagentChatInfo: Codable, Sendable {
    public var parentTitle: String         // título do chat pai
    public var agentType: String
    public var status: SubagentStatus
    public var startedAt: Date?
    public var durationMs: Int?
    public var toolUses: Int
    public var failureReason: String?
}

public struct SubagentSummary: Codable, Sendable {                      // item de subagentList
    public var agentId: String
    public var parentAgentId: String?      // aninhado: o app recua a linha
    public var agentType: String
    public var description: String
    public var status: SubagentStatus
    public var toolUses: Int
    public var startedAt: Date?
    public var durationMs: Int?
}

public enum PendingKind: Codable, Sendable {                            // 1b
    case permission(toolName: String, summary: String, inputJSON: String)
    case question(questions: [PendingQuestion])
}

public struct PendingQuestion: Codable, Sendable {                      // 1b
    public var header: String
    public var question: String
    public var options: [PendingOption]
    public var multiSelect: Bool
}

public struct PendingOption: Codable, Sendable { public var label: String; public var description: String? }

public struct PendingRequest: Codable, Sendable, Identifiable {         // 1b
    public var id: RequestID
    public var agentId: AgentID
    public var createdAt: Date
    public var kind: PendingKind
}

public enum PendingResponse: Codable, Sendable {                        // 1b
    case allow
    case deny(reason: String?)
    case answers([String: [String]])      // pergunta → rótulos escolhidos (≥ 1 por pergunta); texto livre vira rótulo único
}
```

#### §5.2.1 Codificação JSON

Enums com valor associado **não** usam a codificação sintetizada do Swift (`{"toolCall":{"_0":{…}}}`). A regra:

- O caso vira o campo `"type"` e os valores associados viram campos irmãos, com os nomes dos rótulos.
- Em structs que carregam um enum desses (`ChatItem.kind`, `PendingRequest.kind`), os campos do enum são **achatados** no objeto do struct.
- Um struct associado (`toolCall(ToolCall)`, `subagent(SubagentCall)`, `workflow(WorkflowCall)`) também tem os campos achatados. Os campos dele que são structs ou listas (`activity`, `phases`, `agents`) ficam como objetos e listas comuns.
- Opcionais `nil` são omitidos. Datas em ISO-8601 com milissegundos (`2026-09-25T15:44:34.551Z`).
- O `Codable` é implementado à mão, com testes de ida e volta contra as fixtures de `MochaKit/Fixtures/protocol/`.
- Um `type` desconhecido em `ChatItem` decodifica como `unsupported(type:)`; nos demais enums, como erro de decodificação só daquele item.
- `AgentStatus` com valor desconhecido decodifica como `.unknown`.
- Listas tolerantes: `items` de `chatPage`, `chatAppend`, `chatUpdate` e `subagentList`, e `requests` de `pending`, descartam o item que não decodifica e mantêm os outros. As demais listas são estritas (inclusive `phases` e `agents` de um `workflow`).
- Os códigos de `error` formam um conjunto aberto (`ProtocolErrorCode`): um código desconhecido é preservado.
- **`ChatTarget`** é achatado no payload que o carrega: `.agent(id)` vira `"agentId": id`, `.session(id)` vira `"sessionId": id`, e `.subagent(sessionId, agentId)` vira `"sessionId": sessionId, "subagentId": agentId`. Na decodificação, exatamente um entre `agentId` e `sessionId` precisa existir, e `subagentId` só vale junto com `sessionId`; os dois, nenhum, ou `subagentId` sem `sessionId` é erro de decodificação.
- `ArchiveReason` e `UsageWindowKind` com valor desconhecido decodificam como `.unknown`. `AgentSummary.preview` e `AgentSummary.activity` inválidos (autor ou status desconhecido) decodificam como `nil`, sem derrubar a árvore. `windows` de `usage` e `sessions` de `archived` são listas tolerantes.
- `SubagentStatus`, `WorkflowStatus` e `WorkflowPhaseStatus` com valor desconhecido são erro de decodificação do item que os carrega (o item sai da lista tolerante). `ChatMeta.subagent` inválido decodifica como `nil`.
- Os campos e casos da fase subagentes são aditivos e o `v` continua 1: um app antigo recebe `subagent`, `workflow` e `task` como `unsupported`, e ignora `runningSubagents`, `ChatMeta.subagent` e a mensagem `subagentList`. O contrário não é suportado: o app da fase exige o `mochad` da mesma fase, e os dois sobem juntos.

Exemplos canônicos (as fixtures do WP0.2 seguem exatamente estes formatos):

```json
{"id":"8f1c…","at":"2026-09-25T15:44:34.551Z","type":"userPrompt","text":"roda os testes","imageCount":0}
{"id":"9a2d…","at":"2026-09-25T15:44:40.120Z","type":"assistantText","markdown":"Rodando `scripts/test.sh`…"}
{"id":"b7e0…","at":"2026-09-25T15:44:41.000Z","type":"toolCall","toolUseId":"toolu_01H3…","name":"Bash","summary":"scripts/test.sh","inputJSON":"{\"command\":\"scripts/test.sh\"}","status":"succeeded","resultPreview":"All tests passed"}
{"id":"c1f4…","at":"2026-09-25T15:45:10.000Z","type":"turnFooter","durationMs":45000}
{"id":"d2a9…","at":"2026-09-25T15:45:11.000Z","type":"slashCommand","name":"/clear","args":""}
{"id":"e4b1…","at":"2026-09-26T13:52:10.000Z","type":"subagent","toolUseId":"toolu_01AG…","agentId":"a0123456789abcdef","agentType":"general-purpose","description":"Teste de carga /receitas","status":"running","activity":{"toolName":"Bash","summary":"k6 run --vus 50 --duration 2m load/list-recipes.js","status":"running"},"toolUses":9,"startedAt":"2026-09-26T13:52:11.000Z"}
{"id":"f5c2…","at":"2026-09-26T13:50:02.000Z","type":"subagent","toolUseId":"toolu_01PL…","agentId":"a89abcdef01234567","agentType":"Plan","description":"Revisar o índice de receitas","status":"failed","toolUses":3,"startedAt":"2026-09-26T13:50:03.000Z","durationMs":48000,"failureReason":"Agent terminated early due to an API error: …"}
{"id":"0a7d…","at":"2026-09-26T14:10:00.000Z","type":"workflow","toolUseId":"toolu_01WF…","runId":"wf_0a1b2c3d-4e5","name":"auditoria-a11y","status":"running","phases":[{"title":"Mapear telas","status":"completed","agents":[{"agentId":"a1111111111111111","label":"Mapear","status":"completed","durationMs":95000}]},{"title":"Corrigir por tela","detail":"uma tela por agente, com testes de UI","status":"running","agents":[{"agentId":"a2222222222222222","label":"Ajustes","status":"running","activity":{"toolName":"Edit","summary":"SettingsView.swift","status":"running"}}]},{"title":"Revisar","status":"pending","agents":[]}],"agentCount":5,"toolUses":86,"startedAt":"2026-09-26T14:10:00.000Z"}
{"id":"1b8e…","at":"2026-09-26T13:52:11.000Z","type":"task","text":"Rode o teste de carga de GET /receitas com o k6 (load/list-recipes.js)…"}
```

```json
{"id":"5e3b…","agentId":"w17:p1","createdAt":"2026-09-25T15:50:00.000Z","type":"permission","toolName":"Bash","summary":"rm -rf build","inputJSON":"{\"command\":\"rm -rf build\"}"}
{"id":"6f4c…","agentId":"w17:p1","createdAt":"2026-09-25T15:51:00.000Z","type":"question","questions":[{"header":"Formato","question":"Qual formato?","multiSelect":false,"options":[{"label":"JSON","description":"…"},{"label":"YAML"}]}]}
```

```json
{"type":"allow"}
{"type":"deny","reason":"não apaga isso"}
{"type":"answers","answers":{"Qual formato?":["JSON"]}}
```

Envelope completo:

```json
{"v":1,"id":"c-7","type":"openChat","payload":{"agentId":"w17:p1","limit":60}}
{"v":1,"id":"c-7","type":"chatPage","payload":{"agentId":"w17:p1","meta":{"title":"herdr-sidebar abre arquivos em nova tab","workspaceLabel":"Core","model":"claude-opus-5-5","branch":"development","status":"idle"},"items":[…],"before":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64:120394","hasMore":true}}
{"v":1,"type":"agentStatus","payload":{"agentId":"w17:p1","status":"working"}}
{"v":1,"id":"c-9","type":"ack","payload":{}}
{"v":1,"id":"c-9","type":"error","payload":{"code":"agentBlocked","message":"O agente está esperando uma resposta no terminal."}}
{"v":1,"id":"c-11","type":"openChat","payload":{"sessionId":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64","limit":60}}
{"v":1,"id":"c-12","type":"openChat","payload":{"sessionId":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64","subagentId":"a0123456789abcdef","limit":60}}
{"v":1,"type":"chatMeta","payload":{"sessionId":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64","subagentId":"a0123456789abcdef","meta":{"title":"Teste de carga /receitas","workspaceLabel":"receitas-api","model":"claude-opus-5-5","branch":"development","status":"unknown","subagent":{"parentTitle":"Paginação com cursor em /receitas","agentType":"general-purpose","status":"completed","startedAt":"2026-09-26T13:52:11.000Z","durationMs":231000,"toolUses":12}}}}
{"v":1,"id":"c-13","type":"listSubagents","payload":{"agentId":"w17:p1"}}
{"v":1,"id":"c-13","type":"subagentList","payload":{"agentId":"w17:p1","items":[{"agentId":"a0123456789abcdef","agentType":"general-purpose","description":"Teste de carga /receitas","status":"running","toolUses":9,"startedAt":"2026-09-26T13:52:11.000Z"},{"agentId":"a76543210fedcba98","parentAgentId":"a0123456789abcdef","agentType":"Explore","description":"Achar o script de carga","status":"completed","toolUses":5,"startedAt":"2026-09-26T13:52:20.000Z","durationMs":41000}]}}
{"v":1,"type":"usage","payload":{"plan":"Max 20x","account":"d•••@e•••.com","windows":[{"kind":"fiveHour","usedPercent":12,"resetsAt":"2026-09-26T07:00:00.000Z"},{"kind":"weekly","usedPercent":71,"resetsAt":"2026-09-28T14:00:00.000Z"}],"fetchedAt":"2026-09-26T03:21:03.000Z"}}
```

### §5.3 Mensagens

Todas as requisições do cliente podem receber `error` em vez da resposta indicada.

Tipos Swift em `MochaProtocol`: `ClientMessage` e `ServerMessage` (com `.unknown(type:)`), `ChatTarget`, os envelopes `ClientEnvelope` e `ServerEnvelope`, `EnvelopeHeader` (lê `v`, `id` e `type` sem falhar, para o daemon responder `protocolMismatch` ou `invalidPayload` com o `id` certo; o `ClientEnvelope` não valida `v`), os payloads `HelloPayload`, `HelloOkPayload`, `ChatPage`, `LiveActivityRegistration` e `WebServer`, e `ProtocolDate` (formato e parse das datas, reutilizado pelo daemon). A regra "exatamente um entre `deviceToken` e `pairingCode`" é validada pelo daemon, não na decodificação. Fixtures em `MochaKit/Fixtures/protocol/`: `client.<type>[.<variante>].json`, `server.<type>[.<variante>].json`, `chatItem.<kind>[.<variante>].json`, `pendingRequest.<kind>.json` e `pendingResponse.<type>[.<variante>].json`. As variantes `.session` usam `ChatTarget.session`, e as `.subagent`, `ChatTarget.subagent`. Na fase subagentes entram `chatItem.subagent.running.json`, `chatItem.subagent.completed.json`, `chatItem.subagent.failed.json`, `chatItem.subagent.stopped.json`, `chatItem.workflow.json`, `chatItem.task.json`, `client.listSubagents.json`, `server.subagentList.json`, `server.tree.subagents.json` (com `runningSubagents`) e as variantes `.subagent` de `openChat`, `closeChat`, `chatPage`, `chatUpdate` e `chatMeta`. Na fase preview-web entram `client.listWebServers.json`, `server.webServers.json` e `server.helloOk.ssh.json` (com `sshUser` e `sshHostKeys`).

**Cliente → servidor**

| `type` | payload | Resposta | Fase |
|---|---|---|---|
| `hello` | `{deviceToken?: String, pairingCode?: String, deviceName: String, appVersion: String, apns?: ApnsRegistration}` (exatamente um entre `deviceToken` e `pairingCode`) | `helloOk` e depois `tree` | 1a-core (`apns` 1a-final) |
| `openChat` | `{<ChatTarget>, before?: String, limit?: Int}` (`agentId`, `sessionId`, ou `sessionId` com `subagentId`; `limit` padrão 60, máximo 200) | `chatPage` | 1a-core (`subagentId`: subagentes) |
| `closeChat` | `{<ChatTarget>}` | `ack{}` | 1a-core (`subagentId`: subagentes) |
| `listSubagents` | `{agentId}` | `subagentList` | subagentes |
| `sendPrompt` | `{agentId, text}` | `ack{}` | 1a-core |
| `interrupt` | `{agentId}` | `ack{}` | 1a-core |
| `setForeground` | `{agentId?: String, isActive: Bool}` | `ack{}` | 1a-core |
| `unpair` | `{}` | `ack{}` e o daemon fecha a conexão e apaga o aparelho | 1a-core |
| `ping` | `{}` | `pong{}` | 1a-core |
| `archive` | `{sessionId}` (sessão atual de um agente) | `ack{}` e `treeChanged` | 1a-core |
| `slash` | `{agentId, command: String}` (ex.: `"/compact"`) | `ack{}` | 1a-final |
| `setPreferences` | `DevicePreferences` | `ack{}` | 1a-final |
| `respond` | `{requestId, response: PendingResponse}` | `ack{}` | 1b |
| `newAgentTab` | `{workspaceId}` | `ack{agentId}` (§5.3.1) | 1a-final |
| `registerLiveActivity` | `{pushToStartToken?: String, activityId?: String, updateToken?: String, env: ApnsEnvironment}` | `ack{}`. O app acordado em background sem WebSocket manda o mesmo corpo por `POST /v1/live-activity` (§5.5) | 1b |
| `listWebServers` | `{}` | `webServers` (§9.3) | preview-web |

**Servidor → cliente**

| `type` | payload | Quando |
|---|---|---|
| `helloOk` | `{host: HostInfo, deviceId: DeviceID, deviceToken?: String, preferences: DevicePreferences}` (`deviceToken` só no pareamento) | Resposta a `hello` válido |
| `tree` | `{workspaces: [WorkspaceNode]}` | Logo depois de `helloOk`, com o mesmo `id` |
| `archived` | `{sessions: [ArchivedSession]}` (lista inteira, mais recentes primeiro) | Logo depois de `tree`, sem `id`; e a cada mudança (§4.9) |
| `usage` | `UsageSnapshot` | Depois de `archived`, sem `id`, quando o cache existe; e a cada mudança do cache (§3.4) |
| `herdrStatus` | `{connected: Bool}` | Evento: o Herdr ficou disponível ou indisponível depois do `hello` |
| `treeChanged` | `{workspaces: [WorkspaceNode]}` (árvore inteira; é pequena) | Evento: mudança de árvore (debounce de 150 ms) |
| `agentStatus` | `{agentId, status: AgentStatus, title?: String}` | Evento: mudança de status |
| `chatPage` | `{<ChatTarget>, meta: ChatMeta, items: [ChatItem], before: String?, hasMore: Bool}` | Resposta a `openChat` |
| `subagentList` | `{agentId, items: [SubagentSummary]}` (lista tolerante, na ordem da §5.3.1) | Resposta a `listSubagents` |
| `webServers` | `{host: String, servers: [WebServer]}` (`host` é o `hostName` do daemon; `WebServer` = `{pid: Int, process: String, port: Int, title?: String, directory?: String, workspaceId?: WorkspaceID}`; lista tolerante, por porta crescente) | Resposta a `listWebServers` (§9.3) |
| `chatAppend` | `{<ChatTarget>, items: [ChatItem]}` | Evento: itens novos num chat aberto |
| `chatUpdate` | `{<ChatTarget>, items: [ChatItem]}` (substitui por `id`) | Evento: um item já enviado mudou (ex.: `tool_result` chegou) |
| `chatMeta` | `{<ChatTarget>, meta: ChatMeta}` | Evento: título, modelo, branch, status ou modo mudou |
| `pending` | `{requests: [PendingRequest]}` (lista completa) | 1b. Evento: mudança na lista (também enviado logo depois de `tree`) |
| `ack` | `{}`, ou `{agentId}` para `newAgentTab` | Resposta simples |
| `pong` | `{}` | Resposta a `ping` |
| `error` | `{code, message}` | Resposta a uma requisição. Códigos: `unauthorized`, `pairingExpired`, `protocolMismatch`, `unknownType`, `invalidPayload`, `agentNotFound`, `sessionNotFound`, `agentBlocked`, `requestNotFound`, `herdrUnavailable`, `internal` |

#### §5.3.1 Regras do servidor

- **`hello`**:
  - a checagem de `v` vem antes de tudo: `v` diferente de 1 recebe `protocolMismatch`, mesmo na primeira mensagem;
  - a primeira mensagem precisa ser `hello`; outra coisa recebe `error{unauthorized}` e close 1008;
  - `hello` repetido na mesma conexão recebe `invalidPayload`;
  - `hello` recusado (token errado, código inválido ou vencido) conta nas três falhas da §4.5, e a terceira fecha com 1008. Código vencido, já usado ou nunca emitido → `pairingExpired`.
- **Fim da conexão**:
  - `protocolMismatch` → `error` e close 1002;
  - `unpair` → `ack`, close 1000, e o aparelho sai de `devices.json`;
  - aparelho removido pela CLI (§4.8) → `error{unauthorized}` e close 1008.
- **`openChat`**:
  - `limit` ausente = 60; fora de 1…200, é cortado para o intervalo;
  - cursor inválido ou de outra sessão → `invalidPayload`;
  - agente com `kind != "claude"` → `invalidPayload` ("Chat disponível só para Claude Code");
  - agente sem sessão → `chatPage` com `items: []`, `before: nil` e `hasMore: false`, e o chat passa a ser acompanhado (o arquivo pode nascer depois, §3.2.1);
  - agente desconhecido, depois de `resolve` (§4.1.1) → `agentNotFound`;
  - com um id antigo traduzido por `resolve`, o `chatPage` volta com o `agentId` atual.
- **`openChat` e `closeChat` com `sessionId`** (chat só de leitura):
  - `sessionId` fora do formato UUID → `invalidPayload`;
  - sessão sem arquivo em `~/.claude/projects/*/<sessionId>.jsonl` → `sessionNotFound`;
  - a sessão não precisa estar em `archived`; o chat é acompanhado como qualquer outro, e o `chatPage` e os eventos voltam com o mesmo `sessionId`;
  - `sendPrompt`, `interrupt` e `slash` só aceitam `agentId`: o app não oferece envio num chat de sessão.
- **`openChat` e `closeChat` com `sessionId` e `subagentId`** (transcript de subagente, só leitura):
  - `sessionId` fora do formato UUID, ou `subagentId` fora de `[A-Za-z0-9_-]{1,64}` → `invalidPayload`;
  - sem arquivo em `~/.claude/projects/*/<sessionId>/subagents/agent-<subagentId>.jsonl` nem em `~/.claude/projects/*/<sessionId>/subagents/workflows/wf_*/agent-<subagentId>.jsonl` → `sessionNotFound`, com a mensagem "Subagente não encontrado";
  - vale para subagentes de `Agent`, aninhados e agentes de workflow, de sessão atual ou não; o chat é acompanhado ao vivo como qualquer outro, e o `chatPage` e os eventos voltam com o mesmo `sessionId` e `subagentId`;
  - `sendPrompt`, `interrupt`, `slash` e `archive` não aceitam alvo de subagente: os payloads deles não têm `subagentId`, e o app não oferece envio, interrupção nem arquivamento no chat de subagente.
- **`listSubagents`**:
  - agente desconhecido, depois de `resolve` → `agentNotFound`; agente com `kind != "claude"` → `invalidPayload`, com a mensagem do `openChat`; agente sem sessão → `subagentList` com `items: []`;
  - `items` traz só os subagentes de `Agent` da sessão atual, inclusive os aninhados; os agentes de workflow ficam no card do workflow;
  - ordem: primeiro os `running`, depois os terminados, cada grupo do mais recente ao mais antigo (pelo `startedAt` nos `running` e pelo fim, `startedAt` + `durationMs`, nos terminados); cada aninhado vem logo abaixo do pai, na mesma ordem entre irmãos, e um aninhado cujo pai não está na lista entra como de primeiro nível;
  - sem push contínuo: o app pede a lista ao abrir o Detalhe e de novo a cada `treeChanged` que muda o `runningSubagents` do agente.
- **`archive`**: `sessionId` que não é a sessão atual de nenhum agente da árvore → `sessionNotFound`. Aceito, o daemon responde `ack`, grava o arquivamento (§4.9) e manda `treeChanged` com o `archivedAt`.
- **`sendPrompt`, `interrupt` e `slash`**: agente com `kind != "claude"` → `invalidPayload`, com a mesma mensagem do `openChat`.
- **`newAgentTab`**:
  - `workspaceId` fora da árvore → `invalidPayload` ("Workspace não encontrado");
  - o daemon chama `tab.create {workspace_id, cwd: <diretório do workspace (§3.1.4)>, focus: false}` e depois `agent.start {name: "mocha-<n>", kind: "claude", pane_id: <root_pane.pane_id>, args: []}`, com `<n>` o menor inteiro a partir de 1 cujo nome não está em uso entre os agentes do Herdr;
  - espera o agente ficar `idle` ou `blocked` pelo `pane.agent_status_changed` do pane novo, ou por `agent.wait {target: <pane>, until: ["idle", "blocked"], timeout_ms: 30000}`, e responde `ack{agentId}` com o id do pane novo;
  - `blocked` é o diálogo de confiança de uma pasta nova (S2). O daemon não responde a esse diálogo: responde `ack{agentId}`, o agente aparece em PRECISA DE VOCÊ e o João responde no Mac;
  - passados os 30 s sem `idle` nem `blocked`, responde `ack{agentId}` do mesmo jeito, e o agente segue na árvore com o status que tiver;
  - a espera não segura as outras mensagens da conexão, que seguem sendo respondidas;
  - erros do `tab.create` e do `agent.start` seguem a tabela abaixo. Se o `agent.start` falhar, a tab criada continua aberta: o daemon não fecha tabs.
- **Erros do Herdr** (§3.1.1):

| Herdr | Protocolo |
|---|---|
| `agent_blocked` | `agentBlocked` |
| `agent_not_found`, `pane_not_found` | `agentNotFound` |
| Herdr indisponível | `herdrUnavailable` |
| `agent_not_ready`, `agent_prompt_stalled`, `timeout` e os demais | `internal`, com mensagem em português |

- **No app**: o app decide pelo `error.code` que chega antes do close. `unauthorized` e `pairingExpired` levam à tela de pareamento. O token só é apagado quando um pareamento novo dá certo ou no `unpair`.

### §5.4 Paginação

- `openChat` sem `before` devolve os últimos `limit` itens.
- `before` é o cursor opaco devolvido na página anterior. `hasMore == false` indica o começo do arquivo.
- Itens de `tool_result` que chegam depois atualizam itens que o cliente já tem, via `chatUpdate`. Se o `toolCall` não estiver carregado no cliente, o `chatUpdate` é ignorado.

### §5.5 HTTP do gateway

`GET /v1/health` não exige autenticação. O WebSocket (`GET /v1`) autentica pela mensagem `hello`. As demais rotas exigem `Authorization: Bearer <deviceToken>` e respondem 401 sem ele.

| Rota | Uso | Fase |
|---|---|---|
| `GET /v1/health` | `{"ok":true,"version":"…","herdr":true}` (para o `doctor` e o S5) | 1a-core |
| `GET /v1` (upgrade) | WebSocket | 1a-core |
| `POST /v1/respond` | Corpo `{requestId, response}` (mesmo JSON de §5.2.1). Usado pelas ações de notificação sem abrir o app. 200 com `{}`, 404 se o pedido não existe mais | 1b |
| `POST /v1/upload` | Corpo binário com `Content-Length` (no app, `URLSession.upload(for:from:)` com `Data`; corpo em stream vira chunked no Serve e recebe 411), `Content-Type: image/jpeg`, `image/png` ou `image/heic`. Resposta 200 `UploadResponse` (`{"path": "/Users/…/uploads/<uuid>.<ext>"}`, `MochaProtocol`). Erros: 401 sem Bearer válido, 411 sem `Content-Length`, 413 acima de 20 MiB (o `HttpServer` barra antes do handler, então vem antes do 401), 415 com outro `Content-Type`, 400 com corpo vazio. O arquivo é gravado atômico com 0600 em `uploads/` (0700), com nome UUID gerado pelo daemon e extensão pelo `Content-Type` (`jpg`, `png`, `heic`) | 1a-core |
| `POST /v1/live-activity` | Corpo `LiveActivityRegistration` (mesmo JSON do `registerLiveActivity`), com `Authorization: Bearer`. Usado pelo app acordado em background por push-to-start, sem WebSocket aberto, para entregar o token de update da atividade nova. 200 com `{}` | 1b |

---

## §6 App iOS

### §6.1 Estrutura

- SwiftUI, iOS 26+, só iPhone, só retrato na 1a.
- Estado de UI em classes `@Observable @MainActor`.
- Módulos em `App/Sources/`: `AppShell/` (raiz, navegação, deep links), `DesignSystem/`, `Connection/` (`KeychainTokenStore` e ligação do `MochaClient` à UI), `Pairing/`, `Home/`, `AgentDetail/`, `Usage/`, `Drawer/`, `Chat/`, `Composer/`, `Markdown/`, `Settings/`, `Notifications/`, `Inbox/` (1b), `LiveActivity/` (1b), `Voice/` (1b), `Terminal/` (fase 2) e `Debug/` (telas de preview e sondas dos spikes, só em Debug). Na fase subagentes, `Chat/` ganha os cards `SubagentCard`, `WorkflowCard` e `TaskCard` e o chat de subagente (`ChatScreen(target: .subagent)`); `Home/`, o selo de subagentes; e `AgentDetail/`, a lista SUBAGENTES (§6.3).
- Lógica pura de apresentação, testável no macOS, fica em `MochaClient/Presentation/`: seções da Home, ritmo do uso, tempos relativos ("agora", "há 4 min", "ontem"), abreviação do modelo e agrupamento de ferramentas.
- A lógica de conexão fica no target `MochaClient` do pacote (testável no macOS): `ConnectionManager` (actor) implementa `ServerConnection` sobre `URLSessionWebSocketTask`, com backoff e um `TokenStore` injetado. O app entrega o `KeychainTokenStore`.
- O WebSocket fica aberto enquanto o app está em primeiro plano. Ele fecha com 1001 quando o `scenePhase` vira `.background` (inclui bloquear a tela) e reabre em `.active`. O `.inactive` (Central de Controle, Central de Notificações) não fecha. A troca de rede também não fecha (§2.3).
- **Deep links**: `mocha://agent/<paneId>` abre o chat por cima da Home (substitui o chat aberto, se houver) e `mocha://pair?url=…&code=…` inicia o pareamento, lido com `PairingLink`. O `paneId` vai percent-encoded, porque contém `:`. Os testes abrem deep links pelo argumento de launch `-open-url <url>` (só em Debug) e por teste unitário, nunca por `simctl openurl` (o aviso "Open in Mocha?" trava o simulador).
- **Argumentos de launch**: `-demo`, `-demo-script` (§2.2), `-demo-unpaired` (junto com `-demo`, abre em `pairingRequired(nil)`), `-demo-empty` (junto com `-demo`, árvore sem nenhum Claude: Home vazia), `-demo-offline` (junto com `-demo`, a conexão cai logo depois de entregar a árvore, as arquivadas e o uso, e fica em `waitingToRetry(.unreachable)`: Home sem conexão), e, só em Debug, `-open-url <url>` (entrega a URL ao `AppSession` como um deep link), só em Debug, `-open-settings` (abre Ajustes ao iniciar, para a captura da tela 12), só em Debug, `-pairing-error <unreachable|daemonNotRunning|unauthorized|pairingExpired>` (par chave-valor; junto com `-demo -demo-unpaired`, troca o `pairingRequired(nil)` pelo problema, para a captura da tela 01c), só em Debug, `-open-drawer` (abre a gaveta ao iniciar, depois do `-open-url` de um chat; com `-drawer.collapsedWorkspaces <ids separados por quebra de linha>` no domínio de argumentos, serve às capturas da gaveta; os pares `-chave valor` vêm antes das flags), só em Debug, `-open-history` (abre no Histórico), `-open-new-session agent|workspace` (par chave-valor; abre a folha Nova sessão no passo 1 ou no passo 2 com Claude), só em Debug, `-preview design-system|markdown` (a tela `DesignSystemPreview` ou a `MarkdownPreviewScreen`; `-preview-section <seção>` mostra uma seção só da `DesignSystemPreview`, ou da `MarkdownPreviewScreen` com `turn|elements|blocks|perf`), e, só em Debug e lidos dentro do chat, `-chat-open-session`, `-chat-scroll-to`, `-chat-scroll-anchor center|bottom`, `-chat-expand-tool`, `-chat-focus-composer`, `-chat-draft`, `-chat-send`, `-chat-older-delay`, `-chat-perf-sweep`, `-chat-attach-samples <n>` (par chave-valor; anexa n imagens de amostra geradas no app, antes do `-chat-focus-composer` e do `-chat-send`; com `-chat-send ''`, envia só as imagens) e `-chat-attach-menu` (com `-chat-focus-composer`, abre o menu do `+`), `-chat-slash-menu` (com `-chat-focus-composer`, abre o menu `↻`), `-chat-confirm-clear` (mostra a confirmação do `/clear`), `-chat-slash <comando>` (executa um item do menu `↻` sem confirmação) e `-chat-close-after <s>` (volta para a Home depois de s segundos) (servem às capturas e à medição do chat, §6.3 e §6.5), e, só em Debug e lidos em `Notifications/`, `-notification-tap <agentId>` (injeta um alerta de turno concluído desse agente pelo mesmo caminho do toque na notificação) e `-notification-tap-delay <s>` (atrasa essa injeção), e, só em Debug e lido dentro do chat, `-chat-open-subagent <agentId>` (abre por push o transcript desse subagente da sessão do chat aberto, para as capturas 16b e 16c), e, só em Debug e lido em `Home/`, `-home-open-detail <agentId>` (abre o Detalhe desse agente ao iniciar, para a captura 18). O `-preview` é lido só dos argumentos de launch (domínio de argumentos do `UserDefaults`), nunca de um valor gravado.

**Conexão**: esboço normativo em `MochaProtocol`, como a §5.2.

```swift
public enum ConnectionProblem: String, Sendable, Equatable {
    case unreachable        // timeout ou erro de rede: "Sem conexão com o Mac"
    case daemonNotRunning   // 502 no handshake: "O Mac respondeu, mas o mochad não está rodando"
    case unauthorized       // token recusado (aparelho removido ou token inválido)
    case pairingExpired     // código de pareamento vencido ou já usado
    case protocolMismatch
}

public enum ConnectionState: Sendable, Equatable {
    case idle                                   // antes de start(), depois de stop() ou em background
    case connecting                             // abrindo o WebSocket ou esperando o helloOk
    case connected                              // helloOk recebido; tree chega em messages
    case waitingToRetry(ConnectionProblem)      // backoff (§2.3)
    case pairingRequired(ConnectionProblem?)    // sem token, token recusado, código vencido ou depois de unpair
    case failed(ConnectionProblem)              // não se resolve sozinho (protocolMismatch); só tenta de novo no próximo start()
}

public struct PairingLink: Sendable, Equatable {
    public var url: URL         // wss://<host>/v1
    public var code: String     // base64url
    public init?(_ link: URL)   // mocha://pair?url=<percent-encoded>&code=<código>
    public var link: URL
}

public enum ServerConnectionError: Error, Sendable, Equatable { case notConnected }

public protocol ServerConnection: Sendable {
    var messages: AsyncStream<ServerEnvelope> { get }
    var states: AsyncStream<ConnectionState> { get }
    func start() async
    func stop() async
    func pair(_ link: PairingLink) async
    func send(_ message: ClientMessage, id: String) async throws
}
```

- `messages` e `states` têm um consumidor só (o `AppSession`) e atravessam reconexões. `states` começa pelo estado atual.
- A conexão faz o `hello` sozinha a cada abertura, com o token do `TokenStore` ou com o código recebido em `pair`. `helloOk` e `tree` chegam em `messages` com o id `hello-<n>`; o app trata os dois como atualização de estado, sem correlação.
- `send` exige `.connected`; fora dele, lança `notConnected`. O id vem do app (`c-<n>`), que o registra antes de chamar `send`, para a resposta nunca chegar antes do registro.
- `unpair`: depois do `ack`, a conexão apaga o token e vai para `pairingRequired(nil)`.
- `start()` é idempotente. `stop()` fecha com 1001 e vai para `.idle`.
- `DemoServerConnection` e `ConnectionManager` implementam o mesmo contrato.

**`AppSession`** (`App/Sources/AppShell/`, `@MainActor @Observable`):
- é o único consumidor de `messages` e `states`;
- guarda o host, as preferências, a árvore, as sessões arquivadas, o uso, o `herdrConnected`, o estado da conexão, o chat visível e a navegação;
- **navegação**: a raiz do `NavigationStack` é um paginador com duas telas irmãs, o Histórico à esquerda e a Início à direita (`rootPage`), sob um header fixo que não desliza com as páginas: só o conteúdo troca, e o botão da esquerda passa dos anéis para a casa acompanhando o arraste; arrastar da esquerda para a direita na Início (ou o botão de anéis) abre o Histórico, e arrastar da direita para a esquerda no Histórico (ou o botão de casa) volta, a não ser que o gesto comece num card arquivável. O chat entra por push (`ChatScreen(target:)`), e voltar é arrastar da borda esquerda (o gesto de voltar do sistema, religado com a barra de navegação escondida). A gaveta é uma camada por cima que só existe dentro do chat, aberta tocando no disco de status do header. Detalhe do agente, Uso, Ajustes e Nova sessão são folhas. O Pareamento cobre tudo enquanto a conexão está em `pairingRequired`;
- **chat de subagente** (fase subagentes): entra por push sobre a pilha atual (o chat pai, outro transcript de subagente ou, a partir do Detalhe, a pilha que está sob a folha: a Home ou o chat que abriu o Detalhe), e voltar volta à tela de baixo. Os chats da pilha ficam abertos no daemon (sem `closeChat`) enquanto estão nela, e cada um recebe `closeChat` ao sair dela;
- correlaciona as respostas pelo id;
- ao voltar para `.connected`, reabre com `openChat` o chat visível e os que estão abaixo dele na pilha, e substitui as listas;
- num `tree` ou `treeChanged`, se o `agentId` do chat visível sumiu e outro agente tem o mesmo `sessionId`, passa a usar o id novo.

### §6.2 Design system

O visual segue o **mock aprovado**: `docs/design/mock.html`, com uma captura 3x (1170 × 2532) de cada tela em `docs/design/mock/NN-nome.png`. Quando o mock e os prints do Moshi (`docs/referencias/moshi/`) divergem, vale o mock. As medidas estão no CSS do mock, com 1 px do mock = 1 pt no iPhone (tela de 390 × 844). Toda tela nova é comparada lado a lado com a captura correspondente, no simulador, antes de ser dada como pronta. As cores abaixo são as variáveis do mock (as do chat foram medidas nos prints do Moshi, ±4 por canal).

| Token | Hex | Uso |
|---|---|---|
| `bg` | `#1E1E1E` | Fundo do chat e do terminal |
| `drawerBg` | `#161719` | Fundo da gaveta |
| `scrim` | `#0F0F10` | Conteúdo escurecido atrás da gaveta: camada preta a 50 % sobre o `bg`, que resulta nesse hex |
| `textPrimary` | `#FCFCFC` | Texto do chat, nomes de workspace, texto em negrito |
| `textSecondary` | `#98A0A8` | Subtítulos, "Brewed for", recap, placeholder, branch, cabeçalho de seção, ícone de shell |
| `link` | `#78A0F4` | Código inline, caminhos e comandos no markdown |
| `userBubble` | `#1B351B` | Bolha do usuário (texto `textPrimary`) |
| `selectedRow` | `#142E16` | Linha selecionada na gaveta |
| `toolCard` | `#121416` | Card de ferramenta (borda `#303438` só no card expandido; o fechado não tem borda) |
| `glass` | `#3C3C3C` translúcido | Header e botões flutuantes (Liquid Glass escuro) |
| `composer` | `#383838` translúcido | Composer flutuante |
| `controlBg` | `#202225` / selecionado `#121416` | Controle segmentado (recentes/árvore) |
| `claude` | `#D87454` | Ícone asterisco do Claude |
| `gitAccent` | `#FB923C` | Botão circular de git no header (fora do MVP; o espaço fica reservado) |
| `statusOk` | `#00FF00` | Disco de status no header, com um glifo `−` preto no centro (print `chat-conversa.png`) |
| `dirty` | `#F4B450` | Asterisco de alterações pendentes ao lado da branch |
| `error` | `#D8383C` | ✗ de ferramenta com falha |
| `termText` | `#D4D8E0` | Texto padrão do terminal (fase 2) |
| `accessoryBar` | `#424242` / tecla `#272829` | Barra de teclas do terminal (fase 2) |
| `black` | `#010102` | Fundo da Home, do Uso e do Detalhe, sob os brilhos verdes |
| `toolBorder` | `#303438` | Borda do card de ferramenta expandido |
| `controlSel` | `#121416` | Segmento selecionado |
| `badgeOk` | `#0F3712` | Fundo do selo de workspace (texto `statusOk`) e dos selos verdes |
| `badgeWarn` | `#342C1F` | Fundo dos selos âmbar (texto `dirty`) |
| `sepDot` | `#55595F` | Ponto separador "•" da linha de metadados do card |
| `ringTrack` | `#2F3032` | Trilho do anel de contexto |
| `ringAuto` / `ringAutoTrack` | `#A482E6` / `#352C47` | Arco e trilho do anel externo (agentes em modo auto ou edição) do botão de anéis da Início |
| `ringPlan` / `ringPlanTrack` | `#48A89E` / `#1D3A38` | Arco e trilho do anel interno (agentes em modo plan) do botão de anéis da Início |
| `divider` | `#202223` | Divisórias de lista e de folha |
| `barTrack` | `#191B1D` | Trilho das barras de uso |
| `paceMark` | `#979899` | Traço do ritmo constante nas barras de uso |
| `claudeTile` | `#2E221F` | Ladrilho do asterisco no Uso |
| `heroBg` | `#120A08` | Fundo do bloco principal do Detalhe |
| `heroTile` | `#2E1914` | Ladrilho do asterisco no Detalhe |
| `tableBorder` | `#2B2B2B` | Borda das tabelas do markdown |
| `codeInner` | `#17191B` | Caixa interna do card expandido (prévia do resultado) |
| `grabber` | `#47474B` | Alça das folhas |

- **Vidros** (`glassEffect` escuro do iOS 26 com tinta; no mock, fundo translúcido com borda interna clara): `glassChat` `rgba(66,66,66,.8)` no header do chat e nos botões dele; `glassComposer` `rgba(62,62,62,.84)`; `glassHome` `rgba(62,78,64,.5)` nos botões redondos da Home; `glassPill` `rgba(96,100,106,.5)` na pílula de uso e na cápsula "sem conexão"; `glassHero` `rgba(84,74,72,.5)` no X do Detalhe; `glassBlack` `rgba(60,60,62,.55)` nos botões sobre a câmera.
- **Brilho da Home**: sobre `black`, dois gradientes radiais verdes (`statusOk`): 260 × 330 pt centrado no topo (y = 40) com 7,8 % de opacidade, e 250 × 240 pt no canto inferior direito com 11,5 %, os dois indo a 0. Home, Uso, Detalhe, Ajustes, Inbox e Pareamento usam esse fundo; o chat usa `bg`.

- **Tipografia**:
  - Chat, header e composer usam a **JetBrains Mono** (OFL, §11), identificada no print pelo zero com ponto central, pelo `l` com cauda curva e pela ligadura de `...`. Pesos empacotados em `App/Resources/Fonts/`: Regular, Italic, Bold e BoldItalic.
  - Medidas do print (3x): corpo do chat 14,67 pt, com uma linha a cada 20 pt; título do header 16 pt em negrito; subtítulo e card de ferramenta 12 pt; composer 14 pt. Tudo respeita o Dynamic Type (`relativeTo:`), e o tamanho do corpo fica num token só.
  - A gaveta, a Home, as folhas (Uso, Detalhe, Ajustes, Inbox) e o Pareamento usam a fonte do sistema (SF Pro). Na Home: cabeçalho de seção 12 pt maiúsculo em `textSecondary`; título do card 16 pt semibold; segunda linha 14 pt; selo 11 pt semibold. Os valores mono do Detalhe (workspace, tab, sessão) usam a JetBrains Mono.
- **Ponto de status do header**: `idle` e `done` em `statusOk` (disco com o glifo `−`), `working` em `statusOk` pulsando, `blocked` em `dirty`, `unknown` e sem conexão em `textSecondary`. Num chat de sessão arquivada, `textSecondary`.
- **Anel de contexto** (card da Home): 40 pt, trilho `ringTrack`, arco proporcional ao `contextLeftPercent` com o número no centro (11 pt semibold) e um selo redondo no topo (⚡ verde; `!` âmbar em `blocked`). Cor do arco: `dirty` em `blocked`; `statusOk` nos demais; esmaecido (50 %) nos arquivados; sem conexão, cinza e parado. Em `working`, um arco curto extra gira em volta. Sem `contextLeftPercent`, o número vira "—" e o arco some.
- **Vidro**: `glassEffect` do iOS 26 no header, no composer e nos botões redondos flutuantes, sempre escuro (o app força `.preferredColorScheme(.dark)`).
- **Ícones**: SF Symbols. O asterisco do Claude é um símbolo desenhado (asset vetorial) na cor `claude`.

### §6.3 Telas

Cada tela cita a captura de `docs/design/mock/` que ela precisa reproduzir.

**Pareamento** (`01-pareamento`, `01b-lendo-qr`, `01c-erro-pareamento`)
- Primeira execução, token recusado ou depois de desparear. Fundo da Home, logo, "Parear com o Mac" e as instruções `mochad pair`.
- "Ler QR" abre a câmera em tela cheia (`DataScannerViewController`); ao reconhecer o QR, os cantos ficam verdes e a pílula mostra "Conectando ao <host>…"; pareado, vai direto para a Home. O X volta.
- "Colar" só aparece quando a área de transferência tem um link `mocha://pair`, que também chega por deep link.
- O aviso de erro fica acima do botão até a próxima tentativa. Mensagens:
  - "O Mac respondeu, mas o mochad não está rodando" (502 no handshake);
  - "Sem conexão com o Mac" (timeout ou erro de rede);
  - "Código vencido; gere outro com `mochad pair`" (`pairingExpired`);
  - "Este iPhone não está mais pareado" (`unauthorized`).

**Início** (`21-inicio`, `21e-inicio-vazia`)
- Tela inicial. Header fixo, compartilhado com o Histórico: à esquerda, o botão redondo de anéis (44 pt, vidro `home`), que abre o Histórico; à direita, uma cápsula de vidro `home` (44 pt de altura) com o globo, que abre a folha Servidores web, e a engrenagem de Ajustes; o sino da Inbox, com a contagem, entra na cápsula antes do globo só quando há pedido pendente. Os anéis contam os agentes Claude e Codex: o externo (`ringAuto`) enche um terço por agente Claude com `permissionMode` `auto`, `acceptEdits` ou `bypassPermissions` (cheio com 3 ou mais) e o interno (`ringPlan`) um quarto por agente Claude em `plan` (cheio com 4 ou mais), os dois das 12 h no sentido horário e sem animação; `default` e os agentes Codex não entram nos anéis. A bolinha no canto superior direito pulsa (opacidade de 30% a 100% num ciclo de 1,4 s; fixa com Reduzir movimento): `dirty` quando algum agente está `blocked`, senão `statusOk` quando algum está `working`, e some quando nenhum. Sem conexão, os anéis ficam em `offlineRing` e a bolinha some, e a cápsula "Sem conexão com o Mac" aparece no header, logo abaixo dos botões, nas duas telas. Abaixo do header, no conteúdo da Início, a barra "Buscar", só visual por enquanto.
- RECENTES ("Segure para opções" à direita): carrossel horizontal com até 10 conversas por atividade (agentes e sessões arquivadas, lógica em `StartSections`). Cada card de 162 pt tem a miniatura (a `preview`: do usuário em bolha, do assistente em texto; e a `activity` como linha de ferramenta), o chip de estado e o do provedor; abaixo, o título do card e "<workspace em mono verde> · <tempo>". Tocar abre o chat; segurar abre o Detalhe.
- Embaixo, só PRECISA DE VOCÊ e TRABALHANDO, com os mesmos cards do Histórico. Sem a pílula de uso.
- Botão + verde (60 pt) no canto inferior direito: abre a folha Nova sessão.
- Vazia: "Nenhum agente aberto no Herdr" e "Toque em + para abrir uma tab com Claude ou Codex num workspace."

**Nova sessão** (`21b-nova-sessao-agente`, `21c-nova-sessao-workspace`, `21d-nova-sessao-abrindo`)
- Folha `drawerBg` na altura do conteúdo, sem título, X ou indicador de passo. Passo 1, "O que você quer abrir no Herdr?": Claude, Codex e Shell (desabilitado, selo FASE 2). Passo 2, "Escolha o workspace do Herdr": os workspaces (inclusive worktrees) com nome, branch e `*` em `dirty`.
- Tocar num workspace manda `newAgentTab{workspaceId, kind}` e mostra só um indicador de progresso na linha. No `ack{agentId}`, a folha fecha e o chat abre por push; um erro aparece no rodapé. Fechar (arrastar ou tocar fora) e reabrir volta ao passo 1.

**Histórico** (`22-historico`)
- Tela irmã da Início, à esquerda, sob o mesmo header fixo, sem título: no lugar dos anéis, o botão de casa que volta à Início; a cápsula (sino só com pedido pendente, globo e engrenagem) continua.
- Mostra só agentes com `kind == "claude"` e as sessões de `archived`. Seções, nesta ordem, cada uma só quando tem card:
  - **PRECISA DE VOCÊ**: `status == blocked`. Card com borda âmbar;
  - **TRABALHANDO**: `status == working`;
  - **ARQUIVADOS**: `archivedAt != nil`; ou `sessionStartedAt` há mais de 6 h; ou `turnEndedAt ?? lastActivityAt` há 10 min ou mais; e todas as `ArchivedSession`. As duas regras de tempo não valem com `runningSubagents > 0` (fase subagentes): o agente com subagente rodando fica em CONCLUÍDOS;
  - **CONCLUÍDOS**: os demais agentes.
  A regra é avaliada nessa ordem (blocked > working > arquivado > concluído), com o relógio local, a cada mudança da árvore e a cada 30 s. A lógica fica em `MochaClient/Presentation/` com testes. A ordem dentro da seção é `lastActivityAt` (ou `endedAt`) decrescente.
- **Card**:
  - anel de contexto à esquerda (§6.2) e chevron à direita;
  - título: a `preview`, com "Você: " antes quando o autor é `user`; sem `preview`, "Sessão limpa";
  - segunda linha, opcional: em `blocked`, "Precisa de você · <ferramenta>" em `dirty` (só "Precisa de você" sem `activity`); em `working` com `activity`, "<ferramenta>: <resumo>" em `textSecondary`; numa `ArchivedSession`, "Sessão encerrada". O nome da ferramenta segue o card de ferramenta (`Bash` → "Shell");
  - metadados: selo do workspace (`badgeOk`), "Claude Code" em `claude` e o tempo relativo de `lastActivityAt` ("agora" abaixo de 1 min, "há N min", "há N h", "ontem", "há N dias"), separados por `sepDot`;
  - tocar abre o chat (`agentId`, ou `sessionId` numa `ArchivedSession`); segurar abre o Detalhe; arrastar para a esquerda um card de CONCLUÍDOS manda `archive{sessionId}` (a ação "Arquivar"). Os outros cards não arrastam.
- **Pílula de uso** flutuante no rodapé (`glassPill`): asterisco, "5h" com barra e %, divisória, "7d" com barra e %. Tocar abre o Uso. Some sem `usage`.
- **Sem conexão**: a lista fica com o último estado conhecido, anéis parados em cinza, e uma cápsula no topo ("Sem conexão com o Mac", ou a mensagem do estado) abre Ajustes. Nada some; a reconexão é automática.
- **Vazio**: nenhum agente nem sessão arquivada. Texto "Nenhum agente aberto", sem botão.

**Servidores web** (referência: `docs/referencias/moshi/servidores-web.jpg`, sem o card de usos grátis)
- Painel próprio igual ao do Uso (`BottomPanelLayer`), colado às bordas, com o topo em 50% da tela; arrastar para baixo fecha. Fundo `drawerBg`, título "Servidores web". Ao abrir, manda `listWebServers` e mostra um indicador até a resposta; a lista também recarrega quando a conexão volta. Não há puxar para recarregar, que conflitaria com arrastar para fechar.
- Uma seção por workspace do Herdr, na ordem da árvore (worktrees como workspaces próprios), com o `label` em maiúsculas no estilo de cabeçalho de seção; servidores sem `workspaceId` (ou de um workspace fora da árvore) vão numa última seção com o `host`. As linhas ficam num cartão arredondado com divisórias: ícone de disco (`externaldrive`) à esquerda, o `title` (ou, sem ele, o nome da pasta de `directory`, ou "Porta <port>") em 17 pt semibold e, embaixo, "PID <pid> · <process> · PORT <port>" em mono `textSecondary`.
- Tocar numa linha abre o Navegador (§9.3). Só em Debug, `-open-web-servers` abre a folha ao iniciar; com `-demo`, a lista traz os dois servidores do print, e com `-demo-empty` vem vazia. Sem servidores: "Nenhum servidor web rodando no Mac". Sem conexão: a lista some e fica a mesma mensagem da cápsula "Sem conexão com o Mac".

**Navegador** (preview web)
- Tela cheia por cima de tudo (`fullScreenCover`), fundo `black`. Barra superior de vidro com o botão de fechar à esquerda, o título da página (ou "localhost:<porta>") no centro, com a branch do workspace do servidor embaixo em `textSecondary` (sem workspace ou sem branch, só o título) e recarregar à direita; embaixo dela, o `WKWebView`.
- Enquanto o túnel abre, um indicador com "Conectando ao Mac…"; falha do SSH mostra o erro e "Tentar de novo". Sem a chave autorizada no Mac, o erro aponta para Ajustes (chave pública, §9.1). Abrir o Navegador fecha a folha ou o painel aberto. Só em Debug, `-open-web-preview <porta>` abre o Navegador ao iniciar; com `-demo`, a página vem do próprio app (`StaticPageTunnelChannel`), sem SSH.

**Uso do plano** (`03-uso-plano`)
- Folha média sobre a Home (arrastar fecha), fundo `drawerBg`. Título "Uso" e, à direita, "atualizado há X" (de `fetchedAt`).
- Cartão: ladrilho do asterisco, "<plano> (<conta>)" (sem plano, "Claude"; sem conta, sem parênteses) e "Claude Code · <hostName>".
- Uma linha por janela (`fiveHour` → "5h", `weekly` → "7d"): barra com o `usedPercent`, o traço `paceMark` na posição do tempo decorrido, o % e o tempo até zerar ("3h 35m", "2d 10h").
- Tempo decorrido da janela = `1 − (resetsAt − agora) / duração` (5 h ou 7 dias). Ritmo = `usedPercent − decorrido × 100`: acima de +5, "ritmo mais rápido"; abaixo de −5, "ritmo mais lento"; entre os dois, "no ritmo". A linha de baixo junta as duas: "5h: ritmo mais lento · 7d: no ritmo".
- Nota fixa no rodapé: "Os números vêm do último turno do Claude no Mac e ficam velhos quando não há turnos. O traço cinza marca onde o uso estaria num ritmo constante até o fim da janela."

**Detalhe do agente** (`04-detalhe-agente`, `04b-detalhe-precisa-de-voce`)
- Folha grande, aberta tocando no título do header do chat ou segurando um card da Home. X (`glassHero`) ou arrastar para baixo fecha.
- Bloco principal (`heroBg`): ladrilho do asterisco, a `preview` (como no card, até 4 linhas), "<workspace em mono verde> · <hostName> · <tempo relativo>" e o selo de estado: TRABALHANDO (verde, a borda gira), PRONTO (verde), PRECISA DE VOCÊ (âmbar; o workspace fica âmbar também). Numa `ArchivedSession`, o selo ENCERRADA em `textSecondary`.
- "Abrir terminal" (fase 2): oculto até lá.
- Cartão Conta: "<plano> (<conta>)" e as barras de 5h e 7d, sem o traço de ritmo. Some sem `usage`.
- Lista: Host (`hostName`), Modelo (abreviado como no header), Workspace do Herdr, Tab do Herdr (`TabNode.title`), Sessão (id encurtado no meio, em mono; tocar copia o id inteiro e mostra "Copiado").
- Na 1b, com pedido pendente, um botão "Responder" leva ao card do pedido no chat.

**Chat** (`05-chat-inicio-turno`, `05b-chat-fim-turno`, `06-card-expandido`, `07-chat-trabalhando`)
- **Header flutuante de vidro** (`glassChat`), com:
  - disco de status (§6.2); tocar abre a gaveta;
  - asterisco do Claude e título (truncado no meio); tocar no título abre o Detalhe;
  - subtítulo "workspace • modelo • branch" em `textSecondary` (modelo abreviado: sem o prefixo `claude-` e sem o sufixo de data `-AAAAMMDD`, ex.: `claude-opus-5-5` → `opus-5-5`, `claude-haiku-4-5-20251001` → `haiku-4-5`);
  - botão redondo de git, reservado e desabilitado;
  - bússola, presa ao workspace do agente: pede `listWebServers` e filtra pelo `workspaceId` do workspace que contém o agente. Com 1 servidor, abre direto o Navegador; com 0 ou vários, abre o painel Servidores web só com esse workspace (vazio: "Nenhum servidor web neste workspace"). Sem workspace conhecido (thread Codex, sessão arquivada sem agente vivo), abre o painel global.
  - O conteúdo rola por baixo do header e do composer.
- **Lista**:
  - `userPrompt`: bolha à direita, cantos arredondados de ~16 pt, largura máxima de 85 % da área de conteúdo (a bolha ocupa essa largura quando o texto quebra).
  - `assistantText`: markdown à esquerda, largura total, sem bolha.
  - `toolCall`: card `toolCard` de uma linha (ícone, nome em negrito, resumo, e à direita ✓, ✗ em `error` ou o giro de `running`). O nome de exibição de `Bash` é "Shell". Chamadas **consecutivas** da mesma ferramenta formam um card só, com contador (`Shell ×3 …`) e ✗ quando alguma falhou. Tocar expande: por chamada, o input (`$ comando` no Shell) e a prévia do resultado numa caixa `codeInner`; o card expandido ganha a borda `toolBorder`. Tocar de novo recolhe.
  - `thinking`: linha colapsada "Pensou" em itálico `textSecondary`; toque expande quando há texto. Vários `thinking` seguidos viram uma linha só (cerca de 90 % vêm sem texto).
  - `turnFooter`: "Brewed for 45s" em itálico `textSecondary`.
  - `recap`: "**Recap:** …" em itálico `textSecondary`.
  - `slashCommand`: chip discreto à direita com `name` e `args` (ex.: "/clear"); com `output`, o toque expande a saída em mono. `name == "!"` é um comando de shell digitado no terminal.
  - `notice`: texto centralizado pequeno.
- **Linha de status** no fim da lista enquanto `status == working`: "✱ Trabalhando… (3m 58s)", com o tempo desde `turnStartedAt` atualizado a cada segundo, e à direita o botão verde redondo de **parar**, que manda `interrupt`.
- **Rolagem**: gruda no fim quando o usuário já está no fim. Se ele rolou pra cima, aparece o botão redondo "↓" (canto inferior direito, acima do composer) e itens novos não mexem na posição. Enviar sempre leva ao fim.
- **Paginação**: ao chegar no topo, carrega `before` com um indicador; a posição de leitura se mantém.
- **Troca de sessão**: quando o `sessionId` do agente do chat aberto muda num `tree`/`treeChanged` (depois de `/clear`), o app reabre o chat com `openChat` e substitui a lista; a sessão nova começa com o chip `/clear` e o aviso centralizado.
- **Bolha "enviando"**: cada `sendPrompt` cria uma bolha pendente, esmaecida, com "enviando…" abaixo.
  - As bolhas são casadas em ordem (FIFO), com o texto aparado, com o próximo `userPrompt` ou `slashCommand` que chegar (`slashCommand` para texto `/x …` ou `!cmd`).
  - A bolha também some quando chega um `chatPage`, porque a lista é substituída.
  - Depois de 60 s sem par, ela fica marcada "sem confirmação", e o toque a descarta.
- **Sessão arquivada** (`ChatTarget.session`): mesma lista, sem linha de status; o composer dá lugar a uma pílula `glassComposer` "Sessão encerrada · só leitura".

**Composer** (`05-chat-inicio-turno`, `08-chat-digitando`), flutuante sobre o fim da lista
- **Recolhido**: uma linha só, "Chat via Mocha…", com o botão enviar à direita. Um rascunho não enviado aparece na linha recolhida, em branco, com enviar aceso.
- **Expandido** (ao tocar): campo multilinha (até 6 linhas, depois rola) e a linha de botões:
  - `+`: imagem (§6.5);
  - microfone: 1b (oculto antes);
  - `↻`: menu de slash e ações, 1a-final (oculto antes);
  - enviar: círculo, desabilitado sem texto.
- O teclado fecha, e o composer volta a uma linha, ao rolar a lista, tocar fora, abrir a gaveta ou enviar.
- Enviar continua enviando durante `working` (o Claude enfileira). Parar fica só na linha de status.
- **Menu `↻`** (1a-final, `09-menu-slash`, `09b-confirma-clear`): abre acima do `↻`, por cima do teclado. `/compact`, `/clear` (com confirmação), `/context`, `/cost` e "Interromper (Esc)". Comandos que abrem seletor no terminal (`/model`, `/resume`) ficam fora. Lista fixa no código. Depois do `/clear`, o chat reabre na sessão nova.

**Pedido no chat** (1b, `10-pedido-aprovacao`, `10b-pergunta`)
- O card do `PendingRequest` do agente entra no fim da lista, e o disco do header fica âmbar.
- Aprovação: ferramenta, resumo, "Ver entrada completa" (abre o JSON do input) e os botões "Permitir" e "Negar", que respondem na hora.
- Pergunta: seleção única com rádio, múltipla com caixas, "Outro…" como resposta livre. Uma pergunta: um bloco e "Responder" (`10b`). Várias perguntas: uma por vez (`10c`, `10d`), com "<header> · N de M" e um segmento por pergunta; na seleção única, tocar numa opção avança; com caixas ou "Outro…", avança pelo "Próximo"; "Voltar" reabre a anterior com a resposta; na última, "Enviar" manda todas num `answers` só.

**Gaveta** (`11-gaveta-arvore`)
- Camada por cima do chat, **só dentro do chat**: abre tocando no disco de status do header; não há gesto para abrir. Nunca na Início nem no Histórico. Ao abrir, fecha o teclado. Ocupa ~90 % da largura com `scrim` no restante; fecha tocando no scrim ou arrastando para a esquerda; voltar do chat fecha a gaveta.
- Topo: só o campo de busca ("Buscar workspaces, agentes…"), filtrando por workspace, tab e título do agente.
- Árvore: cabeçalho "WORKSPACES"; cada workspace tem chevron, nome em peso médio, ícone de branch com o nome, `*` em `dirty` quando `isDirty`, e worktrees aninhados sob o repositório.
- Tabs: ícone (asterisco do Claude ou `>_`) e título do agente ou da tab. Quando a branch do agente difere da do workspace (§3.1.4), ela aparece em `textSecondary` na linha do agente. Agente ocioso não tem indicador. Em `working` o asterisco pulsa com brilho; em `blocked` aparece um ponto `dirty` à direita.
- A linha do chat aberto fica com `selectedRow`. Tocar numa tab com agente fecha a gaveta e abre o chat (por push sobre a Home, substituindo o chat aberto); tocar numa tab de shell mostra "Terminal chega na fase 2" (na fase 2, abre o terminal).
- Sem `+` por workspace: nova tab é pela folha Nova sessão da Início.

**Ajustes** (`12-ajustes`)
- Folha aberta pela engrenagem da Início.
- Host pareado e data do pareamento (guardada no app), estado da conexão (com as mensagens da tela de pareamento), validade do perfil de provisionamento (`ExpirationDate` do `embedded.mobileprovision`, quando existe; em `dirty` abaixo de 7 dias), a seção NOTIFICAÇÕES com o controle "Turno concluído" (`setPreferences`, 1a-final; volta ao valor anterior se o daemon responder erro e fica esmaecido sem conexão), versão do app e do daemon, e "Desparear" (pede confirmação, manda `unpair`, limpa o Keychain e volta ao Pareamento).

**Inbox** (1b, `13-inbox`)
- Sino na cápsula da Início, com a contagem. Abre uma folha.
- Um cartão por `PendingRequest`, com agente, workspace e tempo, e as mesmas ações do pedido no chat.
- Tocar no nome do agente abre o chat.

**Tela bloqueada e banner** (1a-final e 1b, `14-tela-bloqueada`, `14b-banner`): a Live Activity (1b, §7.3) e o alerta de turno concluído (1a-final, §7.1). Com o app aberto em outro chat, o alerta chega como banner; o do chat visível é suprimido (`setForeground`). Tocar abre `mocha://agent/<paneId>`.

**Terminal** (fase 2, `15-terminal`): folha sobre o chat com o terminal do pane (§9.1), aberta por "Abrir terminal" no Detalhe ou por uma tab de shell da gaveta.

**Subagente no chat** (fase subagentes, `16-chat-subagente` e os estados abaixo dela no mock)
- `subagent`: card `toolCard` próprio para cada chamada, sem agrupar com a seguinte (o agrupamento de chamadas consecutivas é só do `toolCall`):
  - primeira linha: ícone de subagente, o tipo em negrito (sem o prefixo de plugin, que o daemon já tira: `feature-dev:code-reviewer` → `code-reviewer`), a descrição (truncada no fim) e, à direita, o giro (`running`), ✓ (`completed`), ✗ em `error` (`failed`) ou ■ (`stopped`);
  - em `running` com `activity`, uma linha recuada com o ícone e o nome de exibição da ferramenta (os do `toolCall`: `Bash` → "Shell") em negrito e o resumo;
  - última linha, recuada, em `textSecondary`, com o chevron à direita: tempo e ferramentas ("3m 51s • 9 ferramentas"; "1 ferramenta" no singular). Em `running`, o tempo conta desde `startedAt`, atualizado a cada segundo; no fim, é o `durationMs`. Em `failed`, a linha começa com "falhou" em `error` ("falhou • 48s • 3 ferramentas"); em `stopped`, com "parado". Sem tokens;
  - tocar abre o transcript do subagente (`ChatTarget.subagent` com o `sessionId` do chat e o `agentId`); sem `agentId` (antes do lançamento), o toque não faz nada. O card não expande.
- O aviso `Agent "…" finished` do transcript principal não aparece (§3.2.2): o card mostra o fim.
- Tempos no formato da linha de status ("48s", "2m 14s", "1m 02s").

**Transcript do subagente** (`16b-transcript-subagente`, `16c-transcript-concluido`)
- `ChatScreen(target: .subagent)`, só de leitura, por push (§6.1).
- **Header de vidro**: botão de voltar no lugar do disco de status; ícone de subagente em `claude` no lugar do asterisco; título = `ChatMeta.title` (a descrição); subtítulo "subagente de <parentTitle>" em `textSecondary`; sem o botão de git; a bússola segue o workspace do agente pai, como no chat do agente. Tocar no título não faz nada.
- **Topo da lista**, quando a página chega ao começo do arquivo (`hasMore == false`): aviso centralizado "<tipo> · <hora de startedAt> · <modelo abreviado>" (ex.: "general-purpose · 13:52 · opus-5-5"); um campo que falta sai do texto.
- `task`: card "Tarefa" (fundo `toolCard`), com o ícone de subagente e "Tarefa" em `textSecondary`, o texto em até 4 linhas e "Ver tarefa completa" com chevron, que expande o texto inteiro.
- A lista segue o chat; um `subagent` aninhado abre o transcript dele.
- **Pílula de estado** no lugar do composer (`glassComposer`): "Rodando · só leitura" com o giro, "Concluído · só leitura" com ✓, "Falhou · só leitura" com ✗ em `error`, "Parado · só leitura" com ■. Sem linha de status nem botão de parar.
- **Fim**: em `completed`, o rodapé "Concluído em <durationMs> · N ferramentas" em itálico `textSecondary`, no fim da lista; em `failed`, o `failureReason` como aviso centralizado no fim da lista, no original, em inglês. Quando o último item já é um `notice` com o mesmo texto (a falha de API, cujo `failureReason` é o texto do erro sintético, §3.5.2), o aviso não se repete. Os dois vêm do `ChatMeta.subagent` e mudam com o `chatMeta`.
- No chat de subagente, o `setForeground` vai sem `agentId`, como no chat de sessão arquivada.

**Home com subagentes** (`17-home-subagentes`)
- Com `runningSubagents > 0`, a segunda linha do card começa com o selo "N subagente" / "N subagentes" (ícone de subagente, fundo `badgeOk`, texto `statusOk`, 11 pt semibold), seguido da segunda linha de sempre, quando existe. O selo some quando a contagem zera. A contagem soma os subagentes de `Agent`, os aninhados e os agentes de workflow.
- O agente `idle` com subagente rodando fica em CONCLUÍDOS com o selo (regra das seções, acima).

**Detalhe com subagentes** (`18-detalhe-subagentes`)
- Seção SUBAGENTES logo depois do bloco principal (e do "Abrir terminal", na fase 2): cabeçalho "SUBAGENTES" e, à direita, "N rodando" quando há algum rodando. A folha rola, e Conta e a lista de Host, Modelo, Workspace, Tab e Sessão vêm depois.
- A lista vem de `listSubagents`, pedida ao abrir o Detalhe e de novo a cada `treeChanged` que muda o `runningSubagents` do agente. Sem itens, e numa `ArchivedSession`, a seção não aparece.
- Um cartão com uma linha por item, na ordem do daemon: ícone de estado (giro, ✓, ✗ em `error`, ■), a descrição e, abaixo, "<tipo> · <tempo> · N ferramentas" em `textSecondary` ("<tipo> · falhou · …" com "falhou" em `error`; "<tipo> · parado · …"), sem tokens, e o chevron. Um item com `parentAgentId` fica recuado. Em `running`, o tempo conta desde `startedAt`, atualizado a cada segundo.
- Tocar numa linha fecha a folha e abre o transcript do subagente por push.

**Workflow no chat** (`19-chat-workflow` e o estado concluído abaixo dela no mock)
- `workflow`: card `toolCard` com o ícone de workflow, "Workflow" em negrito, o `name` e, à direita, o giro, ✓, ✗ em `error` ou ■.
- **Expandido** (padrão enquanto `running`; tocar no topo do card alterna): borda `toolBorder` e uma caixa `codeInner` com as fases, na ordem:
  - ✓ `completed`, giro `running` (título em negrito), ✗ `failed` em `error` e ○ `pending`, com a contagem à direita: "N agente(s)" na fase concluída ou com falha, "X de N agentes" (concluídos de iniciados) na que roda e "pendente" na pendente;
  - sob a fase `running`, o `detail` em itálico `textSecondary` e os agentes dela: giro ou ✓, o `label` e, rodando, a ferramenta atual (nome em `textPrimary` e resumo); concluído, o tempo. As outras fases mostram só a contagem;
  - rodapé do card, em `textSecondary`: "<tempo> • N agentes • N ferramentas", com o tempo desde `startedAt` enquanto roda.
- **Recolhido** (padrão no fim): uma linha "Workflow <name> · N agentes" com o estado à direita.
- Tocar num agente abre o transcript dele (`ChatTarget.subagent` com o `sessionId` do chat e o `agentId` do agente).

### §6.4 Voz (1b)

- `SpeechAnalyzer` + `SpeechTranscriber` com locale `pt-BR`, on-device.
- Antes de habilitar o microfone, conferir `SpeechTranscriber.supportedLocale(equivalentTo:)` e baixar o modelo via `AssetInventory` se preciso: com `AssetInventory.status(forModules:)` abaixo de `.installed`, `assetInstallationRequest(supporting:)` + `downloadAndInstall()`, com o progresso no composer (S6: no Mac, `.supported` aparece mesmo com o modelo já presente, e a requisição devolve `nil` quando não há nada a baixar).
- Preset `.progressiveTranscription` (resultados voláteis e rápidos). Áudio do `AVAudioEngine` convertido para `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` (16 kHz mono Int16 no Mac) e entregue por `start(inputSequence:)`; `finalizeAndFinishThroughEndOfInput()` ao parar.
- Toque no microfone inicia e toque de novo para. O texto parcial aparece no campo em `textSecondary` e o final substitui o parcial. Nada é enviado sozinho.

### §6.5 Imagem (1a-core)

- O `+` do composer expandido abre um menu próprio (vidro `glassComposer`, medidas do menu da tela `09-menu-slash`) com três origens: "Fotos" (`PhotosPicker`, várias de uma vez, na ordem de seleção), "Câmera" (`UIImagePickerController`; some quando não há câmera) e "Colar imagem" (`UIPasteboard.general.images`, habilitado só com `hasImages`; a leitura mostra o aviso "Permitir colar" do iOS, a não ser que o João libere em Ajustes › Mocha › Colar de Outros Apps).
- Até 5 imagens por prompt. Cada uma é reduzida para no máximo 2.048 px no lado maior e vira JPEG com qualidade 0,85, mantendo a orientação.
- As imagens anexadas aparecem como miniaturas quadradas numa faixa acima do campo, cada uma com um "x" para remover. Com imagem anexada, enviar fica habilitado mesmo sem texto.
- Ao enviar: cada imagem vai por `POST /v1/upload` (§5.5), em sequência, com `Authorization: Bearer <deviceToken>` e a base `https://<host do pareamento>`. Depois de todos os uploads, o app manda um `sendPrompt` com o texto do campo seguido de uma linha `[imagem: <path>]` por imagem, na ordem das miniaturas. O Claude Code lê a imagem pelo caminho.
- Se um upload falhar, nada é enviado: o texto e as miniaturas ficam no composer e o erro aparece como na falha de `sendPrompt`.
- A bolha do usuário (pendente e definitiva) mostra o texto sem os marcadores e uma linha "📎 1 imagem" ou "📎 N imagens". O daemon tira os marcadores do texto pela regra da §3.2.

---

## §7 Push e Live Activity

Validado no S4 (iOS 27, iPhone 14 e simulador). Payloads, headers e medições reais em `docs/spikes/S4.md`.

### §7.1 Alertas (1a-final)

- **APNs**: HTTP/2 via uma `URLSession` do daemon, reaproveitada entre envios (o `URLSession` negocia `h2` sozinho), para `api.sandbox.push.apple.com` ou `api.push.apple.com`, conforme o `env` do token do aparelho. Referência medida com conexão nova a cada envio: resposta em 372–824 ms (mediana 465 ms); alerta com o app aberto em 0,5–1,0 s.
- **Permissão e token no app**: a permissão (`.alert`, `.sound`, `.badge`) é pedida na primeira conexão real com o Mac, nunca no `-demo`. O app chama `registerForRemoteNotifications` a cada launch e guarda o último token no `UserDefaults`; o `hello` leva esse token quando o `env` é o mesmo, e um token que chega depois do `hello` vai no `hello` seguinte. Com o app aberto, o `willPresent` sempre mostra o banner: quem suprime é o daemon, pelo `setForeground`.
- **Ambiente do token**: o app manda `env` junto com cada token (`hello.apns`, `registerLiveActivity`). Ele lê `Entitlements.aps-environment` do `embedded.mobileprovision` do próprio bundle (plist dentro do CMS, entre `<?xml` e `</plist>`): `development` → `sandbox`, `production` → `production`. Sem o arquivo (TestFlight, App Store) → `production`. No simulador → `sandbox`.
- **Chave**: a `.p8` Team Scoped `<KEY_ID>` vale **só no sandbox** (produção responde `403 BadEnvironmentKeyInToken`). Build de TestFlight exige uma chave de produção antes.
- **JWT**: ES256 com a `.p8` (CryptoKit `P256.Signing.PrivateKey(pemRepresentation:)`). Header `{"alg":"ES256","kid":"<KeyID>"}`, claims `{"iss":"<TeamID>","iat":<segundos Unix>}`, base64url sem padding. A assinatura usa `signature.rawRepresentation` (r‖s, 64 bytes), **não DER**. O token é reutilizado e renovado a cada 40 min (a Apple rejeita renovação abaixo de 20 min e token acima de 60 min), e também na hora em `403 ExpiredProviderToken`.
- **Headers**:
  - `apns-topic: com.example.mocha`, `apns-push-type: alert`, `apns-priority: 10`;
  - `apns-id`: UUID em minúsculas, gerado pelo daemon e registrado no log;
  - `apns-collapse-id` = `agentId` (≤ 64 bytes);
  - `apns-expiration`: agora + 1 h para turno concluído e agora + 10 min para "precisa de você" (o hook segura no máximo 590 s).
- **Tipos**:
  - Turno concluído (`Stop`): título "Claude terminou · <workspace>", corpo com os primeiros 180 caracteres de `last_assistant_message` sem markdown (`PlainText.preview(fromMarkdown:)`, §3.2.2). `thread-id` = `agentId`; `category` `TURN_DONE`.
  - Agente precisa de você: disparado pelo `PermissionRequest` (§8), na hora. O `blocked` do Herdr sem pedido (ex.: diálogo de confiança da pasta) e o `Notification` `permission_prompt` são sinais secundários. Título "Claude precisa de você · <workspace>", corpo com o `summary` do pedido ou com `questions[0].question`. `interruption-level: time-sensitive`; `category` `NEEDS_INPUT` (1a-final, sem ações) e `PERMISSION`/`QUESTION` (1b, com ações).
- **Supressão**: nenhum alerta para um aparelho cujo cliente está conectado com `setForeground{agentId: X, isActive: true}` quando o alerta é do agente X. Alertas de turno concluído respeitam `preferences.turnDoneAlerts` do aparelho; os de "precisa de você" sempre saem.
- **Deduplicação**: um alerta de "precisa de você" por pedido, contado por `agentId`. Enquanto a sessão tiver pedido pendente (1b), e até 10 s depois do último alerta de "precisa de você" do agente, o `blocked` do Herdr e o `Notification` `permission_prompt` desse agente não geram outro alerta. O `permission_prompt` chega ~6 s depois do diálogo. O `blocked` do Herdr só alerta na transição para `blocked`, só em agente Claude e depois de 1 s ainda `blocked`, para o `PermissionRequest` do mesmo diálogo chegar antes. Os outros tipos de `Notification` não geram alerta. Os sinais secundários usam um corpo fixo em português, porque a mensagem do Claude vem em inglês; sem workspace conhecido, o título sai sem " · <workspace>".
- **Payload**: `{"aps":{"alert":{"title","body"},"sound":"default","thread-id","category","interruption-level"?},"agentId":"w17:p1","kind":"turnDone|needsInput","requestId?":"…","sentAt":<ms Unix>}`. O `sentAt` serve para diagnóstico de atraso. Payload ≤ 4 KB.
- **Respostas**:
  - 200 traz `apns-id` e, no sandbox, `apns-unique-id` (consulta no Push Notifications Console);
  - 410 ou `400 BadDeviceToken` removem o token do aparelho;
  - `403 ExpiredProviderToken` renova o JWT e repete uma vez;
  - `403 BadEnvironmentKeyInToken` (a documentação diz `BadEnvironmentKeyIdInToken`; tratar os dois), `InvalidProviderToken` e `TopicDisallowed` são erro de configuração: log e `doctor`, sem retry;
  - 429, 5xx e erro de transporte (sem resposta) seguem com backoff de 1, 2, 4 e 8 s.
- **Tokens**: hexadecimal de tamanho variável (32 bytes o de alerta, 80 bytes os de Live Activity no iPhone, 128 no simulador). Validar só hex com tamanho par.
- **Simulador**: não entrega o token de alerta (`registerForRemoteNotifications` nunca responde). Alertas só se testam no iPhone.

### §7.2 Ações de notificação (1b)

- `PERMISSION`: "Permitir" (`.authenticationRequired`, sem `.foreground`) e "Negar" (`.destructive`). "Negar" manda `deny` com a mensagem padrão (§8.2): o Claude recebe a negação e continua o turno.
- `QUESTION`: "Responder" (`UNTextInputNotificationAction`), só para uma pergunta sem `multiSelect`. Um texto igual a um rótulo vira esse rótulo; qualquer outro texto vai como resposta livre, que o Claude aceita. Com `QUESTION`, o corpo é o texto exato da pergunta (até 2.000 bytes), que o app usa como chave de `answers`. Várias perguntas, `multiSelect` ou uma pergunta maior vão com a categoria `NEEDS_INPUT`, sem ações, e o corpo é a prévia de `questions[0].question`: o toque abre o chat com o card.
- O app, acordado em background, faz `POST /v1/respond` com o token do Keychain. Se o tailnet estiver fora, a ação falha e a notificação local "Não consegui falar com o Mac" aparece.

### §7.3 Live Activity agregada (1b, substituída pela §7.5)

> Desde 2026-09-27 vale a §7.5 (um card que acompanha o último evento). Desta seção continuam valendo: codificação do `content-state`, headers, regras do `pending` e dos campos do `highlight` (limites, orçamentos, `activity` com `toolName` cru), Ações (intents, Face ID só no Permitir), limite de 8 h, tokens e simulador.

- Uma única atividade `MochaAgentsAttributes` (sem atributos estáticos relevantes), definida em `MochaProtocol` sob `#if os(iOS)` (o `ActivityAttributes` não existe no macOS), com `ContentState`:

```swift
public struct ContentState: Codable, Hashable {
    public var working: Int
    public var waiting: Int                 // blocked
    public var highlight: Highlight?        // o mais urgente: blocked > working mais antigo
    public var pending: Pending?            // o pedido pendente mais antigo (§8)
    public var updatedAt: Date
    public struct Highlight: Codable, Hashable {
        public var agentId: String
        public var title: String
        public var workspaceLabel: String
        public var status: String
        public var since: Date
        public var tabTitle: String?        // título da tab do Herdr
        public var model: String?
        public var contextLeftPercent: Int?
        public var preview: String?         // última mensagem do agente, sem markdown
        public var activity: String?        // ferramenta rodando, ex.: "Shell: npm run build"
    }
    public struct Pending: Codable, Hashable {
        public enum Kind: String, Codable, Hashable { case permission, question }
        public var requestId: String
        public var agentId: String
        public var kind: Kind
        public var toolName: String?        // só em permission
        public var text: String
        public var options: [String]        // sempre presente; vazio quando não há resposta inline
    }
}
```

- **`pending`**: o pedido pendente mais antigo entre os agentes; quando existe, o `highlight` é o agente dele. Omitido quando não há pedido.
  - Permissão: `toolName` e `text` = o `summary` do pedido (§3.2.2, ≤ 120 caracteres); `options` vazio.
  - Pergunta que se responde na atividade (uma pergunta, sem `multiSelect`, texto ≤ 1.000 bytes, 1 a 4 opções com rótulos ≤ 60 caracteres, e o `pending` codificado ≤ 3.200 bytes para o payload caber em 4 KB): `text` = o texto exato da pergunta e `options` = os rótulos exatos, na ordem. O app responde com `answers` = `{text: rótulo}`.
  - Outra pergunta: `text` = a prévia de `questions[0].question` (180 caracteres, sem markdown) e `options` vazio.
  - Um `pending` que aparece, some ou troca de `requestId` é atualização de prioridade 10.

- **Codificação**: o sistema decodifica o `content-state` com as estratégias **padrão** do `JSONDecoder`. `Date` é um número em segundos desde 2001-01-01 (`timeIntervalSinceReferenceDate`), nunca ISO-8601 nem `ProtocolDate`. O daemon usa o espelho `LiveActivityContentState` (`MochaDaemonCore/Push`), que codifica as datas assim, com `highlight` omitido quando nulo. Já `timestamp`, `stale-date` e `dismissal-date` do `aps` são **segundos Unix** (1970).
- **Campos do `highlight`** (da árvore, §5.3): `model` e `contextLeftPercent` do `AgentSummary`; `preview` = `PlainText.preview` do texto do `preview` do agente quando o autor é o assistente (180 caracteres); `activity` = "<ferramenta>: <summary>" da `ToolActivity` em andamento (120 caracteres); `prompt` = o `prompt` do `TranscriptMeta` da sessão do agente (§3.2.2; 120 caracteres; em branco, omitido). Com `pending`, `preview`, `activity` e `prompt` são omitidos (o card mostra o pedido), e o orçamento do `pending` (3.200 bytes) continua valendo. O `content-state` codificado tem orçamento de 3.840 bytes: acima disso, o daemon descarta nesta ordem `preview`, `activity`, `prompt`, `model` e `contextLeftPercent`. O `activity` leva o `toolName` cru; o app mostra o nome de exibição da ferramenta.
- **Tela bloqueada** (layout da Live Activity do Moshi, `docs/referencias/moshi/live-activity.jpg`; um card só):
  - topo à esquerda: `tabTitle` (ou `workspaceLabel`) na cor do status do destaque · o modelo em cinza, sem o prefixo `claude-`;
  - topo à direita: a barra de contexto (mesma regra de cor da Home) e o tile do Claude;
  - linha 1, negrito, uma linha: sem `pending`, a `activity` ou a `preview` (ou o `title`); com `pending`, "<Ferramenta> quer <verbo>" ou a pergunta;
  - linha 2, cinza, uma linha: a continuação do texto da linha 1 (ou o comando do pedido);
  - contagem discreta dos outros agentes (ex.: "+2 trabalhando · 1 esperando você") e, com `pending`, os botões das Ações abaixo;
  - no fim, "Tudo pronto" no lugar da linha 1.
- **Dynamic Island**: compacta com o asterisco à esquerda e contagem à direita; mínima com o asterisco colorido pelo estado; expandida com destaque, contagem e botão "Abrir" (deep link, também em `widgetURL`). O `alert` do push-to-start mostra a apresentação expandida sozinha. No simulador, a captura precisa de `xcrun simctl io <udid> screenshot --mask=black`.
- **Ações** (tela bloqueada e Dynamic Island expandida), com `pending`:
  - permissão: o que o agente quer fazer ("Shell quer rodar" + `text`) e os botões "Negar" e "Permitir";
  - pergunta com `options`: a pergunta e um botão por opção;
  - pergunta sem `options`: a prévia e o toque abre o chat com o card (deep link do agente).
  - Os botões são `Button(intent:)` com `LiveActivityIntent`: o sistema roda o intent no processo do app, sem abri-lo, e o app faz `POST /v1/respond` (Bearer, §5.5). "Permitir" tem `authenticationPolicy = .requiresAuthentication` (Face ID); "Negar" e as opções usam o padrão, que roda com o iPhone travado.
  - Depois de uma resposta aceita, o app atualiza a atividade localmente sem o `pending`; a atualização do daemon vem em seguida. Uma resposta recusada (400) ou sem conexão deixa o `pending` e mostra o motivo numa notificação local, como nas ações de notificação (§7.2). Um 404 (o pedido já foi resolvido no Mac ou expirou) tira o `pending` e mostra a notificação local "Esse pedido já foi resolvido no Mac", também na ação de notificação.
- **Headers**: `apns-push-type: liveactivity`, `apns-topic: com.example.mocha.push-type.liveactivity`, `apns-id`. `apns-expiration` e `apns-collapse-id` são aceitos, mas não são necessários.
- **Ciclo de vida**:
  - **Início**: quando algum agente passa a `working` e não há atividade ativa.
    - Com o app em primeiro plano, `Activity.request(attributes:content:pushType: .token)`. O token de update chega por `pushTokenUpdates` em ~1,2 s.
    - Com o app fora, push-to-start com `apns-priority: 10` e o payload `{"aps":{"timestamp","event":"start","content-state","attributes-type":"MochaAgentsAttributes","attributes":{},"alert":{"title","body"},"input-push-token":1}}`. O `alert` é obrigatório. O token vem de `Activity<MochaAgentsAttributes>.pushToStartTokenUpdates` e existe sem permissão de notificação nem atividade aberta.
    - Mesmo depois de o usuário deslizar o app para fora, o sistema o lança em background em ~1 s. O token de update da atividade nova chega por `Activity.activityUpdates` → `pushTokenUpdates` em 2–40 s, com o app em background.
  - **Atualização**: `event: update`, `timestamp` (o sistema ignora push com `timestamp` mais antigo que o último aplicado), `content-state` e `stale-date` = agora + 15 min (a atividade fica `stale` se o Mac parar de atualizar).
    - `apns-priority: 10` em toda mudança que o usuário precisa ver: contagem de `working`/`waiting`, troca do destaque e fim. Medido: 0,6–0,7 s.
    - `apns-priority: 5` só para mudanças que podem esperar ou se perder (ex.: só o título do destaque). Medido com o iPhone em uso: 45 s e 84 s, e uma se perdeu, coalescida pela seguinte.
    - No máximo uma atualização a cada 10 s, sempre com o estado mais recente.
    - Enquanto algum agente está `working`/`blocked` sem mudança, uma atualização de prioridade 5 a cada 10 min renova o `stale-date`, para a atividade não ficar `stale` num turno longo.
  - **Fim**: quando nenhum agente está `working`/`blocked` por 60 s, `event: end` com prioridade 10, o estado final ("Tudo pronto") e `dismissal-date` = agora + 15 min. A atividade some na `dismissal-date`.
  - **Limite de 8 h**: ao completar 7 h 50 min, o daemon encerra e inicia outra com push-to-start.
- **Orçamentos** (`liveactivitiesd`, visto no simulador e reavaliado a cada hora): 10 push-to-starts e ~60 updates de prioridade 10 por hora, por app. Com o limite de 10 s e a regra de prioridade acima, o Mocha fica abaixo disso em uso normal. Se não ficar, a alternativa é `NSSupportsLiveActivitiesFrequentUpdates` no Info.plist.
- **Tokens**:
  - o app observa `Activity<MochaAgentsAttributes>.activityUpdates`, o `pushTokenUpdates` de cada atividade e `pushToStartTokenUpdates` desde o `application(_:didFinishLaunchingWithOptions:)`, porque o push-to-start acorda o app sem cena;
  - guarda os tokens (`Application Support/live-activity-tokens.json`);
  - envia `registerLiveActivity` pelo WebSocket em primeiro plano e por `POST /v1/live-activity` (Bearer) quando foi acordado em background, porque ali não há WebSocket aberto;
  - sem conexão, reenvia na próxima.
- Payload ≤ 4 KB: o título do destaque vai truncado em 60 caracteres (um `start` completo tem ~400 bytes).
- **Simulador**: recebe push-to-start e updates reais do sandbox, mas **não entrega ao app o token de update de uma atividade iniciada por push**. Esse caminho só se testa no iPhone.


### §7.4 Live Activity por agente (1b, substituída pela §7.5)

> Desde 2026-09-27 vale a §7.5. Desta seção continuam valendo: o card (layout, medidas e paleta, sem título de tab), as regras de prioridade e de refresh, os alertas no lugar das notificações, o encaixe do payload em 4 KB e a renovação às 7 h 50 min.

Decisão do João em 2026-09-27, depois de comparar com o Moshi com vários agentes em paralelo: uma atividade por agente Claude, no layout do Moshi (`docs/referencias/moshi/live-activity.jpg`).

- **Tipo**: `MochaAgentAttributes` (`MochaProtocol`, só iOS), atributo estático `agentId`; `attributes-type: "MochaAgentAttributes"` e `attributes: {"agentId": "<id>"}` no push-to-start. `ContentState`: `status`, `title`, `workspaceLabel`, `since`, `model?`, `contextLeftPercent?`, `preview?`, `activity?`, `prompt?`, `pending?` (`requestId`, `kind`, `toolName?`, `text`, `options`) e `updatedAt`, com as mesmas regras de preenchimento, limites e orçamentos da §7.3 (sem contagens nem `agentId` no `pending`).
- **Card** (tela bloqueada e Dynamic Island expandida): o card do WP-I16 sem a linha de contagem. Cabeçalho "<workspaceLabel> · <modelo>": o projeto (workspace do Herdr, ex.: "Core") em peso regular na cor do status e o modelo em cinza claro #D4D4D4, 13 pt, 6 pt entre os itens, ponto #555555; sem título de tab. Sem `pending` (ocupado ou parado): linha 1 = a `preview` (senão a `activity`, senão o `title`); linha 2 = "Você: <prompt>" (senão a continuação da linha 1). Medidas da tela bloqueada, tiradas do print do Moshi em 3x: margens 16 nas laterais, 15 no topo e 16 embaixo; 4 pt do cabeçalho à linha 1 e 2 pt entre as linhas; linha 1 19 pt bold (encolhe até 0,86 antes de cortar), linha 2 15 pt #A9A9A9 (até 0,95). As cores do card são declaradas em Display P3, porque os valores vêm de prints do Moshi (P3); em sRGB o verde e o laranja saem lavados. Paleta do card no tom do Moshi: verde #9AF768, tile #CA7B5D, trilho da barra #463B38, cinza #A9A9A9 (âmbar e vermelho da §6.2); barra de contexto + tile; linha 1/linha 2; botões do `pending`. Compacta, no estilo do Moshi: à esquerda a xícara do Mocha (`cup.and.saucer`) na cor do rótulo do status (verde, âmbar esperando), à direita o tile do provedor (círculo #CA7B5D com o asterisco branco; no Codex, fundo `controlBg` e losango); mínima: o tile. `widgetURL` = deep link do agente. `relevance-score`: `blocked` 100, `working` 50, parado 10.
- **Início**: quando um agente passa a `working` e não tem atividade. App em primeiro plano: o app inicia (`Activity.request` com o `agentId`). Senão, push-to-start com `alert` `{"title": "Claude trabalhando · <rótulo>", "body": "<title>"}`.
- **Limites**: no máximo 5 atividades por aparelho. Cheio: um agente que fica `blocked` encerra a atividade parada mais antiga e ocupa a vaga; senão fica sem atividade. O orçamento de 10 push-to-starts por hora é do app inteiro; esgotado, o agente fica sem atividade. Agente sem atividade recebe as notificações da §7.1.
- **Atualização**: por atividade, no máximo uma a cada 10 s, sempre com o estado mais recente; prioridade 10 em mudança de `status` ou de `pending`, 5 no resto (texto, contexto, modelo); refresh 5 a cada 10 min enquanto `working`/`blocked`; `stale-date` = agora + 15 min.
- **Alertas no lugar das notificações**: para um agente com atividade ativa e token de update conhecido no aparelho, o daemon **não** manda os alertas da §7.1 (turno concluído, precisa de você, sinais secundários). Em vez disso:
  - `pending` novo → update prioridade 10 com `alert` `{"title": "Claude precisa de você · <rótulo>", "body": <texto do pending, até 180 caracteres>, "sound": "default"}`; `blocked` sem pending (sinal secundário) → o mesmo alerta com o corpo "Esperando uma resposta no terminal.";
  - turno concluído (`working` → parado) → update prioridade 10 com o estado parado e, se `preferences.turnDoneAlerts`, `alert` `{"title": "Claude terminou · <rótulo>", "body": <corpo da §7.1>, "sound": "default"}`.
  - Antes do token de update chegar (2–40 s depois de um push-to-start), vale a §7.1.
- **Payload**: start, update e end (com o `alert`) cabem nos 4 KB do APNs. Se não couber, o daemon tira, nesta ordem: `preview`, `activity`, `prompt`, `model`, `contextLeftPercent`, as opções do `pending` (vira a prévia de 180 caracteres) e, por fim, corta `title` e `workspaceLabel` em 20 caracteres.
- **Fim**: 30 min sem `working`/`blocked`, ou o agente some da árvore → `end` prioridade 10 com `dismissal-date` = agora. Renovação às 7 h 50 min: `end` + push-to-start do mesmo agente.
- **Tokens**: o push-to-start é um token do app para o tipo `MochaAgentAttributes`; cada atividade manda o seu token de update com `activityId` e `agentId` no `LiveActivityRegistration` (WS em primeiro plano, `POST /v1/live-activity` em background). O daemon guarda as atividades por aparelho e por agente em `devices.json`.
- **Transição**: o daemon e o widget deixam o tipo agregado nos WPs M17/I17. `MochaAgentsAttributes` fica no protocolo só para o app encerrar, ao abrir, as atividades agregadas que encontrar.

### §7.5 Live Activity follow-up (1b-feed)

Decisão do João em 2026-09-27, depois de usar a §7.4 com vários agentes: uma atividade por agente polui a tela bloqueada, e contagens não agregam. Vale **um card só**, que mostra um agente por vez e acompanha o último evento.

- **Tipo**: `MochaFeedAttributes` (`MochaProtocol`, só iOS), sem atributos estáticos; `attributes-type: "MochaFeedAttributes"` e `attributes: {}` no push-to-start. `ContentState`: `agentId` (o agente em foco) e os campos da `MochaAgentAttributes` (§7.4): `status`, `title`, `workspaceLabel`, `since`, `model?`, `contextLeftPercent?`, `preview?`, `activity?`, `prompt?`, `pending?` (`requestId`, `kind`, `toolName?`, `text`, `options`) e `updatedAt`, com as regras de preenchimento, limites e orçamentos da §7.3. O daemon codifica pelo espelho `LiveActivityContentState` com o `agentId`.
- **Uma atividade por aparelho.** O app, ao abrir, encerra as `MochaAgentAttributes` e as `MochaAgentsAttributes` que achar; os dois tipos ficam no protocolo só para isso.
- **Foco** (o agente que o card mostra), recalculado pelo daemon a cada entrada, entre os agentes Claude da árvore:
  1. com pedido pendente em algum agente: o agente do pedido mais antigo (`createdAt`, depois `id`). O pedido segura o card até ser resolvido;
  2. senão: o agente com o **evento** mais recente. Evento = a `preview` mudou, o `status` efetivo mudou (inclusive o turno concluído) ou o agente ficou `blocked` sem pedido. Empate: o agente em foco continua; depois o menor `agentId`.
  - Mudança só de `activity`, `prompt`, `model`, `contextLeftPercent` ou `title` atualiza o card quando é do agente em foco, e não puxa o foco.
  - Um agente que some da árvore perde o foco; sem nenhum agente, o card mantém o último estado até o fim.
- **Card**: o da §7.4 para o agente em foco, sem contagem de outros agentes. `widgetURL` e o botão "Abrir" = deep link do `agentId` do estado. `relevance-score` pelo `status` do agente em foco. Ajustes de 2026-09-27, pelo Moshi:
  - o cabeçalho e a barra de contexto ficam sempre verdes, com ou sem `pending` e também com o agente `blocked` (decisão do João em 2026-09-27: a troca para âmbar incomoda). Com `pending`, a linha 2 do pedido fica em laranja #EC9B43 (P3), medido no print do Moshi. A xícara da compacta da Dynamic Island continua na cor do status (§7.4);
  - plano (`ExitPlanMode`): linha 1 "Exit plan mode", como no Moshi; linha 2 = o plano corrido, sem markdown e sem quebras (o `summary` do pedido de plano é `PlainText.preview` do `plan` inteiro, 120 caracteres, §8.1);
  - botões na tela bloqueada: 39 pt de altura, 12 pt acima deles, texto 17 pt semibold; "Negar" só texto #D4D4D4, sem fundo; "Permitir"/"Aprovar" em cápsula verde. As opções de pergunta ficam como estão;
  - desfecho: o `ContentState` ganha `outcome?` (`allowed`, `denied` ou `answered`). Sem `pending` e com `outcome`, linha 1 "Aprovado", "Negado" ou "Respondido" e linha 2 "Você: <prompt>". O daemon preenche o `outcome` do agente depois de uma resposta do celular a um pedido dele (`respond`), enquanto a `preview` do agente continua a do momento da resposta e não chega outro pedido. A resposta conta como evento para o foco. O `outcome` é o primeiro campo descartado pelo orçamento de 3.840 bytes. O app, ao limpar o `pending` localmente depois de uma resposta aceita, já põe o `outcome` da escolha;
  - o `prompt` (e a prévia de mensagem do usuário) sai sem as tags `<pasted_content …>` e `</pasted_content>`.
- **Início**: quando algum agente passa a `working`/`blocked` e o aparelho não tem card. App em primeiro plano: `Activity.request` com o foco pelo mesmo critério, calculado no app pela árvore. Senão, push-to-start com `alert` `{"title": "Claude trabalhando · <rótulo>", "body": "<title>"}` do agente em foco.
- **Atualização**: no máximo uma a cada 10 s, sempre com o estado mais recente. Prioridade 10 em troca de foco e em mudança de `status` ou de `pending`; 5 no resto; refresh 5 a cada 10 min enquanto algum agente está `working`/`blocked`; `stale-date` = agora + 15 min.
- **Alertas no lugar das notificações**: enquanto o aparelho tem o card com token de update conhecido, o daemon não manda os alertas da §7.1 de **nenhum** agente. O alerta (texto e regras da §7.4) vai no update que traz o foco para o agente do evento. Um evento de outro agente que não ganha o foco, porque um pedido segura o card, sai como alerta da §7.1. Antes do token chegar, vale a §7.1.
- **Fim**: 30 min sem nenhum agente `working`/`blocked` → `end` prioridade 10 com `dismissal-date` = agora. Renovação às 7 h 50 min: `end` + push-to-start.
- **Tokens**: `registerLiveActivity` sem `agentId`: um token de push-to-start para o tipo e o token de update da atividade com `activityId`. O daemon guarda uma atividade por aparelho em `devices.json`; um registro antigo com `agentId` é ignorado.

---

## §8 Aprovações e perguntas (1b)

Mecanismo validado pelo spike S3 no Claude Code 2.1.283. Payloads, respostas e linhas do tempo reais em `MochaKit/Fixtures/hooks/`.

### §8.1 Mecanismo: `PermissionRequest` segurado

- Todo diálogo em que o Claude espera uma decisão no terminal dispara o hook `PermissionRequest` no mesmo instante em que o diálogo aparece: a aprovação de ferramenta (Bash, Write, Edit, MCP…) **e** o seletor do `AskUserQuestion`. O hook (HTTP, timeout 590 s, §3.3.1) fica pendente no `HookServer` enquanto o diálogo continua respondível no Mac. Vale a primeira resposta, dos dois lados.
- Não há hook `PreToolUse` do Mocha nem fallback por `agent.send_keys`.
- Um agente tem no máximo um pedido pendente. Um subagente (com `agent_id` no payload do hook) conta à parte: o pedido dele não encerra o do agente principal da mesma `session_id`, e vice-versa. Com várias ferramentas na mesma resposta, o Claude mostra um diálogo por vez e só dispara o `PermissionRequest` seguinte depois que o anterior se resolve.
- **Entrada** (`Fixtures/hooks/PermissionRequest.*.json`): `session_id`, `transcript_path`, `cwd`, `prompt_id`, `permission_mode`, `tool_name`, `tool_input` e, só para ferramentas, `permission_suggestions` (ignorado: não corresponde às opções do diálogo). Não traz `tool_use_id`.
- **Criação do `PendingRequest`**:
  - `agentId` vem do header `X-Mocha-Pane`, traduzido depois de `pane_moved` (§3.3.1);
  - com `tool_name == "AskUserQuestion"`, `kind` = `question(questions:)`, de `tool_input.questions`;
  - nos demais, `kind` = `permission(toolName:, summary:, inputJSON:)`, com o `summary` da regra do `toolCall` (§3.2.2) e o `tool_input` truncado em 4.000 caracteres;
  - o daemon guarda o `tool_input` original para montar a resposta.
- Ao criar o pedido, o daemon faz broadcast de `pending` e manda o push time-sensitive (§7.1). O Herdr mostra o agente `blocked` ~0,1–0,3 s depois, também no seletor do AskUserQuestion, mas o status sozinho não identifica o pedido.

### §8.2 Respostas ao hook

Resposta HTTP 200, `Content-Type: application/json` (`Fixtures/hooks/response.*.json`):

| `PendingResponse` | Corpo |
|---|---|
| `allow` (permissão) | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` |
| `allow` (permissão `ExitPlanMode`) | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":<tool_input original>,"updatedPermissions":[{"type":"setMode","mode":"auto","destination":"session"}]}}}`. O `allow` puro não basta para o plano: o Claude ignora e o diálogo continua no terminal (documentação dos hooks, 2026-09-27). O modo `auto` repete a 1ª opção do terminal, decisão do João |
| `deny(reason)` (permissão ou pergunta) | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"<reason, ou 'Negado pelo usuário no iPhone.'>"}}}` |
| `answers(map)` (pergunta) | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":{"questions":<tool_input.questions original>,"answers":{"<question>":"<resposta>"}}}}}` |
| sem decisão | `{}` |

- `allow`: a ferramenta roda na hora, e o terminal mostra "Allowed by PermissionRequest hook".
- `deny`: o Claude recebe a mensagem como `tool_result` com `is_error: true` e **continua o turno**. É diferente do "No" do terminal, que interrompe o turno. O daemon não usa `interrupt: true`.
- `answers`:
  - a chave é o texto exato de `question`;
  - o valor é uma string: o `label` na opção única; os `label`s escolhidos, na ordem das opções, unidos por `", "` no `multiSelect`; o texto digitado, como está, em "Outro" (o Claude não confere contra os rótulos);
  - `questions` volta sem nenhuma alteração;
  - toda pergunta precisa de resposta não vazia. O Claude aceita `answers` incompleto e descarta a pergunta sem resposta em silêncio, então o daemon responde `error{invalidPayload}` a um `respond` incompleto;
  - `allow` numa pergunta e `answers` numa permissão também são `invalidPayload`;
  - nunca mandar lista no lugar da string: o Claude aceita, mas grava crua e o terminal não mostra o resumo.
- `{}` (ou corpo vazio) não decide: o diálogo do terminal segue normal. É a resposta da 1a-final e a de §8.3.

### §8.3 Fim do pedido

O pedido sai do `PendingStore`, com broadcast de `pending`, na primeira destas situações:

1. **Resposta do celular** (`respond` ou `POST /v1/respond`): o daemon responde o hook com o corpo de §8.2, e o diálogo do terminal fecha sozinho. Uma segunda resposta ao mesmo pedido recebe `error{requestNotFound}` (404 no HTTP).
2. **O Claude fecha a conexão do hook**: acontece quando o diálogo é respondido no terminal com "No" ou Esc (o turno é interrompido, sem `Stop`), quando o processo do Claude sai e no timeout do hook.
3. **Resposta pelo terminal com "Yes" ou uma opção**: o Claude **não** fecha a conexão (ela fica aberta até o timeout) e ignora resposta tardia. O daemon percebe pelo primeiro destes sinais e responde `{}` ao hook ainda aberto:
   - o status do pane no Herdr sai de `blocked` depois da criação do pedido (~0,1 s depois da tecla);
   - o transcript ganha o `tool_result` do `tool_use` mais recente com o mesmo nome de ferramenta;
   - chega `PermissionRequest`, `UserPromptSubmit` ou `Stop` da mesma sessão.
4. **Tempo**: aos 580 s, o daemon responde `{}`. O diálogo do terminal continua valendo. Se o daemon não responder, o Claude cancela o hook aos 590 s, com o mesmo efeito.

### §8.4 Teclas do diálogo (referência)

Não usadas pelo daemon. Registradas no S3 (Claude Code 2.1.283) para diagnóstico. Com o diálogo aberto, `agent.prompt` devolve `agent_blocked`, então texto também vai por `agent.send_keys`: uma tecla por caractere, e `space` para espaço.

| Diálogo | Ação | Teclas |
|---|---|---|
| Permissão ("1. Yes" já selecionado) | Permitir uma vez | `enter` |
| Permissão | Negar (interrompe o turno) | `esc`, ou `down`, `down`, `enter` ("3. No") |
| Pergunta de opção única | Opção k | `k` (o dígito seleciona e envia), ou `down` × (k−1) e `enter` |
| Pergunta de opção única | "Outro" | `down` × nº de opções (foca "Type something."), o texto, `enter`. O dígito não foca o campo de texto |
| Pergunta `multiSelect` | Marcar | `space` (ou `enter`) em cada opção, `down` para navegar; "Type something" também é marcável |
| Pergunta `multiSelect` | Concluir | `down` até "Submit" (pergunta única) ou "Next" (várias), `enter` |
| Várias perguntas | Avançar e enviar | Responder uma pergunta avança para a aba seguinte. No fim, a tela "Review your answers" abre com "1. Submit answers" selecionado: `enter` |
| Qualquer pergunta | Cancelar (interrompe o turno) | `esc` |

### §8.5 Estado

- O `PendingStore` mantém os pedidos em memória, no máximo um por sessão e `agent_id`. Reiniciar o daemon descarta os pedidos, e os hooks pendentes caem por conexão fechada: para o Claude isso é um erro não bloqueante, e o diálogo do terminal continua.
- `pendingCount` por agente alimenta a gaveta e o `waiting` da Live Activity.

---

## §9 Terminal e preview web (fases 2, 3 e preview-web)

### §9.1 SSH (fase 2)

- Emulador `SwiftTerm` (UIKit `TerminalView` embrulhado em SwiftUI). SSH com `Citadel` (swift-nio-ssh).
- **Chave**: P-256 criada na Secure Enclave (`SecureEnclave.P256.Signing.PrivateKey`, com `.biometryCurrentSet`), usada como `ecdsa-sha2-nistp256` via `NIOSSHPrivateKey(secureEnclaveP256Key:)`. Se o Citadel não expuser isso, um delegate de autenticação próprio.
- **Autenticação** (spike W1): a chave fica com `[.privateKeyUsage, .biometryCurrentSet]` e `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, e o `dataRepresentation` vai no Keychain. O Citadel 0.12.1 não aceita chave da Secure Enclave nos métodos prontos: a autenticação usa `SSHAuthenticationMethod.custom` com um `NIOSSHClientUserAuthenticationDelegate` próprio, que oferece `NIOSSHPrivateKey(secureEnclaveP256Key:)` uma única vez (sem novas ofertas nem novos Face ID depois de uma recusa) e completa a promise com `assumeIsolated()`. A chave do host é conferida por `SSHHostKeyValidator.custom`. `SSHClient.connect(…, reconnect: .never, connectTimeout: .seconds(10))`: quem reconecta é o app.
- A chave é criada com `.biometryCurrentSet`, então cada assinatura (cada conexão nova, inclusive ao voltar do background) pede Face ID; o `App/Info.plist` tem `NSFaceIDUsageDescription`. No simulador, só em Debug, a chave é P-256 em software.
- A chave pública aparece em Ajustes para colar em `~/.ssh/authorized_keys` do Mac. O Remote Login precisa estar ligado no Mac (bloqueio B5).
- **Host**: o mesmo nome MagicDNS, porta 22, dentro do tailnet. O usuário é o `HostInfo.sshUser` do `helloOk`, e o `SSHHostKeyValidator.custom` só aceita a chave apresentada pelo servidor se ela for igual a uma das `HostInfo.sshHostKeys` (sem confiar na primeira conexão). Sem `sshHostKeys` (daemon antigo ou lista vazia), a conexão SSH é recusada com a mensagem "Atualize o mochad no Mac".
- **Sessão**: `herdr agent attach <paneId>` pelo "Abrir terminal" do Detalhe do agente, ou `herdr` puro por uma tab de shell da gaveta (§6.3). Ao reconectar, reanexa no mesmo alvo.
- **Barra de teclas** (`terminal.png`): Ctrl (trava), Esc, Tab, setas (joystick), prefixo do Herdr (`ctrl+space`), colar, histórico e recolher teclado. Cores em §6.2.

### §9.2 Mosh (fase 3)

- Build do mosh para iOS a partir de `blinksh/build-mosh` + `blinksh/mosh` (GPLv3; aceitável num app que não é distribuído), com libprotobuf.
- Bootstrap: `mosh-server new` via SSH (Citadel), com a chave e a porta devolvidas ligadas ao `mosh-client` embutido. O Mac precisa do `mosh-server` (`brew install mosh`).
- O transporte é trocável na mesma tela de terminal (SSH ou Mosh).

### §9.3 Preview web (fase preview-web)

- **Descoberta** (`mochad`, `WebServerScanner` em `MochaDaemonCore/WebServers/`), a cada `listWebServers`:
  - lista os PIDs do usuário do daemon (`proc_listpids` + `proc_pidinfo(PROC_PIDTBSDINFO)`, mesmo `uid`) e, de cada um, os sockets TCP em `LISTEN` (`PROC_PIDLISTFDS` + `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`), sem subprocesso;
  - descarta as portas do próprio `mochad` (hooks e gateway) e os processos com executável em `/System/`, `/usr/libexec/` ou `/Applications/*.app/`;
  - uma porta aparece uma vez (a primeira pelo menor PID);
  - sonda cada porta com `GET /` em `http://localhost:<porta>` (o `localhost` cobre servidores só em `::1`, como o Vite no Node recente), timeout de 800 ms, todas em paralelo; fica quem responde HTTP com `Content-Type` `text/html`, seguindo até 3 redirecionamentos para o mesmo host;
  - `title` = o `<title>` do HTML (primeiros 64 KB, entidades básicas decodificadas, espaços colapsados); `directory` = o cwd do processo (`PROC_PIDVNODEPATHINFO`); `process` = o nome do processo (`proc_name`);
  - responde em até 2 s; porta que não respondeu a tempo fica de fora;
  - `workspaceId` = o workspace do Herdr cuja raiz (o `checkout_path` da worktree ou o cwd do pane da tab ativa) é o prefixo mais longo do `directory`; no empate, vence o `checkout_path`. `/` e a home nunca são raiz. Sem raiz que contenha o diretório, o campo fica ausente.
- **Túnel** (app): uma conexão SSH por aparelho (§9.1: host MagicDNS, porta 22, chave da Secure Enclave), compartilhada com o terminal. Para cada preview, o `PortForwarder` abre um `NWListener` em `127.0.0.1` com porta efêmera no iPhone; cada conexão aceita vira um canal `direct-tcpip` do Citadel para `localhost:<porta do Mac>` (o `sshd` tenta IPv4 e IPv6), com bytes copiados nos dois sentidos até um lado fechar: o canal sai de `SSHClient.createDirectTCPIPChannel(using: .init(targetHost: "localhost", targetPort:, originatorAddress:))`, embrulhado no `initialize` num `NIOAsyncChannel<ByteBuffer, ByteBuffer>` com `isOutboundHalfClosureEnabled`; o `NWListener` usa `requiredLocalEndpoint` em `.ipv4(.loopback)`, sem `acceptLocalOnly` (com ele, o simulador reseta toda conexão aceita); a ponte copia com dois filhos num task group e propaga o fim de cada lado (`outbound.finish()` e `.finalMessage`). O `TunnelPortForwarder` (actor em `MochaClient/Tunnel/`, sem depender do Citadel) recebe um `TunnelChannelOpener` (`@Sendable (Int) async throws -> any TunnelChannel`), trocado por um falso nos testes; no app, o `SSHTunnelChannel` adapta o `NIOAsyncChannel`. O `stop()` é `async` e espera o listener cancelar, para reabrir na mesma porta ao voltar do background. O `WKWebView` carrega `http://127.0.0.1:<porta local>/`, e assim HMR, WebSocket e caminhos absolutos funcionam sem reescrita.
- **Ciclo de vida**: o listener fecha quando o Navegador fecha. Ao voltar do background, o app reabre a conexão SSH e o listener na mesma porta local, se livre, e recarrega a página.
- **ATS**: o `App/Info.plist` tem `NSAppTransportSecurity › NSAllowsLocalNetworking`, que libera só `127.0.0.1`/`localhost` em HTTP.
- **Segurança**: nada abre no Mac além do SSH que já existe (§9.1); o daemon só lê processos e sonda `localhost`. O túnel só chega a portas de loopback do Mac e exige a chave autorizada em `~/.ssh/authorized_keys` (bloqueio B5).

---

## §10 Segurança

- O daemon só escuta em `127.0.0.1` (hooks em 47420, gateway em 47421). A exposição ao iPhone é só pelo `tailscale serve` (tailnet privada, TLS). Os headers `Tailscale-User-*` e `X-Forwarded-*` que o Serve acrescenta não autenticam nada, porque um processo local pode conectar direto na porta e forjá-los: a autenticação é sempre o token do aparelho (§4.5).
- O canal local (§4.8) fica num socket Unix 0600, sem segredo e fora do Serve. O `hookSecret` serve só aos hooks.
- O token de aparelho fica no Keychain do iPhone. O daemon guarda só o SHA-256 dele.
- O código de pareamento é de uso único e expira em 10 min.
- O `HookServer` exige `X-Mocha-Hook-Secret` e escuta só em `127.0.0.1`.
- A `.p8` do APNs fica no Keychain do Mac e nunca vai para disco fora dele nem para o log.
- Uploads são aceitos só de aparelho autenticado, com limite de 20 MB, e o nome é gerado pelo daemon (UUID). O caminho enviado pelo cliente é ignorado.
- `sendPrompt` e `slash` não viram comandos de shell no Mac: vão só como texto para o agente via Herdr.

---

## §11 Dependências

| Dependência | Onde | Licença | Fase |
|---|---|---|---|
| Frameworks da Apple (SwiftUI, Network, CryptoKit, Security, ActivityKit, UserNotifications, Speech, VisionKit, PhotosUI, CoreImage) | app e daemon | — | todas |
| `swift-markdown` (github.com/swiftlang/swift-markdown), `exactVersion: 0.9.0` | app (`Markdown/`) | Apache-2.0 | 1a-core |
| `swift-cmark` e `swift-docc-plugin`, transitivas do `swift-markdown` | app | BSD-2 / Apache-2.0 | 1a-core |
| JetBrains Mono 2.304 (github.com/JetBrains/JetBrainsMono), pesos Regular, Italic, Bold e BoldItalic em `App/Resources/Fonts/`, com a `OFL.txt`. Motivo: é a fonte mono dos prints (§6.2) | app (`DesignSystem/`) | OFL-1.1 | 1a-core |
| Swift Testing | testes | — | todas |
| `SwiftTerm` (github.com/migueldeicaza/SwiftTerm) | app | MIT | 2 |
| `Citadel` (github.com/orlandos-nl/Citadel), `exactVersion: 0.12.1` | app | MIT | preview-web e 2 |
| `swift-nio-ssh` do fork `Wellz26/swift-nio-ssh` 0.3.x, transitiva do `Citadel` 0.12.1 (não é o pacote da Apple). Traz `NIOSSHPrivateKey(secureEnclaveP256Key:)`, usada na chave da §9.1 | app | Apache-2.0 | preview-web e 2 |
| `blinksh/mosh` + protobuf | app | GPLv3 / BSD | 3 |

Não há outras dependências. Uma nova precisa entrar nesta tabela, com licença e motivo, antes de ser adicionada.

O markdown do chat é renderizado por um renderizador próprio sobre a AST do `swift-markdown`, porque o `AttributedString(markdown:)` não renderiza blocos (listas, código, citações) e o visual precisa bater com os prints. Suporte mínimo: parágrafos, negrito, itálico, código inline, blocos de código (fundo `toolCard`, rolagem horizontal), listas numeradas e com marcadores (aninhadas), títulos, citações, links e tabelas simples (rolagem horizontal).

---

## §12 Riscos

| Risco | Mitigação |
|---|---|
| O formato do JSONL do Claude muda numa atualização | Parser tolerante (§3.2.2), fixtures reais versionadas, e o `doctor` mostra a versão do Claude e a taxa de linhas descartadas. O Claude Code se atualiza sozinho (no S1 passou de 2.1.282 para 2.1.283 durante o uso); o `doctor` avisa quando a versão das linhas é maior que a última validada |
| API do Herdr muda (protocolo ≠ 22) | O `HerdrClient` confere a versão do protocolo no connect; o `doctor` avisa; fixtures em `Fixtures/herdr/` |
| O hook `PermissionRequest` não roda em paralelo com o diálogo na versão instalada | Confirmado em paralelo na 2.1.283 (S3). Uma versão nova pode mudar isso: o `doctor` avisa versão acima da validada, e `MochaKit/Fixtures/hooks/` documenta o contrato |
| A resposta pelo terminal com "Yes" não fecha o hook `PermissionRequest` | Detecção pelo status do Herdr, pelo transcript e pelos hooks da sessão, e `{}` ao hook (§8.3) |
| Hook `http` com o daemon parado mostra erro no terminal a cada turno | Hooks de comando com `\|\| true`, exceto o `PermissionRequest`, cuja falha é silenciosa (§3.3.1) |
| Tailscale fora no iPhone | Bloqueio B6 (VPN On Demand); o app mostra "Sem conexão com o Mac" e as ações de notificação avisam a falha |
| `moshi-hook` competindo pelos hooks | Detecção no `doctor`/`install-hooks` e bloqueio B7 |
| Arquivos de transcript muito grandes | Índice de offsets, leitura pelo fim, prévias truncadas (§3.2.3) |
| O Herdr ignora parâmetros desconhecidos, e o alvo omitido cai no pane focado do João | Tipos de parâmetro com os nomes exatos de `herdr-api.schema.json`, alvo sempre explícito, teste de contrato contra o schema; o daemon não chama métodos de foco, split, layout nem escrita de workspace |
| Troca de sessão (`/clear`) sem evento do Herdr | Detecção por `pane_updated`, `agent.get` e reconciliação (§3.1.3); hook `SessionStart` a partir da 1a-final |
| Build do Xcode e perfil com push expiram | Perfil de desenvolvimento de ~1 ano; `doctor` do app em Ajustes mostra a validade quando disponível |
| A extensão do Tailscale standalone não abre socket Unix fora do sandbox | Gateway em TCP `127.0.0.1:47421` (S5); o `doctor` acusa alvo `unix:` no Serve |
| O primeiro HTTPS do nó segura o TLS por ~1 min enquanto o certificado é emitido | `serve-setup --apply` aquece o health com limite de 90 s; o `doctor` separa timeout de TLS de 502 |
| Atualização de Live Activity com prioridade 5 atrasa minutos ou se perde | Prioridade 10 em toda mudança visível, limite de 1 update a cada 10 s (§7.3); `stale-date` marca a atividade como desatualizada |
| O Keychain pede autorização a cada build novo do `mochad` | Binário sempre assinado com a identidade do time e identificador fixo (§4.3); o `doctor` confere a assinatura |
| A chave APNs atual só vale no sandbox; TestFlight usa produção | Criar ou habilitar uma chave de produção antes do primeiro build de TestFlight; `BadEnvironmentKeyInToken` aparece no `doctor` (§7.1) |
| O cache de uso é privado do plugin `herdr-agent-usage` e pode mudar de formato ou deixar de existir | Leitura tolerante de só quatro campos (§3.4), fixture sintética versionada, contexto com reserva pelo transcript, pílula de uso escondida sem cache e item Uso no `doctor` |
| O plano e a conta vêm de chaves de `~/.claude.json` inferidas, sem leitura real pelos agentes | Só `organizationRateLimitTier` e `emailAddress`, com fallback para "Claude" sem plano; conferência do João no WP-X1 |
| Os arquivos de subagentes e workflows (`meta.json`, `journal.jsonl`, `wf_*.json`) e a notificação de tarefa são internos do Claude Code e mudam sem aviso | Estado derivado de mais de um sinal, com o mais recente valendo (§3.5.2), leitura tolerante, fases com reserva pelo journal (§3.5.3), fixtures redigidas versionadas e o aviso de versão do `doctor` (§3.2.2) |
| A janela de contexto do modelo é inferida pelo nome | Primeiro o `used_percent` do plugin, que vem do próprio Claude Code; a tabela de `ContextWindow` é só reserva |

---

## §13 Codex CLI e desktop

Esta fase acrescenta Codex sem alterar os contratos específicos do Claude das §§3–8. O foco é o Codex CLI em panes do Herdr; o desktop é uma etapa posterior, somente de leitura. O spike S7 é um bloqueio técnico: se dois clientes não puderem observar e decidir a mesma thread pelo App Server, a implementação de controle para no relatório do spike, sem fallback por teclas no terminal.

### §13.1 CLI e fonte de dados

- O `mochad` usa o Codex App Server local por socket Unix. Ele mesmo sobe o App Server como processo filho (`codex app-server --listen unix://~/Library/Application Support/Mocha/codex.sock`) e o reinicia 5 s depois de uma queda. O executável vem de `/opt/homebrew/bin`, `/usr/local/bin` ou `~/.local/bin`; sem ele, as tabs Codex ficam indisponíveis e o `doctor` avisa. A tab Codex criada pelo Mocha roda `codex --remote unix://<socket>` no Herdr. O pane continua sendo a identidade de agente da Home; a thread do App Server é a identidade da conversa. O observador envia `thread/resume` para receber eventos e pedidos pendentes; `thread/list` sozinho não o inscreve. A associação pane–thread deve ser verificável pelo daemon, pois o TUI remoto apareceu com `source=vscode` no S7 e `source` não identifica o pane.
- Associação pane–thread (lab de 2026-09-28): com `--remote`, os hooks rodam no App Server e o Herdr não recebe `agent_session`; o `herdr agent start` expira esperando prontidão. Por isso, ao criar a tab, o daemon anota (pane, cwd, instante) e liga o pane ao próximo `thread/started` global com o mesmo cwd normalizado, numa janela de 120 s; panes no mesmo cwd são atendidos em ordem. No `/new`, com um único pane Codex naquele cwd, o pane passa para a thread nova.
- A thread nova não tem rollout antes do primeiro turno: `thread/resume` falha com "no rollout found", mas `turn/start` funciona. O daemon repete o resume a cada 2 s até a inscrição passar. Criar a thread pelo daemon (`thread/start`) e abrir o TUI com `codex resume --remote … <id>` falha pelo mesmo motivo.
- O status das tabs Codex vem do App Server (`thread/status/changed`, `turn/started`, `turn/completed`; pedido pendente é `blocked`), não do Herdr. Os pedidos Codex usam o prefixo `codex:` no `requestId` interno para o `respond` rotear pelo provedor.
- `thread/list`, `thread/read` e as notificações do App Server alimentam histórico, estado, itens do chat e subagentes. `turn/start` ou `turn/steer`, `turn/interrupt` e as respostas aos pedidos do servidor fazem as ações do iPhone. O daemon não lê o JSONL do Codex como contrato e não digita aprovações no pane.
- Um CLI já aberto fora do App Server gerenciado pode ser mostrado com os dados disponíveis, mas só recebe ações depois que a ligação pane–thread e a capacidade de controle forem verificadas. O Mocha não reinicia nem migra a sessão automaticamente.
- A perda da conexão marca o agente como indisponível para ações. Na reconexão, o daemon relê a thread e reconcilia itens por ID; não reenvia prompts nem decisões cuja confirmação se perdeu. O S7 validou reconexão ociosa sem duplicar itens; queda com operação em trânsito fica no WP-XC. A versão `codex-cli 0.157.1` validada em S7 entra no `doctor`. O daemon não tenta aplicar novos overrides de permissão ao retomar uma thread remota, pois o S7 recebeu `Permission overrides are not supported when resuming a remote task`.
- O uso da conta vem de `account/rateLimits/read`; o uso da thread, de `thread/tokenUsage/updated` quando houver. A UI usa duração e reset devolvidos pela API, sem fixar janelas de 5 h e 7 dias.

### §13.2 Protocolo e apresentação

- O protocolo app–daemon passa a v2, com identificação de provedor para sessões e arquivos. Registros antigos sem provedor são Claude. `newAgentTab` aceita `kind` Claude ou Codex; o campo omitido significa Claude para migração dos dados e fixtures. IDs de agente do Herdr permanecem opacos.
- `AgentSummary.controlAvailable` indica se uma tab Codex tem ligação de controle verificada; `false` desabilita envio e interrupção. A ausência do campo mantém o comportamento Claude já existente. Sessões Codex arquivadas e threads desktop usam alvo de chat distinto do alvo Claude, ainda que os IDs coincidam.
- `openChat`, `sendPrompt`, `interrupt` e `respond` usam a mesma experiência visual dos agentes Claude, com roteamento pelo provedor no daemon. Só pedidos ainda pendentes podem ser respondidos; a primeira decisão entre terminal e iPhone vence. A origem do pedido e sua thread entram na chave interna do `PendingStore` para não confundir sessões dos dois provedores. O ID do pedido JSON-RPC é escopado à conexão que o recebeu; a resposta deve sair nessa conexão. Em Codex Default, `request_user_input` é recusado pelo App Server 0.157.1; perguntas estruturadas aparecem apenas nos modos em que a API as disponibilizar (Plan validado no S7). Essa limitação não bloqueia chat e aprovações no Default (decisão do João em 2026-09-27).
- `PendingQuestion.id` é opcional e guarda o ID da pergunta do App Server. Respostas Codex usam esse ID como chave; perguntas Claude sem ID continuam usando o texto da pergunta. Isso evita confundir duas perguntas Codex com texto igual.
- Home, gaveta, Detalhe, chat, Uso, notificações e Live Activity mostram o provedor e usam o nome “Codex” no texto relativo a agentes Codex. O seletor de nova tab oferece Claude como opção inicial e Codex. UI nova ou alterada segue o mock da §6.2, que deve ganhar os estados Codex antes da implementação da tela.
- O app e o daemon devem informar incompatibilidade de versão em vez de interpretar mensagens v1 como v2. O modo demo recebe fixtures dos dois provedores.

### §13.3 Desktop, após o aceite do CLI

- O desktop fornece `thread/list` e leitura paginada pelo App Server sem `thread/resume`, envio, interrupção ou resposta. A Home mostra até 20 conversas recentes; a gaveta pagina o histórico inteiro. As conversas desktop não se associam a panes Herdr.
- Uma conexão separada pode devolver `notLoaded` para uma conversa ativa no desktop; nesse caso o Mocha mostra estado desconhecido. Hooks `SessionStart`, `UserPromptSubmit`, `Stop`, `PermissionRequest`, `Interrupt` e `SessionEnd` podem complementar estado e alertas, mas sua configuração exata deve ser revista pelo João antes da instalação real. A leitura não depende dos hooks.
