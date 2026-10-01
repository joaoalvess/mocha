# Mocha: regras para agentes de IA

O trabalho é feito por um **orquestrador** (a sessão principal) que delega **pacotes de trabalho (WPs)** a **subagentes**. Leia a seção do seu papel e as seções comuns.

- `docs/SPEC.md`: fonte da verdade (o quê e como).
- `docs/PLANO.md`: fases, ondas, WPs, critérios de aceite, bloqueios e status.
- `docs/design/mock.html` e as capturas 3x em `docs/design/mock/NN-nome.png`: referência visual obrigatória para toda UI (SPEC §6.2). Os prints do Moshi em `docs/referencias/moshi/` (só no repositório principal, fora do git) são a base do mock; quando divergem, vale o mock.

## Orquestrador

1. Leia este arquivo, a SPEC inteira e a fase atual do PLANO.
2. Apresente ao João um plano curto da fase: ondas, WPs por onda, bloqueios que precisam dele agora. Espere a aprovação antes de delegar.
3. Peça todos os bloqueios (`Bx`) da fase de uma vez, no começo.
4. **Fase 0**: o WP0.1 é feito por você mesmo, direto em `main` (`git init` e o commit dos docs primeiro). Só depois você cria a branch `fase/0`. Nas outras fases, você cria `fase/<id>` a partir de `main` antes de delegar.
5. Delegue cada WP a um subagente com: o bloco do WP no PLANO, as §§ da SPEC citadas, a lista de arquivos existentes relevantes, a seção "Subagente" deste arquivo e, a partir da 1a-core, o caminho absoluto do worktree do WP. No máximo 3 subagentes ao mesmo tempo, spikes incluídos.
6. Você é o dono de `MochaKit/Package.swift`, `project.yml`, `MochaKit/Sources/MochaProtocol/**`, `MochaKit/Fixtures/protocol/**`, `App/Info.plist`, `App/Mocha.entitlements`, `Widgets/Info.plist`, `AGENTS.md`, `.gitignore`, `docs/SPEC.md`, `docs/PLANO.md` e `docs/HANDOFF.md`. Aplique você as mudanças que os subagentes propuserem nesses arquivos. A exceção é um arquivo que o bloco do WP no PLANO entrega ao WP, só naquela onda. Spikes escrevem só no diretório dono listado no PLANO, que inclui o próprio `docs/spikes/<Sx>.md`.
7. **Worktree por WP** (a partir da 1a-core):
   - no início da onda, crie um worktree do Herdr por WP: `herdr worktree create --cwd ~/Developer/mocha --branch wp/<id> --base fase/<fase> --path ~/Developer/mocha/.claude/worktrees/<id> --no-focus`;
   - copie `Config/Signing.xcconfig` e o `.env` do repositório principal para o worktree;
   - se o WP precisa da fixture grande, ligue `MochaKit/Fixtures/transcripts/generated/` do worktree por symlink ao mesmo diretório do repositório principal;
   - no fim do WP, revise, commite em `wp/<id>`, faça `git merge --no-ff wp/<id>` na branch da fase e rode `herdr worktree remove --workspace <id do workspace>`, que mantém a branch;
   - mudança num arquivo seu no meio de uma onda: aplique no worktree do WP que precisa dela, em commit separado;
   - antes de abrir ou remover um worktree, confira que nenhum pane está com `cd` dentro dele (bug do Herdr 0.9.1: o `worktree remove` fecharia o workspace do repositório).
8. Revise cada entrega contra os critérios de aceite, rode a validação (ou delegue a um subagente de validação, que devolve só passou/falhou e os trechos de erro), faça os commits do WP e atualize a tabela de status do PLANO.
9. Ao fim de cada spike, aplique no PLANO e na SPEC o que o relatório lista em "Impacto".
10. Não delegue decisões de arquitetura nem a revisão final.

## Subagente

1. Trabalhe só no caminho absoluto do worktree que o orquestrador der. Nunca edite o repositório principal nem outro worktree.
2. Dentro dele, trabalhe só no **diretório dono** do seu WP. Precisa mudar um arquivo fora dele (inclusive os do orquestrador)? Descreva a mudança como diff no relatório.
3. Siga a SPEC. Se algo da SPEC estiver errado ou impossível, pare e reporte; não improvise contrato.
4. **Não faça commit.** O orquestrador commita.
5. Rode os testes do seu escopo antes de entregar (§Builds e testes).
6. Entregue o relatório no formato do fim deste arquivo.

