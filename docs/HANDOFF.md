# Handoff do orquestrador

## WP-X2: integração da 1a-final

- **Preparado** (2026-09-26, à noite):
  - `mochad` da `fase/1a-final` (`926af42`) instalado em `~/.local/bin/mochad`, assinado pelo time com `com.joaoalves.mochad`; LaunchAgent `com.joaoalves.mochad` rodando; log em `~/Library/Logs/Mocha/mochad.log`.
  - `mochad doctor` verde, com o APNs pronto (key `<KEY_ID>`, time `<TEAM_ID>`). Avisos esperados: hooks até o passo 1 abaixo e moshi-hook instalado até o B7.
  - Serve sem mudança: `https://mac-mini.tail1234.ts.net` → `http://127.0.0.1:47421`.
  - App assinado da mesma fase (`com.example.mocha`, `aps-environment` development), instalado no iPhone 14 por `devicectl`. Build em `build/DerivedData/Build/Products/Debug-iphoneos/Mocha.app`, log em `build/verify/x2-device-build.log`.
- **O que o João faz, em ordem**:
  1. No Mac, `mochad install-hooks`. Ele escreve em `~/.claude/settings.json`, com backup em `settings.json.mocha-bak`, e o `mochad doctor` passa a mostrar os hooks ✅. Enquanto o moshi-hook estiver instalado (B7), os alertas chegam em dobro, do Moshi e do Mocha.
  2. B6: liga o VPN On Demand no app Tailscale do iPhone.
  3. Abre o Mocha no iPhone. O app da fase já foi instalado por cima do anterior, e o pareamento continua.
  4. Aceita a permissão de notificação na primeira conexão. Depois, `mochad devices` e `mochad apns test --device <id>`.
  5. Percorre o checklist do bloco "### WP-X2" do `docs/PLANO.md`. Os agentes novos do `+` abrem sessões novas do Claude, que já nascem com os hooks do passo 1.
- **Depois do X2**: com o ok do João, `fase/1a-final` entra em `main`. O B7 (remover o moshi-hook) fica a critério dele, antes da 1b.

## Estado

- Fase **1a-final**, branch `fase/1a-final` (criada da `fase/1a-core`; `main` em `fb22739`). Sem remoto. WPs de código feitos e mergeados: M5, I6, I7, M6, I11, M6-fix e M12 (commits na tabela de status do `docs/PLANO.md`). `scripts/test.sh`, `build-daemon.sh` e `build-app.sh` verdes em `926af42`. Worktree aberto: `mock-subagentes` (fase subagentes, sem commit, esperando o ok do João no mock). Simuladores desligados.
- Ledger: `~/.local/state/claude-ledgers/2026-09-26-mocha-fase-1a-core.md`.
- **Próximo passo**: o checklist do WP-X2 no iPhone (seção acima). Com o ok do João, merge em `main`; depois, a fase subagentes, a partir do ok no mock.
- **Medições pendentes** (numa janela sem build, sem nenhum agente rodando):
  - M2b: `BigTranscriptMetaPerformanceTests` < 50 ms e `BigTranscriptPerformanceTests` < 300 ms;
  - I4 e I5: signpost do chat de 2.000 itens (comandos no relatório do I5, com `-chat-perf-sweep`), incluindo os blocos visíveis de uma mensagem de 20 KB;
  - M4: `mochad run` por 10 min com RSS < 30 MB.
- **Instável**: `HerdrBridgeTests.bootstrapSubscribesThenPingsThenSnapshots` (e às vezes `TranscriptStoreFollowTests`) falha em execução completa com a máquina carregada e passa isolada. Falta achar a causa raiz.
- **Regra de máquina**: no máximo 2 simuladores ligados. Cinco estouraram o limite de 1333 processos por usuário e travaram todo fork.
- **Propostas dos WPs, não aplicadas** (fora de escopo; decidir na 1a-final ou no X1):
  - deep link por sessão para abrir chat arquivado;
  - `ChatHeaderBar` truncando no meio;
  - `login-social` do demo terminando em `idle` para a tela 05b;
  - ícones da gaveta e do pareamento no `DesignSystem`;
  - arredondamento do `Typography.mono` (14,67 → 15);
  - rota por prefixo no `HttpRouter` para o `LocalControl`;
  - Keychain `AfterFirstUnlockThisDeviceOnly`.

## Commits desta sessão (`fase/1a-core`)

