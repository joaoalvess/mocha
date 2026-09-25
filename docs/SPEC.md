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

O **modo agente** (chat) é a tela principal. O terminal é secundário e entra só na fase 2.

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
| Gaveta de workspaces, tabs e agentes do Herdr, ao vivo (inclui worktrees criados pelos agentes) | 1a-core |
| Chat do agente: histórico paginado, atualização ao vivo, markdown, cards de ferramenta | 1a-core |
| Enviar prompt, interromper (Esc) | 1a-core |
| Daemon como LaunchAgent, `doctor` | 1a-core |
| Push de turno concluído e de agente bloqueado, com deep link | 1a-final |
| Slash commands rápidos | 1a-final |
| Inbox de aprovações e perguntas; ações na notificação | 1b |
| Live Activity agregada / Dynamic Island | 1b |
| Ditado por voz on-device | 1b |
| Anexar imagem ao prompt | 1b |
| Abrir nova tab com Claude num workspace existente | 1b |
| Terminal SSH (`herdr agent attach`) | 2 |
| Transporte Mosh no terminal | 3 |

### §1.4 Fora de escopo

Nada disto entra em nenhuma fase acima: outros agentes (Codex, Antigravity e demais), vários hosts, diff viewer, preview de dev server, temas, fontes e atalhos configuráveis, Apple Watch, iPad, criação de worktree pelo app, relay em nuvem, publicação na App Store, Android.

### §1.5 Glossário