## Ambiente

- macOS 27, Xcode 27 (Swift 6.4), Apple M1 com 8 GB. O shell do João é fish; scripts do repositório são bash.
- Ferramentas:
  - `/opt/homebrew/bin`: `xcodegen`, `herdr`, `rg`, `fd`, `gh`.
  - `/usr/local/bin/tailscale` (wrapper; o código do `mochad` chama `/Applications/Tailscale.app/Contents/MacOS/tailscale`, §4.5).
  - `/usr/bin/jq`.
  - Se o `PATH` estiver vazio num subagente, use caminhos absolutos.
- O João roda tudo dentro do Herdr (`HERDR_ENV=1`). Processos longos (daemon em primeiro plano, `log stream`, app no simulador) rodam numa tab do Herdr, não no Bash do agente:
  1. `herdr tab create --workspace <id> --cwd <caminho> --label <o-que> --no-focus`. O subagente usa o workspace do próprio worktree (em `herdr workspace list`, o que tem `.worktree.checkout_path` igual ao caminho dele) e `--cwd` no worktree. O orquestrador usa o workspace da própria sessão (`$HERDR_WORKSPACE_ID`) e `--cwd ~/Developer/mocha`;
  2. `herdr pane run <pane> "<comando>"`;
  3. leia a saída com `herdr pane read --source recent-unwrapped`.
  Deixe a tab aberta enquanto o processo roda.
- **Scripts**:
  - `scripts/bootstrap.sh`: gera o `Mocha.xcodeproj`;
  - `scripts/test.sh`: testes do MochaKit;
  - `scripts/build-app.sh`: build para o simulador;
  - `scripts/build-device.sh`: build assinado para o iPhone;
  - `scripts/lib/xcode-lock.sh`: trava que os dois scripts de build do app pegam antes do `xcodebuild`;
  - `scripts/build-daemon.sh`: build release do `mochad`;
  - `scripts/run-daemon.sh`: `mochad run` em primeiro plano.
  - `scripts/check-claude-update.sh`: valida o Claude Code instalado contra o Mocha (§Atualização do Claude Code); com `--hook`, só avisa se a versão é nova.
  - `scripts/check-codex-update.sh`: valida o Codex instalado contra o Mocha (§Atualização do Codex); com `--hook`, só avisa se a versão é nova.

## Código

- Swift 6 com strict concurrency completo. Estado mutável compartilhado fica em `actor`; UI em `@MainActor` com `@Observable`.
- Identificadores em inglês. Texto de UI em português do Brasil com acentuação correta.
- Sem comentários no código; nomes explicam o código.
- Sem `try!`, `fatalError` ou force unwrap em código de produção (testes podem).
- Sem `@unchecked Sendable`, a não ser justificado no relatório.
- Dependências: só as da SPEC §11. Uma nova exige entrar na §11 antes, com aprovação do João.
- Não mexa em arquivos fora do escopo. Algo fora do escopo precisa de correção? Descreva no relatório.

## Builds e testes

- Swift Testing (`import Testing`).
- Testes unitários nunca usam o Herdr real, o Claude real, a rede, o APNs nem o Keychain real: use `MochaTestSupport` e `MochaKit/Fixtures/`.
- Testes que tocam o sistema real levam a tag `.integration` e só rodam com `MOCHA_INTEGRATION=1`.
- Cada worktree tem o próprio `.build` e o próprio `build/DerivedData`. Rode `scripts/test.sh` no worktree, sem `--scratch-path`.
- `xcodebuild` só pelos scripts (`build-app.sh`, `build-device.sh`). Eles pegam a trava em `~/Library/Caches/com.joaoalves.mocha/xcodebuild.lock`, e assim só um `xcodebuild` roda por vez na máquina. Os pacotes clonados ficam em `~/Library/Caches/com.joaoalves.mocha/SourcePackages`, compartilhados entre os worktrees.
- Medições de desempenho (tempo de página, `signpost`, RSS) só rodam quando o orquestrador libera a janela sem nenhum build na máquina.
- **UI**:
  - simulador: use o UDID que o orquestrador der, sempre com `xcrun simctl … <udid>`, nunca `booted`;
  - compare capturas do simulador (`xcrun simctl io <udid> screenshot <arquivo>`) com as capturas do mock em `docs/design/mock/` (mesma resolução: 1170 × 2532 no iPhone 17e, que tem os 390 × 844 pt do iPhone 14 do João) e liste as diferenças no relatório; as medidas estão no CSS de `docs/design/mock.html` (1 px = 1 pt);
  - deep links se testam pelo argumento de launch `-open-url <url>` e por teste unitário; nunca rode `xcrun simctl openurl` com o esquema `mocha://` (o aviso "Open in Mocha?" trava o simulador);
  - cores exatamente as da SPEC §6.2;
  - antes de rodar verificação pesada de UI, o orquestrador oferece ao João testar no iPhone.

