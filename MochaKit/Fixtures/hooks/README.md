# Fixtures de hooks do Claude Code (spike S3)

Capturadas em 2026-09-25 no Claude Code 2.1.283 (`--model haiku`), dentro do laboratório `mocha-lab-S3` do Herdr 0.9.1, com um servidor HTTP de teste em `127.0.0.1` que gravava cada requisição e segurava a resposta quando pedido. Análise completa: `docs/spikes/S3.md`.

## Redação

- `/Users/joaoalves` → `/Users/dev`; pasta do laboratório → `/Users/dev/projects/demo-app` (e `-Users-dev-projects-demo-app` nos caminhos de `~/.claude/projects` e do scratchpad).
- `session_id` → `11111111-…` (1ª sessão), `22222222-…` (2ª) e `33333333-…` (3ª, depois do `/clear`); o `transcript_path` e o `scratchpad_dir` acompanham.
- `prompt_id` → `5f0c0000-0000-4000-8000-0000000000NN`; `tool_use_id` → `toolu_01Demo<n>`. O mesmo id real vira o mesmo id fictício em todos os arquivos.
- Porta do laboratório 47490 → 47420 (a do `HookServer`) no header `Host`. O segredo é o fictício `test-secret`. O pane `w1C:p2` é o id real do laboratório.
- Os prompts e perguntas do laboratório já eram neutros e ficaram como estão.

## Arquivos

| Arquivo | O que é |
|---|---|
| `SessionStart.{startup,clear,compact,resume}.json` | Corpo do `SessionStart` por `source`. Veio por **hook de comando** (`curl`): o Claude ignora hook `http` nesse evento |
| `SessionEnd.{clear,prompt_input_exit}.json` | Corpo do `SessionEnd` (`/clear` e `/exit`) |
| `UserPromptSubmit.json`, `Stop.json` | Turno simples; `Stop` traz `last_assistant_message`, `background_tasks` e `session_crons` |
| `Notification.permission_prompt.json` | ~6 s depois de um diálogo de permissão **ou** de um seletor do AskUserQuestion sem tecla |
| `Notification.idle_prompt.json` | ~60 s depois do fim do turno sem tecla |
| `PreToolUse.bash.json`, `PermissionRequest.bash.json`, `PostToolUse.bash.json` | Os três hooks da mesma chamada de Bash (mesmo `tool_input`). O `PermissionRequest` não tem `tool_use_id` |
| `PermissionRequest.write.json` | Pedido de `Write` (caminho absoluto, `content`) |
| `PermissionRequest.ExitPlanMode.json` | **Sintetizada pela doc** (não capturada): pedido do `ExitPlanMode` com `plan` e `planFilePath`, que o Claude injeta no `tool_input`. Sem `permission_suggestions`, que ainda não foi visto num pedido real |
| `PermissionRequest.AskUserQuestion.{single,multi}.json` | O seletor do AskUserQuestion também dispara `PermissionRequest` (sem `permission_suggestions`). `multi`: 3 perguntas, a 2ª com `multiSelect` |
| `PreToolUse.AskUserQuestion.{single,multi}.json` | O `PreToolUse` do AskUserQuestion (mecanismo A, não adotado) |
| `PostToolUse.AskUserQuestion.{single,multi}.json` | Respondidas no terminal: `tool_input`/`tool_response` com `answers` (`multiSelect` com rótulos unidos por `", "`, texto livre como está) e `annotations: {}` |
| `headers.http.json` | Headers de um hook `http` (cliente `axios`, `keep-alive`) com `X-Mocha-Pane` interpolado |
| `headers.interpolation.json` | `$HERDR_PANE_ID` e `${HERDR_PANE_ID}` interpolados; `X-Test-Unlisted` (`$HERDR_TAB_ID`, fora de `allowedEnvVars`) chega vazio |
| `headers.command-curl.json` | Headers do `curl` do hook de comando |
| `response.PermissionRequest.allow.json` | Resposta que aprova (vale para qualquer ferramenta) |
| `response.PermissionRequest.ExitPlanMode.allow.json` | Aprova o plano: `allow` + `updatedInput` com o `tool_input` original sem mudança + `updatedPermissions` `setMode` `auto` na sessão (a doc diz que `allow` sozinho não basta para o `ExitPlanMode`) |
| `response.PermissionRequest.deny.json` | Nega com mensagem; o Claude recebe a mensagem como `tool_result` de erro e **continua** o turno |
| `response.PermissionRequest.deny-interrupt.json` | Nega com `interrupt: true`: o turno para, como o "No" do terminal |
| `response.PermissionRequest.AskUserQuestion.{single,multi}.json` | Responde o AskUserQuestion: `allow` + `updatedInput` com as `questions` originais e `answers` (mecanismo C, adotado) |
| `response.PreToolUse.AskUserQuestion.{single,multi}.json` | Mesma resposta no formato do `PreToolUse` (mecanismo A, testado e não adotado) |
| `response.empty.json` | `{}`: sem decisão; o diálogo do terminal segue normal |
| `sequence.*.jsonl` | Linha do tempo de um cenário: hooks recebidos (`source: hook`), respostas do servidor (`daemon`), conexão fechada pelo Claude (`claude`), status do Herdr (`herdr`), `tool_use`/`tool_result` no transcript (`transcript`) e teclas enviadas (`terminal`). `dt` em segundos desde o início. Horários de tecla são aproximados (±0,3 s), exceto o do `terminal-allow` |
| `settings.install-hooks.proposed.json` | Bloco de hooks proposto para o `install-hooks` (validado no laboratório com a porta 47490), ao lado do hook do Herdr. Na fase controles ganhou o `PreModelSwitch` síncrono (sem `async`, sem `-o /dev/null`, `\|\| echo '{}'`) e o `PostModelSwitch` |
| `Stop.effort.json`, `PreToolUse.bash.effort.json` | Spike S8 (Claude Code 2.1.284, Sonnet 5.5): `permission_mode` e `effort.level`. O `Stop.json` do S3 (Haiku) não tem `effort` |
| `PreModelSwitch.command.json` | S8: `/model sonnet` digitado com cache quente; sem `permission_mode` (a documentação diz que tem) |
| `PostModelSwitch.{picker,auto}.json` | S8: troca pelo seletor e troca automática (Haiku em `plan` roda Sonnet), esta sem `prompt_id` e com `requested_model: null` |
| `response.PreModelSwitch.allow.json` | Resposta que pula o diálogo "Switch model?" (só com `setModel` do app pendente no pane) |

`elicitation_dialog` não foi capturado: só dispara com um servidor MCP pedindo formulário.

As amostras do S8 seguem a mesma redação, com o `session_id` `44444444-…` e `prompt_id` `5f0c0000-…-00000000001N`.
