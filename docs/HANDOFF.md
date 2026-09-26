# Handoff do orquestrador

## Estado

- Fase: **1a-core**, branch `fase/1a-core` (a partir de `main` em `ed3f2f0`). Sem remoto.
- **Onda 1.0 concluída.** A próxima é a **Onda 1.A**: WP-M1 · WP-M2 · WP-I1, em paralelo, um worktree do Herdr por WP (PLANO, "Como o orquestrador trabalha" e "Fase 1a-core"; AGENTS, Orquestrador item 7).
- Nenhum WP em andamento. Nenhum worktree aberto (`git worktree list` só mostra o principal). A branch `wp/D1` ficou, já mergeada.

## Onda 1.0: commits

| O quê | Commit |
|---|---|
| `.gitignore` com `.claude/worktrees/` | `abdf5ed` |
| SPEC: §4.1.1 (interfaces internas), §4.1.2 (composição), §4.8 (canal local), §5.3.1 (regras do servidor), contrato de conexão e `AppSession` na §6.1 | `d798eee`, `901bba8`, `3563f7f` |
| Fixtures de cursor `<sessionId>:<offset>` | `964ddc4`, `0cc471b` |
| `Package.swift`: `MochaTestSupport` compartilhado | `f1521c5` |
| Trava do `xcodebuild` (`scripts/lib/xcode-lock.sh`) e `SourcePackages` compartilhado | `2c38ec6` |
| Esquema `Mocha Demo`, `mocha://` e `NSCameraUsageDescription` | `816e2d1` |
| PLANO e AGENTS da 1a-core (worktree por WP, blocos dos WPs revisados) | `536866f` |
| WP-D1 (merge `e13bd0e`) | `393ec96`, `0ecf4d2`, `f1045ef` |

Validação no fim da onda: `scripts/test.sh` passou (protocolo 33 testes, demo 36, daemon 90) e `scripts/build-app.sh` compilou.

## Autorizações do João para esta fase

- **B4**: `mochad serve-setup --apply` no WP-X1 (registrado no PLANO).
- **WP-M4**:
  - LaunchAgent de teste (install → `launchctl print` → uninstall);
  - `mochad run` por ~10 min numa tab do Herdr lendo o Herdr real, para medir o RSS;
  - `mochad apns test` com token falso.
- **WP-M2**: ler os transcripts reais de `~/.claude/projects`, só para contar tipos e ver a versão do Claude.
- **WP-I1**: empacotar JetBrains Mono ou Geist Mono (OFL) e registrar na §11 se a comparação com o print apontar uma delas.
- **Pendentes do WP-X1**:
  - B8 (checklist no iPhone);
  - iPhone 14 pareado com o Xcode, no mesmo Wi-Fi ou no cabo.

## Dados para os briefs da Onda 1.A em diante

**Worktree**
- Criar com `herdr worktree create --cwd /Users/joaoalves/Developer/mocha --branch wp/<id> --base fase/1a-core --path /Users/joaoalves/Developer/mocha/.claude/worktrees/<id> --label "mocha <id>" --no-focus`. O JSON devolve `result.workspace.workspace_id`.
- Remover com `herdr worktree remove --workspace <workspace_id>`.
- Copiar `Config/Signing.xcconfig` para o worktree.
- No M2, criar `MochaKit/Fixtures/transcripts/generated` como symlink para o do repositório principal (o `big-50mb.jsonl` já existe lá).

**Simuladores** (um por WP de app numa onda):

| Simulador | UDID | Uso |
|---|---|---|
| iPhone 17 | `D45EF07B-BB8E-4290-9234-50AF2EF2BCD7` | I1, depois I2 |
| iPhone 17e | `54DC817A-9A00-4E27-B845-EE9B89DB6F30` | I4 |
| iPhone 18 Pro | `6F9B436B-962D-4762-A5E1-5F70F7B1885C` | I3, depois I5 |

**Demo do WP-D1** (`MochaKit/Sources/MochaDemo/`), para o I1, o I3 e o I5:
- `try DemoServerConnection(options: DemoOptions(...))` com:

  | Opção | Padrão | Efeito |
  |---|---|---|
  | `startsPaired` | `true` | `false` abre em `pairingRequired(nil)` |
  | `runsScript` | `false` | liga o roteiro |
  | `connectDelay` | 400 ms | espera até o handshake |
  | `echoDelay` | 1 s | espera até o eco do prompt |
  | `replyDelay` | 2 s | espera até a resposta |
  | `scriptTimeScale` | 1 | multiplica os tempos do roteiro |

- Mapeamento: `-demo` → `DemoOptions()`; `-demo-script` → `runsScript: true`. O I1 decide uma flag para as telas de pareamento, por exemplo `-demo-unpaired` → `startsPaired: false`.
- Chat de 2.000 itens: agente `w3:p3` ("Refatoração da API de receitas"), tab `w3:t3`.
- Roteiro, com os tempos contados a partir do primeiro `.connected`:

  | Tempo | Evento |
  |---|---|
  | 3 s | worktree `w6` "feed-rss" aninhado sob `w2`, com o agente `w6:p1` |
  | 5–13 s | turno em `w1:p1`: `chatAppend` contínuo; o Bash `script-turn-bash` vai de `running` a `succeeded` por `chatUpdate` aos 11 s; `chatMeta` com título novo aos 12 s |
  | 17 s | `/clear` em `w6:p1` (`sessionId` novo) |
  | 21 s | `pane_moved`: `w5:p1` → `w5:p2`; `openChat` com o id antigo devolve `agentId` `w5:p2` |
  | 25–27,5 s | queda e volta da conexão, com `hello-2` |

  `chatAppend`, `chatUpdate` e `chatMeta` só saem para chats abertos. Os chats abertos são esquecidos a cada handshake.

**§§ extras nos briefs** (além das citadas no bloco do WP):
- M1 e M2: §4.1.1;
- M3: §3.1.3, §3.1.4, §4.4, §5.5, §10;
- M4: §3.1.1, §3.2.2, §3.3, §4.3, §4.5, §4.6, §7.1, §10;
- I1: §2.2 e §6.1 (`AppSession`);
- I2: §5.1, §5.3;
- I3 e I5: §6.2, §5.3;
- I5: §2.3.

## Cuidados

- O Bash do orquestrador guarda o `cd`. Use caminhos absolutos ou `git -C`, para não ficar dentro de um worktree ao fazer merge ou remover.
- Mudar o contrato de um arquivo do orquestrador quebra testes que dependem dele (o cursor novo quebrou `FixtureRoundTripTests`, e o agregado `unknown` quebrou `tree.json`). Rode `scripts/test.sh` depois de cada mudança nos seus arquivos.
- Os WPs de UI: antes da verificação visual pesada, ofereça ao João testar no iPhone.

## Próximo passo

Abrir a Onda 1.A:
1. Criar os worktrees `M1`, `M2` e `I1`.
2. Delegar os três em paralelo, com o bloco do WP no PLANO, as §§, os dados acima e o caminho do worktree.
3. Revisar, commitar em `wp/<id>`, fazer `merge --no-ff` na `fase/1a-core`, validar e mandar o resumo da onda ao João.