## Atualização do Claude Code

O daemon lê telas, hooks e transcripts do Claude Code, e nada disso é contrato estável: cada versão pode mudar um seletor ou um formato.

- A última versão validada é `ClaudeCodeVersion.lastValidated` (`MochaKit/Sources/MochaDaemonCore/App/ClaudeCodeVersion.swift`). O hook `SessionStart` do projeto (`.claude/settings.json`) avisa quando o `claude --version` instalado é mais novo.
- Com o aviso, antes de qualquer outro trabalho, rode `scripts/check-claude-update.sh`. Ele abre um Claude no workspace de laboratório `mocha-lab-claude-update` e roda os testes `.integration` das telas (`ClaudeScreenIntegrationTests`: rodapé, `/effort`, `/model`), do censo de transcripts reais, dos hooks e da colagem de imagem (`ClaudeImagePasteIntegrationTests`: o caminho colado vira `[Image #N]`). Se tudo passar, ele sobe a versão validada; commite em `chore(claude): validate Claude Code <versão>`.
- Se falhar, pare e reporte ao João com a tela real que o teste imprime. A correção vem com um teste de regressão feito com essa tela, e a SPEC é atualizada onde descreve o formato.
- Parser novo que leia algo do Claude Code (tela, hook, transcript) entra com um teste nessa lista.

## Atualização do Codex

O daemon fala com o Codex CLI pelo App Server, e parte do que ele usa é API experimental (`thread/settings/update`, `turn/settings/update`, `collaborationMode`): cada versão pode mudar um método, um campo ou um item.

- A última versão validada é `CodexExecutable.lastValidatedVersion` (`MochaKit/Sources/MochaDaemonCore/Codex/CodexAppServerProcess.swift`). O hook `SessionStart` do projeto (`.claude/settings.json`) avisa quando o `codex --version` instalado é mais novo.
- Com o aviso, antes de qualquer outro trabalho, rode `scripts/check-codex-update.sh`. Ele:
  - monta o lab `~/Developer/mocha-lab/codex-update/` com `CODEX_HOME` próprio;
  - abre o workspace `mocha-lab-codex-update` com o App Server do lab e um TUI `--remote`;
  - roda as suítes `.integration` de `MochaKit/Tests/MochaDaemonCoreTests/CodexIntegration/`: handshake, ciclo de uma thread com um prompt curto, censo das fixtures de `MochaKit/Fixtures/codex/` contra os eventos reais e o schema instalado, e o diff dos métodos e tipos de item contra `MochaKit/Fixtures/codex/schema/methods.json`.
  Se tudo passar, ele sobe a versão validada e atualiza a cópia do schema; commite as duas em `chore(codex): validate Codex <versão>`.
- O script nunca toca no `~/.codex`: todo `codex` roda com o `CODEX_HOME` do lab, e ele falha se o `~/.codex/config.toml` mudar. Sem login no lab: `CODEX_HOME=~/Developer/mocha-lab/codex-update/codex-home codex login`.
- Se falhar, pare e reporte ao João com o payload ou a tela real que o teste imprime. A correção vem com um teste de regressão feito com esse payload, e a §13.4 da SPEC é atualizada onde descreve o formato.
- Método novo do App Server que o daemon passe a usar entra com um teste nessa lista.

## Limites no ambiente do João