- **Workspace**: workspace do Herdr (`workspace_id`, ex.: `w17`, `w1A`; ids opacos, nunca reaproveitados). Pode ser um worktree git ligado a outro workspace do mesmo repositório.
- **Tab**: tab do Herdr (`tab_id`, ex.: `w17:t1`).
- **Pane**: pane do Herdr (`pane_id`, ex.: `w17:p1`). Um pane movido para outro workspace ganha id novo (evento `pane_moved`), e o agente muda de `AgentID`.
- **Agente**: um pane onde o Herdr detectou o Claude Code. No protocolo, a identidade do agente é o `pane_id` (`AgentID`).
- **Sessão**: sessão do Claude Code (`session_id`, UUID). Um agente troca de sessão com `/clear`, que cria um arquivo de transcript novo; `/compact` mantém a sessão e o arquivo.
- **Turno**: do prompt do usuário até o Claude parar (hook `Stop`).
- **Pedido pendente**: aprovação de ferramenta ou pergunta (AskUserQuestion) esperando resposta (1b).

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
│ tailscale serve  ──►  gateway (socket Unix 0600 ou 127.0.0.1)      │
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
      MochaClient/                cliente WS do app: ConnectionManager, reconexão, TokenStore (§6.1)
      MochaDemo/                  ServerConnection em processo com dados de demonstração (Resources/*.json)
      MochaTranscript/            parser do JSONL do Claude Code → ChatItem (§3.2)
      MochaHerdr/                 cliente do socket do Herdr (§3.1)
      MochaDaemonCore/            serviços do daemon (§4)
      mochad/                     executável (CLI + run loop)
      MochaTestSupport/           fakes e helpers para os testes do daemon
    Tests/
      MochaProtocolTests/  MochaDemoTests/  MochaClientTests/  MochaTranscriptTests/  MochaHerdrTests/  MochaDaemonCoreTests/
    Fixtures/
      transcripts/  herdr/  hooks/  protocol/
  scripts/
    bootstrap.sh                  xcodegen generate
    test.sh                       swift test --package-path MochaKit
    build-app.sh                  xcodebuild do app para o simulador
    build-device.sh               xcodebuild assinado do app para o iPhone (-allowProvisioningUpdates)
    build-daemon.sh               swift build -c release --product mochad
    run-daemon.sh                 roda o mochad em primeiro plano com log no stdout
  docs/  prompts/
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
| `MochaTestSupport` | macOS | `MochaProtocol`, `MochaDaemonCore` |
| `MochaClientTests` | macOS | `MochaClient`, `MochaDaemonCore` (usa o `HttpServer` real como servidor WS de teste) |
| `MochaDemoTests` | macOS | `MochaDemo` |

Os test targets acham `MochaKit/Fixtures/` por um helper `Fixtures` baseado em `#filePath`, porque o SwiftPM não aceita recurso fora do diretório do target.

O app (`project.yml`) depende de `MochaProtocol`, `MochaClient`, `MochaDemo` e `swift-markdown`. A extensão `MochaWidgets` depende só de `MochaProtocol`. O modo demo liga com o argumento de launch `-demo`: o app usa `DemoServerConnection` (de `MochaDemo`) no lugar da conexão real.

### §2.3 Fluxos principais

**Abrir o app (1a-core)**
1. O app lê a URL e o token do Keychain, abre o WebSocket e envia `hello` (§5.3).
2. O daemon valida o token e responde `helloOk` seguido de `tree` (e de `pending`, na 1b).
3. O app mostra o último chat aberto, ou a gaveta se não houver nenhum.

**Abrir um chat (1a-core)**
1. O app envia `openChat{agentId, limit: 60}`.
2. O daemon resolve o arquivo da sessão (§3.2.1), monta a última página e responde `chatPage`.
3. Enquanto o chat está aberto, novas entradas no arquivo viram `chatAppend` ou `chatUpdate` para esse cliente.
4. Rolar até o topo pede `openChat{agentId, before: cursor}`.

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
- O app reconecta com backoff exponencial (0,5 s → 8 s, com jitter) enquanto está em primeiro plano. Ao reconectar, reenvia `hello`, recebe `tree` e reabre o chat visível com `openChat` (página nova; o app substitui a lista).
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
| `tab.create` | `{workspace_id, cwd, label?, focus: false}` | `tab_created` (`tab`, `root_pane`) | Nova tab | 1b |
| `agent.start` | `{name, kind: "claude", pane_id, args: [String], timeout_ms?}` | `agent_started` (`argv`, `agent` com `launch_pending: true`) | Digita `claude <args>` no shell do pane e volta na hora. A prontidão chega por `pane.agent_status_changed` (`idle`) ou `agent.wait`. `name` único, `[a-z][a-z0-9_-]{0,31}` | 1b |
| `agent.wait` | `{target, until: [status], timeout_ms}` | `agent_info` ou erro `timeout` | Esperar a prontidão depois do `agent.start` | 1b |
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
- Um worktree criado pelo agente dentro do próprio pane (ex.: `.claude/worktrees/<nome>`) não vira workspace: aparece só no `foreground_cwd` do pane.
- **Branch**: ler `HEAD` do git do diretório do workspace direto do arquivo, sem subprocesso. Para worktree ligado, `.git` é um arquivo `gitdir: …`; seguir esse caminho.
- **`isDirty`**: `git -C <diretório> status --porcelain=v1 --untracked-files=normal`, saída não vazia. Roda no máximo a cada 15 s por workspace, com cache, e é recalculado depois de cada `Stop` do agente desse workspace.
- Tabs sem agente aparecem como shell (ícone `>_`, `label` da tab).
- Uma tab pode ter mais de um agente (panes divididos). Cada agente vira uma linha própria sob a tab.
- Agentes que não são Claude Code (`agent != "claude"`) aparecem com ícone genérico e o nome do agente, mas não abrem chat. O toque mostra "Chat disponível só para Claude Code".

### §3.2 Transcript do Claude Code

#### §3.2.1 Localização

- Arquivo da sessão: `~/.claude/projects/<cwd codificado>/<session_id>.jsonl`.
- Resolução: procurar só `~/.claude/projects/*/<session_id>.jsonl` (um nível), com cache do resultado. **Não** reimplementar a codificação do diretório. Quando o hook traz `transcript_path`, ele tem precedência.
- O diretório do projeto também tem `memory/`, `<session_id>/tool-results/`, `<session_id>/subagents/` e `.jsonl` de plugins (ex.: `vercel-plugin/skill-injections.jsonl`, sem `type`). Nunca varrer `**/*.jsonl`.
- **Criação**: numa sessão nova, o arquivo só nasce na primeira mensagem, e o `transcript_path` do `SessionStart` pode apontar para um arquivo que ainda não existe. O diretório do projeto também pode não existir ainda (primeira sessão naquele `cwd`). O `TranscriptStore` trata arquivo inexistente como sessão vazia e observa o diretório do projeto (ou `~/.claude/projects/`, se ele também não existir) até o arquivo aparecer. Depois de `/clear`, o arquivo novo nasce na hora, já com as linhas do `/clear`.
- **Sessões**: `/clear` cria um `session_id` novo e um arquivo novo; o antigo só recebe metadados depois disso. `/compact` mantém o `session_id` e o arquivo.
- **Identidade**: vale `sessionId`. O campo `session_id` (snake_case), presente em parte das linhas, pode trazer a sessão anterior ao `/clear` e é ignorado.
- **Subagentes**: ficam em `<session_id>/subagents/agent-<agentId>.jsonl` (todas as linhas com `isSidechain: true` e `agentId`), com `agent-<agentId>.meta.json` (`agentType`, `description`, `toolUseId` do `Agent` que o criou). Não são exibidos. No arquivo principal, o subagente aparece só como o `toolCall` `Agent` e, se rodou em background, como a notificação de tarefa. Linhas com `isSidechain: true` no arquivo principal são ignoradas por garantia.

#### §3.2.2 Formato e mapeamento (Claude Code 2.1.282)

Uma entrada JSON por linha, com o campo `type`. O formato não é documentado pela Anthropic. As fixtures de `MochaKit/Fixtures/transcripts/` cobrem cada caso, e o README delas traz a sequência esperada. O parser ignora campos desconhecidos, trata tipos desconhecidos pela política abaixo e nunca falha a sessão inteira por causa de uma linha ruim: a linha é descartada e contada.

Cada linha `assistant` tem **um** bloco em `message.content`. Uma resposta da API vira várias linhas com o mesmo `message.id` e `apiBlockIndex` 0, 1, 2… Linhas `user` com `tool_result` podem vir entre blocos da mesma `message.id` (ferramentas em paralelo).

As regras são avaliadas em ordem; vale a primeira que casar.

| Entrada | Condição | Vira |
|---|---|---|
| qualquer | JSON inválido ou sem `type` string | descartada (contador `dropped`) |
| qualquer | `isSidechain == true` | ignorada |
| `ai-title` | — | `ChatMeta.title` (o último vence); não vira item |
| `permission-mode` | — | `ChatMeta.permissionMode` (o último vence; vistos: `default`, `acceptEdits`, `plan`, `auto`) |
| `mode`, `atis-latch`, `last-prompt`, `agent-name`, `queue-operation`, `file-history-snapshot`, `file-history-delta`, `worktree-state`, `relocated`, `cost-state`, `pr-link`, `frame-link`, `fork-context-ref`, `bridge-session`, `continued-in` | — | ignorados |
| `attachment` | `attachment.type == "queued_command"`, `commandMode == "prompt"`, `origin.kind` ausente ou `human`, sem `isMeta` | `userPrompt`: prompt enviado com o Claude trabalhando. `prompt` é string ou blocos `text`/`image` |
| `attachment` | `queued_command` com `commandMode == "task-notification"` | `notice` com o `<summary>` |
| `attachment` | demais | ignorado |
| `user` | `isMeta == true` | ignorado (caveat de comando local, `turnCompanion`, mensagem `peer`, "[Image: original …]") |
| `user` | `isCompactSummary == true` | ignorado (resumo do `/compact`) |
| `user`, content string | contém `<command-name>/x</command-name>` | `slashCommand(name: "/x", args: <command-args>)`. Se o último `slashCommand` tem o mesmo `promptId` e o mesmo nome, não cria item (eco do `/compact`) |
| `user`, content string | começa com `<local-command-stdout>` ou `<local-command-stderr>` | `output` do último `slashCommand`, sem as tags e sem códigos ANSI → `chatUpdate` |
| `user`, content string | começa com `<bash-input>` (comando `!` do terminal) | `slashCommand(name: "!", args: <comando>)` |
| `user`, content string | começa com `<bash-stdout>` ou `<bash-stderr>` | `output` do último `slashCommand` (stdout, e stderr se não vazio) → `chatUpdate` |
| `user`, content string | `origin.kind == "task-notification"` ou começa com `<task-notification>` | `notice` com o `<summary>` (ex.: `Agent "Revisar README" finished`) |
| `user`, content string | o texto é `/compact` ou `/compact <instruções>` | `slashCommand(name: "/compact", args: …)`: a linha crua que o Claude grava antes de compactar |
| `user`, content string | demais | `userPrompt(text, imageCount: 0)` |
| `user`, content array | tem bloco `tool_result` | atualiza o `toolCall` de `tool_use_id`: `failed` se `is_error == true`, senão `succeeded`, com `resultPreview` → `chatUpdate`. `tool_use_id` desconhecido: ignorado e contado |
| `user`, content array | um único bloco `text` igual a `[Request interrupted by user]` ou `[Request interrupted by user for tool use]` | `notice("Interrompido pelo usuário")` |
| `user`, content array | blocos `text`/`image` | `userPrompt(text: textos unidos por "\n", imageCount: nº de blocos image)`; outros blocos (ex.: `document`) não contam |
| `assistant` | `isApiErrorMessage == true` ou `message.model == "<synthetic>"` | `notice` com o texto do bloco (ex.: "API Error: …"); não atualiza modelo nem branch |
| `assistant`, bloco `text` | texto não vazio depois de aparar espaços | `assistantText(markdown)` |
| `assistant`, bloco `thinking` | — | `thinking(text:)`, com `nil` quando `thinking == ""` (o caso comum) |
| `assistant`, bloco `redacted_thinking` | — | `thinking(text: nil)` |
| `assistant`, bloco `tool_use` | — | `toolCall` com `status: running`, `summary` (abaixo) e `inputJSON` do `input` truncado em 4.000 caracteres |
| `assistant`, outro bloco | — | ignorado e contado |
| `system` / `turn_duration` | `durationMs` | `turnFooter(durationMs)`. Turno interrompido não tem `turn_duration` |
| `system` / `away_summary` | `content` | `recap(text)` |
| `system` / `local_command` | `content` com `<command-name>` | `slashCommand`, pela mesma regra de `user` |
| `system` / `local_command` | `content` com `<local-command-stdout>` ou `<local-command-stderr>` | `output` do último `slashCommand` |
| `system` / `compact_boundary` | — | `notice("Conversa compactada")` |
| `system` / `informational`, `model_consent_fallback`, `api_error` | `content` | `notice(content)` |
| `system` / `stop_hook_summary`, `bridge_status`, `agents_killed` | — | ignorados |
| `system`, outro `subtype` | — | ignorado e contado |
| outro `type` | — | ignorado e contado |

`toolCall.summary` (uma linha, até 120 caracteres):

| Ferramenta | `summary` |
|---|---|
| `Bash` | primeira linha de `command` |
| `Read`, `Write`, `Edit`, `NotebookEdit` | `file_path`, relativo ao `cwd` da linha quando está dentro dele |
| `Grep`, `Glob` | `pattern` |
| `WebFetch` | `url` |
| `WebSearch`, `ToolSearch` | `query` |
| `Agent` | `description` |
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

Regras:

- **Ordem**: a do arquivo. `timestamp` não é monotônico (no `/compact`, linhas gravadas depois têm hora anterior) e só alimenta `ChatItem.at`.
- **Ids**:
  - O id do item é `<uuid da linha>`, ou `<uuid>#<índice do bloco>` se uma linha trouxer mais de um bloco (não observado na 2.1.282). Um `userPrompt` de `queued_command` usa o `uuid` da linha `attachment`.
  - Linhas que só atualizam outro item não geram id: saída de comando, `tool_result` e eco do `/compact`.
- **`tool_result`**: vem sempre depois do `tool_use`, em até 50 linhas no corpus (99 % em até 3). Um `tool_use` sem resultado fica `running` (AskUserQuestion esperando resposta ou sessão encerrada).
- **Header**:
  - Modelo e branch vêm da última linha `assistant` que não seja `<synthetic>` (`message.model`, `gitBranch`).
  - `gitBranch == "HEAD"` (pasta sem git ou HEAD destacado) vira `nil`. O modelo pode ter sufixo de data (`claude-haiku-4-5-20251001`).
  - O título vem do último `ai-title`, que começa como frase e depois vira o nome em kebab-case (igual ao título do terminal). Na falta dele, vem de `terminal_title_stripped` do Herdr.
- **Escrita**:
  - O Claude grava cada bloco completo, sem streaming por token. Enquanto o status for `working`, o app mostra o indicador de "trabalhando".
  - Os metadados (`last-prompt`, `ai-title`, `mode`, `permission-mode`, `atis-latch`) são regravados em grupo durante o turno, então `permissionMode` pode atrasar alguns segundos em relação ao terminal.
- **Comando local**: a saída pode ter códigos ANSI (`\u001b[2m…`), removidos antes de enviar. Quebras de linha nas pontas são aparadas; espaços iniciais ficam (saída de `git status`).

Política para tipos novos:

1. `type`, `subtype`, tipo de bloco ou `attachment.type` desconhecido: a linha (ou o bloco) é ignorada e contada por nome, com um aviso no log por nome e por arquivo, não por linha.
2. Campos desconhecidos são sempre ignorados. Campos esperados ausentes usam o padrão: `is_error` ausente é sucesso, `thinking` ausente é vazio.
3. O `doctor` mostra, por sessão acompanhada, a versão do Claude (`version` da última linha), as linhas descartadas e os desconhecidos por nome. Ele avisa quando a versão é maior que a última validada (2.1.282).
4. Um tipo novo que precise aparecer no chat entra nesta tabela junto com uma fixture e o snapshot esperado.

#### §3.2.3 Leitura e desempenho

- Os arquivos passam de dezenas de MB em sessões longas, e uma linha pode passar de 1 MB (imagem colada em base64; a maior vista tinha 1,8 MB).
- **Primeira abertura**:
  - Varredura única do arquivo, montando um índice de offsets de linha; a última linha sem `\n` fica fora do índice.
  - Página inicial = últimos `limit` itens, lidos a partir do fim.
  - Ao montar qualquer página, os `tool_result` das até 64 linhas seguintes ao fim dela são aplicados aos `toolCall` da página.
  - Meta: `chatPage` em < 300 ms para um arquivo de 50 MB no M1 (fixture de `scripts/gen-big-transcript.swift`).
- **Acompanhamento**: `DispatchSource.makeFileSystemObjectSource` (`.extend`, `.write`, `.rename`, `.delete`), lendo de `lastOffset` até o fim. Linha incompleta (sem `\n`) fica em buffer até completar.
- **Arquivo que ainda não existe** (sessão nova sem mensagem): observar o diretório do projeto, ou `~/.claude/projects/` se ele também não existir, até o arquivo aparecer.
- **Cursor de paginação**: opaco para o app. Internamente é o offset da primeira linha da página.
- O daemon só acompanha arquivos de sessões com chat aberto em algum cliente, ou com agente `working`/`blocked` (necessário para push e Live Activity). Fora disso, fecha o descritor.

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
- O segredo é o `hookSecret` do `config.json`, escrito literalmente no header e no comando. O `HookServer` responde 401 sem ele. O segredo fica em texto no `settings.json` e aparece na linha de comando do `curl` enquanto o hook roda; isso é aceito num Mac de um usuário só.
- **`HookServer`**:
  - rotas `POST /hooks/<Evento>`, respondendo sempre 200 com JSON (`{}` quando não decide);
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

---

## §4 mochad (daemon do Mac)

### §4.1 Componentes

Todos são `actor`s ou tipos `Sendable`, com Swift 6 e strict concurrency completo.

| Componente | Responsabilidade |
|---|---|
| `HerdrClient` (`MochaHerdr`) | Conexões com o socket, requisições com id, stream de eventos (`AsyncStream`), reconexão |
| `HerdrBridge` | Snapshot inicial, inscrições (§3.1.3), árvore derivada (§3.1.4), comandos (prompt, Esc, teclas, nova tab) |
| `TranscriptStore` | Resolução de arquivo, índice de offsets, páginas, acompanhamento, deltas por sessão |
| `SessionHub` | Clientes conectados, chats abertos por cliente, primeiro plano por cliente, broadcast |
| `HttpServer` | HTTP/1.1 mínimo sobre `NWListener` (§4.4) |
| `Gateway` | Rotas do app sobre o `HttpServer`: WebSocket `/v1` e HTTP de ações e upload (§5) |
| `HookServer` | Rotas `/hooks/<evento>` no listener local, validação do segredo, tradução em eventos internos |
| `PendingStore` | Pedidos pendentes (1b), timeouts e resolução |
| `PushService` | APNs: JWT, alertas, Live Activity, escolha de ambiente (§7) |
| `DeviceStore` | Aparelhos pareados (§4.6) |
| `Pairing` | Geração de token e QR (§4.5) |

### §4.2 CLI

| Comando | Faz |
|---|---|
| `mochad run` | Roda em primeiro plano (é o que o LaunchAgent chama) |
| `mochad install` | Copia o binário para `~/.local/bin/mochad`, escreve `~/Library/LaunchAgents/com.joaoalves.mochad.plist` (`RunAtLoad`, `KeepAlive`, logs em `~/Library/Logs/Mocha/`) e roda `launchctl bootstrap gui/$UID …` |
| `mochad uninstall` | `launchctl bootout` e remove o plist. Não apaga dados |
| `mochad pair` | Gera um token de pareamento de uso único (válido por 10 min) e imprime o QR no terminal (§4.5) |
| `mochad devices` | Lista e remove aparelhos pareados (`--remove <id>`) |
| `mochad install-hooks` / `uninstall-hooks` | §3.3 |
| `mochad serve-setup` | Mostra (e com `--apply` executa) o comando `tailscale serve` (§4.5) |
| `mochad apns import <arquivo.p8> --key-id <KID> --team-id <TID>` | Guarda a chave no Keychain e grava `keyId`/`teamId` no config |
| `mochad apns test [--device <id>]` | Manda um push de teste |
| `mochad status` | Estado do daemon, do Herdr e do Serve, clientes conectados |
| `mochad doctor` | Diagnóstico com ✅/⚠️/❌: socket do Herdr, `agent.list`, hooks instalados, moshi-hook, Serve, APNs, permissões do diretório de dados |

### §4.3 Caminhos e configuração

| Caminho | Conteúdo |
|---|---|
| `~/Library/Application Support/Mocha/config.json` | `hookPort` (47420), `gateway` (`{"kind":"unix","path":…}` ou `{"kind":"tcp","port":47421}`), `apns{teamId, keyId, bundleId}`, `hookSecret` |
| `~/Library/Application Support/Mocha/devices.json` | Aparelhos (§4.6). Permissão 0600 |
| `~/Library/Application Support/Mocha/gateway.sock` | Socket Unix do gateway (0600), se o S5 aprovar |
| `~/Library/Application Support/Mocha/uploads/` | Imagens recebidas (1b). Apagadas depois de 7 dias |
| `~/Library/Logs/Mocha/mochad.log` | stdout/stderr do LaunchAgent |
| Keychain (login), serviço `com.joaoalves.mocha.apns`, conta = Key ID | Conteúdo da `.p8` |

Log: `os.Logger(subsystem: "com.joaoalves.mocha", category: <componente>)`. Tokens e segredos nunca vão para o log.

### §4.4 HttpServer

- `NWListener` TCP em `127.0.0.1` para os hooks. O gateway fica no socket Unix ou em `127.0.0.1` (§4.5), com o mesmo servidor atendendo HTTP e o upgrade de WebSocket.
- Suporta: linha de requisição, headers, corpo com `Content-Length` (limite de 1 MB; 20 MB só em `/v1/upload`; acima disso, 413), resposta com `Content-Length`, `Connection: close`. Sem chunked, sem keep-alive, sem HTTP/2.
- Handlers são `async` e podem segurar a resposta por até 600 s (necessário para o `PermissionRequest`, §8.1). A conexão fechada pelo cliente cancela a `Task` do handler.
- **WebSocket**: o upgrade (`Sec-WebSocket-Accept` com SHA-1 + base64) e o framing RFC 6455 são implementados no próprio `HttpServer`: frames de texto e binário, fragmentação de entrada, ping/pong automático, close, e máscara obrigatória nos frames do cliente. Sem extensões (sem `permessage-deflate`). O `NWProtocolWebSocket` fica de fora porque, no stack do listener, ele não atende HTTP comum na mesma porta.
- Resposta a método desconhecido ou path inválido: 404/405 com corpo vazio.
- **Bindings**: `.loopback(port:)` (127.0.0.1) e `.unixSocket(path:)`. O `NWListener` escuta em `NWEndpoint.unix(path:)` (confirmado no WP0.3): o servidor remove um socket antigo antes do bind (só se o caminho for socket), aplica 0600 depois do `.ready` e apaga o arquivo no `stop`.
- **Respostas do próprio servidor**: `Transfer-Encoding` (chunked ou outro) → 411; requisição malformada (linha ou header inválido, `Content-Length` inválido ou conflitante) → 400; versão diferente de 1.0/1.1 → 505; cabeçalho acima de 32 KiB → 431; cabeçalho incompleto em 30 s → fecha sem resposta; 405 leva `Allow`; erro lançado pelo handler → 500 vazio. 204, 304 e 1xx saem sem `Content-Length` (RFC 9110). O handler não sobrescreve `Content-Length`, `Connection` nem `Transfer-Encoding`. `Expect: 100-continue` não é tratado.
- **Resposta antecipada** (413, 404 ou 405 com corpo pendente): o servidor drena o corpo até `min(Content-Length, 32 MiB)` ou EOF, com limite de 10 s, antes de fechar, para o cliente receber a resposta em vez de um reset.
- **Tempo do handler**: o servidor não impõe timeout; o limite (ex.: 580 s do `PermissionRequest`, §8.3) é de quem chama. O cliente que fecha ou meio-fecha (shutdown de escrita) a conexão cancela a `Task` do handler.
- **WebSocket**: limite de mensagem de 1 MiB por padrão, configurável por rota; close com eco do código e espera de até 5 s pelo close do cliente; o servidor não manda ping periódico.

### §4.5 Exposição, pareamento e autenticação

- **Exposição**: `tailscale serve --bg --https=443 <alvo>`, onde `<alvo>` é `unix:<gateway.sock>` (preferido) ou `http://127.0.0.1:47421`. O socket Unix só vale se dois pontos se confirmarem: que o `NWListener` escuta em `NWEndpoint.unix(path:)` (confirmado no WP0.3) e que o Tailscale standalone (que roda como extensão de sistema) consegue abrir um socket em `~/Library/Application Support/Mocha/`. Sem isso, fica o TCP em `127.0.0.1`. O S5 registra o comando exato. O iPhone acessa `wss://mac-mini.tail1234.ts.net/v1`.
- **Pareamento**:
  1. `mochad pair` gera um código de pareamento aleatório de 32 bytes (base64url) e imprime um QR (CoreImage `CIQRCodeGenerator` renderizado com meio-blocos Unicode) com `mocha://pair?url=<wss url>&code=<código>`.
  2. O app lê o QR (câmera, `DataScannerViewController`) ou recebe o link colado.
  3. Ele conecta e envia `hello{pairingCode}`.
  4. O daemon troca o código por um **token de aparelho** (32 bytes aleatórios), devolvido uma única vez em `helloOk.deviceToken`.
  5. O app guarda o token no Keychain (`kSecAttrAccessibleAfterFirstUnlock`, necessário para ações de notificação em background).
- **Autenticação**: toda conexão WS envia `hello{deviceToken}` como **primeira mensagem**. A URL do WS nunca carrega token, porque o proxy do Serve pode descartar a query string. Requisições HTTP do app levam `Authorization: Bearer <deviceToken>`. O daemon guarda só o SHA-256 do token e compara em tempo constante. Três falhas seguidas numa conexão encerram a conexão.

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

### §4.7 Metas de desempenho do daemon

- Parado (sem cliente e sem agente trabalhando): CPU ~0 %, RSS < 30 MB.
- Latência de evento do Herdr até `agentStatus` no app, na mesma rede: < 250 ms.
- Latência de linha nova no JSONL até `chatAppend`: < 300 ms.
- Nenhum polling abaixo de 2 s. Tudo é orientado a eventos (socket do Herdr e DispatchSource).
- Referência medida (S2): o Herdr entrega `pane.agent_status_changed` 30–100 ms depois da mudança de estado, e o `working` chega 0,5–0,7 s depois do envio do prompt (o `agent.prompt` leva ~300 ms).

---

## §5 Protocolo v1 (`MochaProtocol`)

### §5.1 Envelope

Mensagens WebSocket de texto, JSON UTF-8. Datas em ISO-8601 com milissegundos. Chaves em camelCase.

```json
{"v": 1, "id": "c-42", "type": "sendPrompt", "payload": { … }}
```

- `v`: versão do protocolo. Um cliente com `v` diferente recebe `error{code:"protocolMismatch"}` e é desconectado.
- `id`: obrigatório em toda mensagem do cliente (string única por conexão). Toda **resposta direta** repete o `id` da requisição: `helloOk`, `tree` (a primeira, logo após `helloOk`, repete o `id` do `hello`), `chatPage`, `ack`, `pong` e `error`. **Eventos** do servidor (`treeChanged`, `agentStatus`, `chatAppend`, `chatUpdate`, `chatMeta`, `pending`) não têm `id`.
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

public enum ChatItemKind: Codable, Sendable {
    case userPrompt(text: String, imageCount: Int)
    case slashCommand(name: String, args: String, output: String?)   // name: "/x" ou "!" (comando de shell do terminal)
    case assistantText(markdown: String)
    case thinking(text: String?)
    case toolCall(ToolCall)
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
- Um struct associado (`toolCall(ToolCall)`) também tem os campos achatados.
- Opcionais `nil` são omitidos. Datas em ISO-8601 com milissegundos (`2026-09-25T15:44:34.551Z`).
- O `Codable` é implementado à mão, com testes de ida e volta contra as fixtures de `MochaKit/Fixtures/protocol/`.
- Um `type` desconhecido em `ChatItem` decodifica como `unsupported(type:)`; nos demais enums, como erro de decodificação só daquele item.
- `AgentStatus` com valor desconhecido decodifica como `.unknown`.
- Listas tolerantes: `items` de `chatPage`, `chatAppend` e `chatUpdate`, e `requests` de `pending`, descartam o item que não decodifica e mantêm os outros. As demais listas são estritas.
- Os códigos de `error` formam um conjunto aberto (`ProtocolErrorCode`): um código desconhecido é preservado.

Exemplos canônicos (as fixtures do WP0.2 seguem exatamente estes formatos):

```json
{"id":"8f1c…","at":"2026-09-25T15:44:34.551Z","type":"userPrompt","text":"roda os testes","imageCount":0}
{"id":"9a2d…","at":"2026-09-25T15:44:40.120Z","type":"assistantText","markdown":"Rodando `scripts/test.sh`…"}
{"id":"b7e0…","at":"2026-09-25T15:44:41.000Z","type":"toolCall","toolUseId":"toolu_01H3…","name":"Bash","summary":"scripts/test.sh","inputJSON":"{\"command\":\"scripts/test.sh\"}","status":"succeeded","resultPreview":"All tests passed"}
{"id":"c1f4…","at":"2026-09-25T15:45:10.000Z","type":"turnFooter","durationMs":45000}
{"id":"d2a9…","at":"2026-09-25T15:45:11.000Z","type":"slashCommand","name":"/clear","args":""}
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
{"v":1,"id":"c-7","type":"chatPage","payload":{"agentId":"w17:p1","meta":{"title":"herdr-sidebar abre arquivos em nova tab","workspaceLabel":"Core","model":"claude-opus-5-5","branch":"development","status":"idle"},"items":[…],"before":"b:120394","hasMore":true}}
{"v":1,"type":"agentStatus","payload":{"agentId":"w17:p1","status":"working"}}
{"v":1,"id":"c-9","type":"ack","payload":{}}
{"v":1,"id":"c-9","type":"error","payload":{"code":"agentBlocked","message":"O agente está esperando uma resposta no terminal."}}
```

### §5.3 Mensagens

Todas as requisições do cliente podem receber `error` em vez da resposta indicada.

Tipos Swift em `MochaProtocol`: `ClientMessage` e `ServerMessage` (com `.unknown(type:)`), os envelopes `ClientEnvelope` e `ServerEnvelope`, `EnvelopeHeader` (lê `v`, `id` e `type` sem falhar, para o daemon responder `protocolMismatch` ou `invalidPayload` com o `id` certo; o `ClientEnvelope` não valida `v`), os payloads `HelloPayload`, `HelloOkPayload`, `ChatPage` e `LiveActivityRegistration`, e `ProtocolDate` (formato e parse das datas, reutilizado pelo daemon). A regra "exatamente um entre `deviceToken` e `pairingCode`" é validada pelo daemon, não na decodificação. Fixtures em `MochaKit/Fixtures/protocol/`: `client.<type>[.<variante>].json`, `server.<type>[.<variante>].json`, `chatItem.<kind>[.<variante>].json`, `pendingRequest.<kind>.json` e `pendingResponse.<type>[.<variante>].json`.

**Cliente → servidor**

| `type` | payload | Resposta | Fase |
|---|---|---|---|
| `hello` | `{deviceToken?: String, pairingCode?: String, deviceName: String, appVersion: String, apns?: ApnsRegistration}` (exatamente um entre `deviceToken` e `pairingCode`) | `helloOk` e depois `tree` | 1a-core (`apns` 1a-final) |
| `openChat` | `{agentId, before?: String, limit?: Int}` (`limit` padrão 60, máximo 200) | `chatPage` | 1a-core |
| `closeChat` | `{agentId}` | `ack{}` | 1a-core |
| `sendPrompt` | `{agentId, text}` | `ack{}` | 1a-core |
| `interrupt` | `{agentId}` | `ack{}` | 1a-core |
| `setForeground` | `{agentId?: String, isActive: Bool}` | `ack{}` | 1a-core |
| `unpair` | `{}` | `ack{}` e o daemon fecha a conexão e apaga o aparelho | 1a-core |
| `ping` | `{}` | `pong{}` | 1a-core |
| `slash` | `{agentId, command: String}` (ex.: `"/compact"`) | `ack{}` | 1a-final |
| `setPreferences` | `DevicePreferences` | `ack{}` | 1a-final |
| `respond` | `{requestId, response: PendingResponse}` | `ack{}` | 1b |
| `newAgentTab` | `{workspaceId}` | `ack{agentId}` | 1b |
| `registerLiveActivity` | `{pushToStartToken?: String, activityId?: String, updateToken?: String, env: ApnsEnvironment}` | `ack{}` | 1b |

**Servidor → cliente**

| `type` | payload | Quando |
|---|---|---|
| `helloOk` | `{host: HostInfo, deviceId: DeviceID, deviceToken?: String, preferences: DevicePreferences}` (`deviceToken` só no pareamento) | Resposta a `hello` válido |
| `tree` | `{workspaces: [WorkspaceNode]}` | Logo depois de `helloOk`, com o mesmo `id` |
| `treeChanged` | `{workspaces: [WorkspaceNode]}` (árvore inteira; é pequena) | Evento: mudança de árvore (debounce de 150 ms) |
| `agentStatus` | `{agentId, status: AgentStatus, title?: String}` | Evento: mudança de status |
| `chatPage` | `{agentId, meta: ChatMeta, items: [ChatItem], before: String?, hasMore: Bool}` | Resposta a `openChat` |
| `chatAppend` | `{agentId, items: [ChatItem]}` | Evento: itens novos num chat aberto |
| `chatUpdate` | `{agentId, items: [ChatItem]}` (substitui por `id`) | Evento: um item já enviado mudou (ex.: `tool_result` chegou) |
| `chatMeta` | `{agentId, meta: ChatMeta}` | Evento: título, modelo, branch, status ou modo mudou |
| `pending` | `{requests: [PendingRequest]}` (lista completa) | 1b. Evento: mudança na lista (também enviado logo depois de `tree`) |
| `ack` | `{}`, ou `{agentId}` para `newAgentTab` | Resposta simples |
| `pong` | `{}` | Resposta a `ping` |
| `error` | `{code, message}` | Resposta a uma requisição. Códigos: `unauthorized`, `pairingExpired`, `protocolMismatch`, `unknownType`, `invalidPayload`, `agentNotFound`, `agentBlocked`, `requestNotFound`, `herdrUnavailable`, `internal` |

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
| `POST /v1/upload` | Corpo binário, `Content-Type: image/jpeg`, `image/png` ou `image/heic`. Resposta `{"path": "/Users/…/uploads/<uuid>.<ext>"}` | 1b |

---

## §6 App iOS

### §6.1 Estrutura

- SwiftUI, iOS 26+, só iPhone, só retrato na 1a.
- Estado de UI em classes `@Observable @MainActor`. A conexão fica num `actor ConnectionManager` que expõe `AsyncStream` de mensagens do servidor.
- Módulos em `App/Sources/`: `AppShell/` (raiz, navegação, deep links), `DesignSystem/`, `Connection/` (`KeychainTokenStore` e ligação do `MochaClient` à UI), `Pairing/`, `Drawer/`, `Chat/`, `Composer/`, `Markdown/`, `Settings/`, `Notifications/`, `Inbox/` (1b), `LiveActivity/` (1b), `Voice/` (1b), `Terminal/` (fase 2) e `Debug/` (telas de preview e sondas dos spikes, só em Debug).
- A lógica de conexão fica no target `MochaClient` do pacote (testável no macOS): `ConnectionManager` (actor) implementa `ServerConnection` sobre `URLSessionWebSocketTask`, com backoff e um `TokenStore` injetado. O app entrega o `KeychainTokenStore`.
- O WebSocket fica aberto só com o app ativo e fecha ao ir para background (`scenePhase`).
- **Deep links**: `mocha://agent/<paneId>` abre o chat e `mocha://pair?url=…&code=…` inicia o pareamento. O `paneId` vai percent-encoded, porque contém `:`.

### §6.2 Design system

O visual segue fielmente os prints em `docs/referencias/moshi/`. Toda tela nova é comparada lado a lado com o print correspondente antes de ser dada como pronta. As cores abaixo foram medidas nos prints (arredondadas em ±4 por canal).

| Token | Hex | Uso |
|---|---|---|
| `bg` | `#1E1E1E` | Fundo do chat e do terminal |
| `drawerBg` | `#161719` | Fundo da gaveta |
| `scrim` | `#0F0F10` | Conteúdo escurecido atrás da gaveta |
| `textPrimary` | `#FCFCFC` | Texto do chat, nomes de workspace, texto em negrito |
| `textSecondary` | `#98A0A8` | Subtítulos, "Brewed for", recap, placeholder, branch, cabeçalho de seção, ícone de shell |
| `link` | `#78A0F4` | Código inline, caminhos e comandos no markdown |
| `userBubble` | `#1B351B` | Bolha do usuário (texto `textPrimary`) |
| `selectedRow` | `#142E16` | Linha selecionada na gaveta |
| `toolCard` | `#121416` | Card de ferramenta (borda `#303438`) |
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

- **Tipografia**:
  - Chat, header e composer usam fonte **monoespaçada**. O WP de design system identifica a fonte do print comparando o SF Mono do sistema (`.monospaced`) com JetBrains Mono e Geist Mono (licença OFL, empacotável).
  - O corpo do chat mede ~17 pt, com entrelinha folgada (ver prints), e respeita o Dynamic Type.
  - A gaveta usa a fonte do sistema (SF Pro), como no print `gaveta-workspaces.png`.
- **Vidro**: `glassEffect` do iOS 26 no header, no composer e nos botões redondos flutuantes, sempre escuro (o app força `.preferredColorScheme(.dark)`).
- **Ícones**: SF Symbols. O asterisco do Claude é um símbolo desenhado (asset vetorial) na cor `claude`.

### §6.3 Telas

**Pareamento** (primeira execução ou token inválido)
- Tela escura com o logo, "Parear com o Mac" e as instruções `mochad pair`.
- Botão de ler QR (câmera) e campo para colar o link.
- Estados: lendo, conectando, pareado, erro (com a mensagem).

**Gaveta** (`gaveta-workspaces.png`)
- Abre pela borda esquerda (arrasto) ou pelo botão do header, e ocupa ~90 % da largura com `scrim` no restante.
- Topo: campo de busca ("Buscar workspaces, agentes…") filtrando por workspace, tab e título do agente, e o controle segmentado **Recentes** (relógio: agentes por `lastActivityAt`) | **Árvore** (lista).
- Árvore: cabeçalho "WORKSPACES"; cada workspace tem chevron, nome em peso médio, ícone de branch com o nome, `*` em `dirty` quando `isDirty`, e worktrees aninhados.
- Tabs: ícone (asterisco do Claude ou `>_`) e título do agente ou da tab. Agente ocioso não tem indicador, como no print. Em `working` o asterisco pulsa; em `blocked` aparece um ponto `dirty` à direita.
- A linha do chat atual fica com `selectedRow`. Tocar numa tab com agente abre o chat; tocar numa tab de shell mostra "Terminal chega na fase 2".
- 1b: botão `+` por workspace → "Nova tab com Claude".

**Chat** (`chat-conversa.png`, `chat-recap.png`)
- **Header flutuante de vidro**, com:
  - ponto de status;
  - asterisco do Claude;
  - título (truncado no meio);
  - subtítulo "workspace • modelo • branch" em `textSecondary` (modelo abreviado: sem o prefixo `claude-` e sem o sufixo de data `-AAAAMMDD`, ex.: `claude-opus-5-5` → `opus-5-5`, `claude-haiku-4-5-20251001` → `haiku-4-5`);
  - à direita, um botão redondo que abre a gaveta (bússola).
  - O conteúdo rola por baixo do header.
- **Lista**:
  - `userPrompt`: bolha à direita, cantos arredondados de ~20 pt, largura máxima de ~80 %.
  - `assistantText`: markdown à esquerda, largura total, sem bolha.
  - `toolCall`: card `toolCard` de uma linha (`>_ Shell <resumo>` com ✓ ou ✗ à direita). Chamadas **consecutivas** da mesma ferramenta formam um card só, com contador (`Shell ×3 …`). Tocar expande e mostra, por chamada, o input e a prévia do resultado em mono.
  - `thinking`: linha colapsada "Pensou" em `textSecondary`; toque expande quando há texto. Vários `thinking` seguidos viram uma linha só (cerca de 90 % vêm sem texto).
  - `turnFooter`: "Brewed for 45s" em itálico `textSecondary`.
  - `recap`: "**Recap:** …" em itálico `textSecondary`.
  - `slashCommand`: chip discreto com `name` e `args` (ex.: "/clear"); com `output`, o toque expande a saída em mono. `name == "!"` é um comando de shell digitado no terminal.
  - `notice`: texto centralizado pequeno.
  - Indicador "trabalhando…" no fim da lista enquanto `status == working`.
- **Rolagem**: gruda no fim quando o usuário já está no fim. Se ele rolou pra cima, aparece o botão redondo "↓" (canto inferior direito, acima do composer) e itens novos não mexem na posição.
- **Paginação**: ao chegar no topo, carrega `before` com um indicador; a posição de leitura se mantém.
- **Troca de sessão**: quando o `sessionId` do agente do chat aberto muda num `tree`/`treeChanged` (depois de `/clear`), o app reabre o chat com `openChat` e substitui a lista; a sessão nova começa com o chip `/clear`.

**Composer** (flutuante sobre o fim da lista)
- Campo multilinha "Chat via Mocha…" (até 6 linhas, depois rola).
- Linha de botões:
  - `+`: imagem, 1b;
  - `>_`: terminal, fase 2, **oculto antes da fase 2**;
  - `↻`: menu de slash e ações, 1a-final;
  - microfone: 1b;
  - enviar: círculo; desabilitado sem texto.
- Com o agente em `working`, o botão enviar vira **parar** (quadrado), que manda `interrupt`. Com texto digitado durante `working`, enviar continua disponível (o Claude enfileira).
- **Menu `↻`** (1a-final): `/compact`, `/clear` (com confirmação), `/context`, `/cost`, "Interromper (Esc)". Comandos que abrem seletor no terminal (`/model`, `/resume`) ficam fora. Lista fixa no código.

**Inbox** (1b)
- Acesso por um sino no header da gaveta, com badge da contagem.
- Um cartão por `PendingRequest`, com agente, workspace e tempo.
- Aprovação: ferramenta, resumo e input expandível, com botões "Permitir" e "Negar".
- Pergunta: cada `PendingQuestion` com as opções (seleção única ou múltipla), campo "Outro" e botão "Responder".
- Tocar no nome do agente abre o chat.

**Ajustes**: host pareado e estado da conexão, desparear (`unpair` e limpeza do Keychain), notificações de turno concluído (`setPreferences`, 1a-final), versão do app e do daemon.

### §6.4 Voz (1b)

- `SpeechAnalyzer` + `SpeechTranscriber` com locale `pt-BR`, on-device.
- Antes de habilitar o microfone, conferir `SpeechTranscriber.supportedLocales` e baixar o modelo via `AssetInventory` se preciso.
- Toque no microfone inicia e toque de novo para. O texto parcial aparece no campo em `textSecondary` e o final substitui o parcial. Nada é enviado sozinho.

### §6.5 Imagem (1b)

- Origem: `PhotosPicker`, câmera e colar da área de transferência.
- Reduzir para no máximo 2.048 px no lado maior, JPEG qualidade 0,85.
- `POST /v1/upload`, e o caminho devolvido entra no prompt como texto (`[imagem: /Users/…/uploads/x.jpg]`). O Claude Code lê imagens pelo caminho.
- A bolha do usuário mostra "📎 1 imagem".

---

## §7 Push e Live Activity

### §7.1 Alertas (1a-final)

- **APNs**: HTTP/2 via `URLSession` para `api.sandbox.push.apple.com` ou `api.push.apple.com`, conforme o `env` do token do aparelho (o app manda `env` junto com o token; build do Xcode = `sandbox`, TestFlight = `production`, detectado pelo `aps-environment` do perfil embutido ou por flag de build).
- **JWT**: ES256 com a `.p8` (CryptoKit `P256.Signing.PrivateKey(pemRepresentation:)`). A assinatura usa `signature.rawRepresentation` (r‖s), **não DER**. O token é reutilizado e renovado a cada 40 min (a Apple rejeita renovação abaixo de 20 min e token acima de 60 min).
- **Headers**: `apns-topic: com.example.mocha`, `apns-push-type: alert`, `apns-priority: 10` (alertas são imediatos; prioridade 5 pode atrasar a entrega), `apns-collapse-id` por agente.
- **Tipos**:
  - Turno concluído (`Stop`): título "Claude terminou · <workspace>", corpo com os primeiros 180 caracteres de `last_assistant_message` sem markdown. `thread-id` = `agentId`; `category` `TURN_DONE`.
  - Agente precisa de você: disparado pelo `PermissionRequest` (§8), na hora. O `blocked` do Herdr sem pedido (ex.: diálogo de confiança da pasta) e o `Notification` `permission_prompt` são sinais secundários. Título "Claude precisa de você · <workspace>", corpo com o `summary` do pedido ou com `questions[0].question`. `interruption-level: time-sensitive`; `category` `NEEDS_INPUT` (1a-final, sem ações) e `PERMISSION`/`QUESTION` (1b, com ações).
- **Supressão**: nenhum alerta para um aparelho cujo cliente está conectado com `setForeground{agentId: X, isActive: true}` quando o alerta é do agente X. Alertas de turno concluído respeitam `preferences.turnDoneAlerts` do aparelho; os de "precisa de você" sempre saem.
- **Deduplicação**: um alerta de "precisa de você" por pedido. Enquanto a sessão tiver pedido pendente (1b), e até 10 s depois do `PermissionRequest`, o `blocked` do Herdr e o `Notification` `permission_prompt` dessa sessão não geram outro alerta. O `permission_prompt` chega ~6 s depois do diálogo.
- **Payload**: `{"aps":{…},"agentId":"w17:p1","kind":"turnDone|needsInput","requestId?":"…"}`.
- Resposta 410 ou `BadDeviceToken` do APNs remove o token do aparelho.

### §7.2 Ações de notificação (1b)

- `PERMISSION`: "Permitir" (`.authenticationRequired`, sem `.foreground`) e "Negar" (`.destructive`). "Negar" manda `deny` com a mensagem padrão (§8.2): o Claude recebe a negação e continua o turno.
- `QUESTION`: "Responder" (`UNTextInputNotificationAction`), só para uma pergunta sem `multiSelect`. Um texto igual a um rótulo vira esse rótulo; qualquer outro texto vai como resposta livre, que o Claude aceita. Várias perguntas ou `multiSelect` abrem o app (`.foreground`).
- O app, acordado em background, faz `POST /v1/respond` com o token do Keychain. Se o tailnet estiver fora, a ação falha e a notificação local "Não consegui falar com o Mac" aparece.

### §7.3 Live Activity agregada (1b)

- Uma única atividade `MochaAgentsAttributes` (sem atributos estáticos relevantes), definida em `MochaProtocol` sob `#if os(iOS)` (o `ActivityAttributes` não existe no macOS), com `ContentState`:

```swift
public struct ContentState: Codable, Hashable {
    public var working: Int
    public var waiting: Int                 // blocked
    public var highlight: Highlight?        // o mais urgente: blocked > working mais antigo
    public var updatedAt: Date
    public struct Highlight: Codable, Hashable {
        public var agentId: String
        public var title: String
        public var workspaceLabel: String
        public var status: String
        public var since: Date
    }
}
```

- **Tela bloqueada**: "2 trabalhando · 1 esperando você" e a linha do destaque, com timer desde `since`.
- **Dynamic Island**: compacta com o asterisco à esquerda e contagem à direita; mínima com o asterisco colorido pelo estado; expandida com destaque, contagem e botão "Abrir" (deep link).
- **Ciclo de vida**:
  - **Início**: quando algum agente passa a `working` e não há atividade ativa. Com o app em primeiro plano, `Activity.request(…, pushType: .token)`; com o app fora, push-to-start (`apns-push-type: liveactivity`, `event: start`, token de push-to-start obtido em `Activity<…>.pushToStartTokenUpdates`).
  - **Atualização**: `event: update`, `apns-topic: com.example.mocha.push-type.liveactivity`, `apns-priority: 5`, e `10` só quando `waiting` passa de 0 para ≥ 1. No máximo uma atualização a cada 10 s, exceto a transição para `blocked`.
  - **Fim**: quando nenhum agente está `working`/`blocked` por 60 s, `event: end` com o estado final ("Tudo pronto") e `dismissal-date` = agora + 15 min.
  - **Limite de 8 h**: ao completar 7 h 50 min, o daemon encerra e inicia outra com push-to-start.
- **Tokens**: o app observa `pushTokenUpdates` de cada atividade e `pushToStartTokenUpdates`, e envia `registerLiveActivity`. Sem conexão, guarda o token e reenvia na próxima conexão.
- Payload ≤ 4 KB: o título do destaque vai truncado em 60 caracteres.

---

## §8 Aprovações e perguntas (1b)

Mecanismo validado pelo spike S3 no Claude Code 2.1.283. Payloads, respostas e linhas do tempo reais em `MochaKit/Fixtures/hooks/`.

### §8.1 Mecanismo: `PermissionRequest` segurado

- Todo diálogo em que o Claude espera uma decisão no terminal dispara o hook `PermissionRequest` no mesmo instante em que o diálogo aparece: a aprovação de ferramenta (Bash, Write, Edit, MCP…) **e** o seletor do `AskUserQuestion`. O hook (HTTP, timeout 590 s, §3.3.1) fica pendente no `HookServer` enquanto o diálogo continua respondível no Mac. Vale a primeira resposta, dos dois lados.
- Não há hook `PreToolUse` do Mocha nem fallback por `agent.send_keys`.
- Um agente tem no máximo um pedido pendente. Com várias ferramentas na mesma resposta, o Claude mostra um diálogo por vez e só dispara o `PermissionRequest` seguinte depois que o anterior se resolve.
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
   - chega `PermissionRequest`, `UserPromptSubmit`, `Stop` ou `SessionEnd` da mesma sessão.
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

- O `PendingStore` mantém os pedidos em memória, no máximo um por sessão. Reiniciar o daemon descarta os pedidos, e os hooks pendentes caem por conexão fechada: para o Claude isso é um erro não bloqueante, e o diálogo do terminal continua.
- `pendingCount` por agente alimenta a gaveta e o `waiting` da Live Activity.

---

## §9 Terminal (fases 2 e 3)

### §9.1 SSH (fase 2)

- Emulador `SwiftTerm` (UIKit `TerminalView` embrulhado em SwiftUI). SSH com `Citadel` (swift-nio-ssh).
- **Chave**: P-256 criada na Secure Enclave (`SecureEnclave.P256.Signing.PrivateKey`, com `.biometryCurrentSet`), usada como `ecdsa-sha2-nistp256` via `NIOSSHPrivateKey(secureEnclaveP256Key:)`. Se o Citadel não expuser isso, um delegate de autenticação próprio.
- A chave pública aparece em Ajustes para colar em `~/.ssh/authorized_keys` do Mac. O Remote Login precisa estar ligado no Mac (bloqueio B5).
- **Host**: o mesmo nome MagicDNS, porta 22, dentro do tailnet.
- **Sessão**: `herdr agent attach <paneId>` no pane do chat atual (botão `>_` no composer) ou `herdr` puro pela gaveta. Ao reconectar, reanexa no mesmo alvo.
- **Barra de teclas** (`terminal.png`): Ctrl (trava), Esc, Tab, setas (joystick), prefixo do Herdr (`ctrl+space`), colar, histórico e recolher teclado. Cores em §6.2.

### §9.2 Mosh (fase 3)

- Build do mosh para iOS a partir de `blinksh/build-mosh` + `blinksh/mosh` (GPLv3; aceitável num app que não é distribuído), com libprotobuf.
- Bootstrap: `mosh-server new` via SSH (Citadel), com a chave e a porta devolvidas ligadas ao `mosh-client` embutido. O Mac precisa do `mosh-server` (`brew install mosh`).
- O transporte é trocável na mesma tela de terminal (SSH ou Mosh).

---

## §10 Segurança

- O daemon só escuta em `127.0.0.1` ou num socket Unix 0600. A exposição ao iPhone é só pelo `tailscale serve` (tailnet privada, TLS).
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
| Swift Testing | testes | — | todas |
| `SwiftTerm` (github.com/migueldeicaza/SwiftTerm) | app | MIT | 2 |
| `Citadel` (github.com/orlandos-nl/Citadel) | app | MIT | 2 |
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
| Orçamento de atualização da Live Activity | Prioridade 5 por padrão e limite de uma atualização a cada 10 s (§7.3) |
| `moshi-hook` competindo pelos hooks | Detecção no `doctor`/`install-hooks` e bloqueio B7 |
| Arquivos de transcript muito grandes | Índice de offsets, leitura pelo fim, prévias truncadas (§3.2.3) |
| O Herdr ignora parâmetros desconhecidos, e o alvo omitido cai no pane focado do João | Tipos de parâmetro com os nomes exatos de `herdr-api.schema.json`, alvo sempre explícito, teste de contrato contra o schema; o daemon não chama métodos de foco, split, layout nem escrita de workspace |
| Troca de sessão (`/clear`) sem evento do Herdr | Detecção por `pane_updated`, `agent.get` e reconciliação (§3.1.3); hook `SessionStart` a partir da 1a-final |
| Build do Xcode e perfil com push expiram | Perfil de desenvolvimento de ~1 ano; `doctor` do app em Ajustes mostra a validade quando disponível |