| O quê | Commit |
|---|---|
| WP-M1 (merge `f749a7c`) | `a95f3c7`, `c54fabd`, `146201b`, `1303675` |
| SPEC e PLANO do M1 (reconexão no bridge, HEAD destacado, follow-ups no M6/M8) | `261b262`, `78fdbb5`, `4444852` |
| SPEC do I1 (JetBrains Mono na §11, medidas do print, flags `-demo-unpaired`/`-preview`) | `9c91cfe`, `776845f` |
| WP-M2 (merge `6163f61`) | `b34bf17`, `7f55ad2`, `0ea19a6`, `52dbc30` |
| `Package.swift` (deps dos testes do daemon) e remoção do `MochaTestSupport/Placeholder.swift` | `d039870`, `e96efce` |
| SPEC e PLANO do M2 (Claude Code 2.1.283, paginação, meta; constante no M4) | `c0fba01`, `e81c283`, `cdadb31` |
| Referências novas e mock aprovado | `b31ed5e`, `9ed758e` |
| Passo 1 (contratos do escopo B: SPEC, AGENTS, PLANO, PNGs do mock, MochaProtocol) | `2fba5f9`, `be6bd8b`, `5434975`, `d59f9d8`, `4da7f18`, `6ebf98a`, `ad32f29`, `0e28ceb` |
| Onda 1.A': WP-D2 (merge `cb5a698`), WP-M2b (merge `97e13b4`), WP-I1 Fases A e B (merge `cec977f`) e `-demo-empty` | `9e28bea`, `1d5c283` |

Validação: `scripts/test.sh` verde na `fase/1a-core` depois do M2 (protocolo 33, transcript 40, Herdr 44, demo 36, daemon 164, client 1). Medição do M2 em release, sem build: primeira página de 50 MB em 32,5 ms (frio) e ~10 ms.

## Decisões tomadas sem o João

Opção mais simples e fiel ao mock e ao Moshi, conforme o mandato da noite. Confira de manhã.

- **Protocolo**: `ChatTarget` (`agentId` ou `sessionId` achatado no payload); `setForeground` segue só com `agentId`. `preview` e `activity` desconhecidos decodificam como `nil` sem derrubar a árvore. Até o M10, `archive` responde `unknownType`.
- **Home**: regra das 6 h aplicada ao pé da letra (início da sessão há mais de 6 h → ARQUIVADOS); arrastar para arquivar só em CONCLUÍDOS; cartões de `ArchivedSession` não arrastam; preview `nil` vira "Sessão limpa"; retenção de 7 dias ou 50 sessões.
- **Chat de sessão encerrada**: pílula "Sessão encerrada · só leitura" no lugar do composer.
- **Plano e conta**: chaves `oauthAccount.organizationRateLimitTier` e `oauthAccount.emailAddress` inferidas do HANDOFF; o daemon lê em runtime, os testes usam fixture sintética (`MochaKit/Fixtures/usage/claude.json`). **Conferir.**
- **Janela de contexto**: 1M para opus-4-7+, opus-5*, fable* e sonnet-5*; 200k para o resto.
- **Terminal (fase 2)**: abre por "Abrir terminal" no detalhe e pelas tabs de shell da gaveta.
- **Código**: lógica de apresentação (nomes de modelo, ferramentas, tempos relativos) em `MochaClient/Presentation/`, testável.
- **Demo (D2)**: host "MacBook"; o chat `login-social` alimenta as telas 5/5b/6; `receitas` é o chat longo (2000 itens); a sessão arquivada tem `ChatMeta.status` `idle`; `-demo-empty` troca as tabs por "zsh" e usa uso de 3%/64%.
- **Ferramentas**: simuladores iPhone 17e (390×844 pt, igual ao mock), um por WP de UI.

**Confirmadas pelo João (2026-09-26, de manhã)**: o `mochad` instalado no WP-X1 lê o plano e a conta do `~/.claude.json`; o critério de 16 ms do markdown vale só para os blocos visíveis no chat; a folha de Uso flutuante do iOS 26 (8 pt de margem, ~96% da escala do mock) fica como está.

## Decisões do João (2026-09-26)

- Visual: o mock aprovado vale; o Moshi é a base.
- Home (central de agentes) é a tela inicial. O chat abre por cima (push). Voltar: arrastar da borda ou tocar no disco de status. A gaveta abre pela bússola do chat e pelo botão esquerdo da Home, sem gesto de borda.
- Seções da Home (regra do Moshi):
  - PRECISA DE VOCÊ: `blocked`;
  - TRABALHANDO: `working`;
  - CONCLUÍDOS: turno terminado há menos de 10 min;
  - ARQUIVADOS: mais de 10 min, sessão com mais de 6 h, sessão substituída por /clear, pane fechado ou card arrastado.
- Card:
  - anel = % de contexto restante, com o arco girando enquanto trabalha;
  - 2ª linha = última ferramenta, ou "Precisa de você · <ferramenta>".