- **Herdr**:
  - o Herdr é real e está em uso;
  - é permitido: ler estado; criar e fechar os workspaces de laboratório `mocha-lab-<Sx>` (um por spike, com diretório em `~/Developer/mocha-lab/<Sx>/`, fora do repositório) e mexer neles; criar e remover os worktrees dos WPs (só o orquestrador); criar tabs para processos longos no workspace do próprio worktree ou da própria sessão do orquestrador (§Ambiente);
  - ninguém manda texto ou teclas para panes fora do próprio worktree, do próprio laboratório ou das tabs que o próprio agente criou.
- **Claude**:
  - não edite `~/.claude/settings.json`; sessões de teste usam `claude --setting-sources project,local --settings <arquivo>`;
  - o `mochad install-hooks` real roda só nos WPs de integração, com o ok do João.
- **Tailscale**: não altere a config sem o ok do João (S5 e `serve-setup`).
- **Segredos**: nunca commite a `.p8`, tokens ou segredos. Nunca os imprima no log.
- **Distribuição**: nunca faça upload para o TestFlight ou o App Store Connect sem pedido explícito do João.
- **Aparelhos**: instalar no iPhone pelo Xcode é permitido quando o WP pede.

## Git

- A branch de cada fase é `fase/<id>` (ex.: `fase/0`, `fase/1a-core`), criada a partir de `main`. A exceção é o WP0.1, feito direto em `main`.
- A partir da 1a-core, cada WP tem a branch `wp/<id>`, criada a partir da branch da fase pelo `herdr worktree create`. O orquestrador commita nela e faz `git merge --no-ff wp/<id>` na branch da fase, sem rebase.
- O merge em `main` acontece no fim da fase: para a Fase 0, quando todos os WPs e spikes estiverem concluídos e o João der o ok; nas demais, depois do checklist do WP de integração.
- Commits pequenos, em inglês, no padrão Conventional Commits com escopo:
  - `feat(daemon): …`, `feat(app): …`, `feat(protocol): …`;
  - `test(transcript): …`, `docs(spec): …`, `chore(scaffold): …`.
  O primeiro commit do repositório é `docs(spec): add spec, plan and agent rules`.
  Um ou mais commits por WP, sempre com caminhos explícitos no `git add`.
- Nunca adicione `Co-Authored-By` nem qualquer atribuição a IA.
- O remoto `origin` é o repositório público `joaoalvess/mocha` no GitHub. Push só do `main` e só quando o João pedir. `reset --hard`, `clean -f`, rebase e reescrita de histórico só com o ok do João.
- O repositório é público: segredos, valores pessoais (tailnet, UDID, IDs da conta Apple, bundle do app) e nomes de trabalho nunca entram no git. Eles ficam no `Config/Signing.xcconfig` ou no `.env`, e docs e testes usam valores de exemplo.
- Mudanças temporárias de depuração (logs, mocks, overrides) saem antes do commit.

## Contexto e retomada

- O orquestrador mantém o contexto baixo delegando:
  - builds, testes e instalações: o subagente devolve só passou/falhou e os erros relevantes;
  - leitura extensa (interfaces de SDK, código de dependências, transcripts grandes);
  - pesquisa na web.
- Ao se aproximar de **500 mil tokens**, pare num ponto limpo: commite o que está pronto e escreva `docs/HANDOFF.md` (fase, onda, WPs concluídos com commits, WPs em andamento e o que falta em cada um, bloqueios pendentes, próximo passo). Uma sessão nova continua com a seção "Continuar" de `prompts/orquestrador.md`.

## Parar e reportar

Pare e reporte, sem improvisar, quando:

- uma API da Apple, do Herdr, do Claude Code ou do Tailscale divergir do que a SPEC descreve;
- um critério de aceite for impossível como escrito;
- o trabalho exigir ação do João (bloqueios, permissões de sistema, teste no iPhone, autorização de config).

## Relatório (subagente → orquestrador)

```
## <WP> — <título>
Status: concluído | parcial | bloqueado
Arquivos: <lista de caminhos criados ou alterados>
Feito:
- …
Validação:
- <comando> → <resultado>
Critérios de aceite:
- [x] … / [ ] … (motivo)
Mudanças propostas fora do meu diretório:
- <arquivo>: <diff ou descrição>
Pendências / decisões para o João:
- …
Impacto na SPEC ou no PLANO (spikes):
- § / WP — o que muda
```