- Uso do plano:
  - só 5h e 7d, do cache local do plugin `herdr-agent-usage`, sem token e sem a linha Fable;
  - mostra "atualizado há X";
  - ritmo = usado − decorrido, com tolerância de 5 pontos.
- Composer:
  - uma linha quando recolhido; ao focar, até 6 linhas mais a linha de botões;
  - o teclado fecha ao rolar, tocar fora, abrir a gaveta ou enviar.
- Parar fica na linha de status "Trabalhando… (Xm Ys)" no fim da lista; enviar continua enviando durante o turno.
- O detalhe do agente é uma folha: abre tocando no título do header ou segurando o card. O sino da Inbox (1b) fica na Home.

## Pesquisa (fontes dos dados novos)

- **Contexto restante**: `100 − session_contexts.<sessionId>.used_percent` em `~/.local/state/herdr/plugins/herdr-agent-usage/claude-statusline.json` (a janela de cada sessão está em `session_models.<sessionId>`).
  - Reserva: a última linha `assistant` do transcript, somando `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` (sem `output_tokens`, sem sidechain e sem `<synthetic>`).
  - A janela do modelo vem da doc do Claude Code: Opus 4.7+, Fable e Sonnet 5 têm 1M.
- **Cota 5h/7d**: o mesmo cache, com `windows[]` (`kind` `five_hour`/`weekly`, `used_percent`, `resets_at`) e `fetched_at_unix`. O plugin grava a partir do stdin do statusLine do Claude Code.
  - O plano ("Max 20x") estaria em `~/.claude.json`, mas o classificador de permissões bloqueia a leitura desse arquivo como "Credential Exploration". Por isso ele precisa de um bloqueio novo, com fixtures fornecidas ou autorizadas pelo João.
- **Moshi**: o arquivamento é por tempo (10 min depois do fim do turno, ou 6 h). Os textos "Session started", "Claude resumed" e "Session cleared" vêm do `SessionStart`.

## Replanejamento da 1a-core (proposto, revisado por subagente; aguarda aprovação)

### Decisão pendente do João: escopo

- **A (recomendada pela revisão)**:
  - na 1a-core, a Home mostra só os agentes vivos, com ARQUIVADOS = ocioso há mais de 10 min, calculado no app;
  - vão para a 1a-final: o Uso do plano, as sessões encerradas persistentes (clear, pane fechado, 6 h, arrastar), a mensagem `archive` e o chat só de leitura (`openChat` por sessão).
- **B**: tudo na 1a-core, com um WP de daemon novo (`MochaDaemonCore/Sessions/` e `Usage/`) e o bloqueio B9 (fixtures redigidas de `~/.claude.json` e do cache do plugin).

### Passo 1: contratos (orquestrador, em `fase/1a-core`)

**SPEC**
- **Produto e fluxos:**
  - §1.1: a Home é a tela principal;
  - §1.3: acrescentar a Home (e o Uso, conforme o escopo);
  - §2.3: "Abrir o app" leva à Home, e "Abrir um chat" usa o alvo novo.
- **Dados do transcript (§3.2 e §4.1.1):** o `TranscriptMeta` ganha:
  - `preview`: a última mensagem com o autor, com um corte fixo na §5.2;
  - `activity`: `{toolName, summary}?` do último `toolCall` `running` (ou do último);
  - o contexto usado, com a janela da sessão;
  - `turnStartedAt`: a hora do último `userPrompt` que não veio de `queued_command`;
  - `turnEndedAt`: o último `turn_duration`.
- **Deltas (§4.1.1):** o `.meta` passa a incluir os campos novos, e o `chatMeta` só sai quando muda um campo do `ChatMeta`.
- **Composição (§4.1.2):**
  - o `SessionHub` sobrescreve também `preview`, `activity`, `contextLeftPercent`, `turnStartedAt` e `turnEndedAt`;
  - o hub assina o transcript de todo agente `working`/`blocked`, mesmo sem chat aberto, para a Home se atualizar;
  - o contexto vem primeiro do cache do plugin.
- **Protocolo (§5.2 e §5.3):**
  - campos novos no `AgentSummary`;
  - se o escopo for B: o evento `archived{sessions}`, separado do `tree`; o evento `usage`; a mensagem `archive`; e um `ChatTarget` (agente ou sessão) em `openChat`/`chatPage`/`chatAppend`/`chatUpdate`/`chatMeta`/`closeChat`/`setForeground`, com as regras da §5.3.1;
  - `herdrConnected` passa a vir num evento, porque hoje só chega no `hello`.
- **Seções da Home:**
  - o daemon manda `turnEndedAt` (e `archivedReason`, no escopo B);
  - o app aplica o corte de 10 min com o relógio local, com a precedência blocked > working > arquivado > concluído;
  - a Home filtra `kind == "claude"`.
- **Uso (se entrar):** o app calcula o decorrido a partir de `resetsAt` e do tipo da janela. O daemon observa o diretório do cache, que é gravado por rename, e reabre o arquivo.
- **App:**
  - §6.1: Home como raiz, os módulos `Home/`, `AgentDetail/` e `Usage/`;
  - §6.2: os tokens novos do mock, inclusive os de vidro (`gl-home`, `gl-pill`, `gl-hero`, `gl-black`) e os gradientes de brilho;
  - o mock passa a valer sobre os prints quando os dois divergem;
  - §6.3: todas as telas, com o sino da Inbox na Home.
- **Riscos:** §12 ganha a dependência do cache privado de um plugin.

**AGENTS e PLANO**
- AGENTS (linhas 7 e 79): a referência visual passa a ser o mock, com PNGs em `docs/design/mock/<n>.png`, gerados pelo orquestrador (ferramenta WKWebView em `/private/tmp/claude-501/-Users-joaoalves-Developer/7c200af0-61d3-43c2-a663-14488d6c135b/scratchpad/design/`: `build.py` e `snap`).
- PLANO:
  - "Visão das fases";
  - os blocos do I1, I3, I4, I5, M3, M4 e X1;
  - os WPs novos (D2, M2b, I12, e o de Sessions/Usage no escopo B) na tabela de status e no "Depende de" do X1.

**Código e fixtures:** `MochaProtocol` e as fixtures com os tipos novos, e `scripts/test.sh` verde.

### Ondas (revisadas)

- **1.A'**:
  - **WP-D2**: o demo com os campos novos, e `archive`/`openChat` por sessão se o escopo for B.
  - **WP-M2b**: o `TranscriptMeta` novo. Dono: `MochaTranscript/`, `MochaDaemonCore/Transcript/`, `MochaTestSupport/Transcript/` e `Fixtures/transcripts/expected/`.
  - **WP-I1, Fase B refeita pelo mock:**
    - o I1 entrega **todo** o `AppSession`, a navegação, o design system e os encaixes `HomeScreen`, `AgentDetailSheet`, `UsageSheet`, `SettingsScreen`, `DrawerScreen`, `ChatScreen(target:)` e `MarkdownView(markdown:)`;
    - aceite: arrastar da borda volta à Home, conferido no aparelho.
- **1.B**:
  - **WP-M3**: com a composição nova, assinando os transcripts dos agentes `working`/`blocked`.
  - **WP-I12**: dono de `App/Sources/Home/`, `AgentDetail/` e `Usage/`, sem tocar em `AppShell/` nem `DesignSystem/`.
  - **WP-I4**: markdown pelo mock. Veio para a 1.B porque o I5 depende dele.
- **1.C**:
  - **WP-M4**: com o bloco atualizado.
  - **WP-I3**: gaveta pelo mock, sem gesto de borda, sem tocar em `AppShell/`.
  - **WP-I5**: telas 5 a 8 do mock. A tela 10 é da 1b.
- **1.D**: WP-I2 (conexão, pareamento e ajustes; a data do pareamento fica guardada no app), mais o WP de Sessions/Usage no escopo B.
- **1.E**: WP-X1, com o checklist novo (Home, seções, anel, teclado, composer e, no escopo B, uso e arquivados).

## Cuidados

- O Bash do orquestrador guarda o `cd`. Use caminhos absolutos ou `git -C`.
- Um `index.lock` passageiro aparece nos worktrees (o `herdr-reviewr` lê o git). Se um commit falhar por lock, confira `git log` e repita.
- Para remover um worktree:
  1. saia do `herdr-reviewr` com `q` no pane raiz do workspace do worktree;
  2. feche as tabs;
  3. rode `herdr worktree remove --workspace <id>`.
- Symlink da fixture grande num worktree: `MochaKit/Fixtures/transcripts/generated` está no `.git/info/exclude`.
- Tab `tests` aberta no workspace Mocha (`w1E:t2`), para validar a fase.
- Na UI, antes da verificação visual pesada, ofereça ao João testar no iPhone:
  1. `scripts/build-device.sh` numa tab do worktree;
  2. `xcrun devicectl device install app --device <udid-do-iphone> <app>`;
  3. `xcrun devicectl device process launch --device … --terminate-existing com.example.mocha -demo`.
- No Xcode 27, o primeiro `simctl openurl` com esquema próprio abre o aviso "Open in Mocha?" e trava até alguém tocar.
