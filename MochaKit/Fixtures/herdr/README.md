# Fixtures do Herdr (spike S2)

Capturadas em 2026-09-25 no Herdr 0.9.1 (protocolo 22), pelo socket `~/.config/herdr/herdr.sock`, com um cliente Python próprio. Detalhes e análise: `docs/spikes/S2.md`.

## Redação

- `/Users/joaoalves` → `/Users/dev`. Projetos de trabalho → `/Users/dev/projects/demo-api` e `/Users/dev/projects/demo-web`. Laboratório `mocha-lab-S2` → `demo-app` (`/Users/dev/projects/demo-app`); laboratório `mocha-lab-S1` → `demo-lab`.
- Rótulos, títulos de terminal e o token `quota_topic` de sessões reais → textos neutros ("tarefa principal", "revisão do código", "tarefa de exemplo"). Prompts do laboratório ficaram como estão (já são neutros).
- `session_id` de sessões reais → `11111111-…` e `22222222-…`. Os do laboratório são os reais.
- Estrutura, tipos, ids do Herdr (`wJ`, `w1A:p1`, `term_…`) e ordem dos campos preservados. `tokens` vêm de um plugin do usuário e podem ser ignorados.

## Origem

| Arquivo | Origem |
|---|---|
| `herdr-api.schema.json` | `herdr api schema --json` (completo, sem redação) |
| `ping.response.json` | `ping` real |
| `workspace.list.response.json` | `workspace.list` real, com o laboratório aberto (2 workspaces com `worktree`, 4 sem) |
| `workspace.create.response.json`, `workspace.close.response.json` | laboratório |
| `tab.list.response.json` | `tab.list` real, sem `workspace_id` (todas as tabs) |
| `tab.list.workspace.response.json` | `tab.list` do laboratório (`workspace_id` informado) |
| `tab.get.two-agents.response.json` | tab do laboratório com dois agentes (`done` + `working`): o `agent_status` agregado sai `done` |
| `tab.create.response.json`, `pane.split.response.json`, `pane.close.response.json` | laboratório |
| `agent.list.response.json` | `agent.list` real, com dois agentes na mesma tab (`w1A:p1`, `w1A:p2`) |
| `agent.get.response.json` | `agent.get` de um agente do laboratório em `working` |
| `agent.get.by-name.response.json` | `agent.get` pelo nome dado no `agent.start` (`labstart`) |
| `pane.get.response.json` | `pane.get` de um pane do laboratório com agente |
| `pane.list.response.json` | `pane.list` real (panes com e sem agente) |
| `session.snapshot.response.json` | `session.snapshot` real, antes do laboratório |
| `session.snapshot.two-agents-one-tab.response.json` | `session.snapshot` filtrado para o workspace do laboratório (tab com 2 panes/agentes) |
| `worktree.list.response.json` | `worktree.list` do laboratório |
| `agent.prompt.response.json` | `agent.prompt` sem `wait` (volta em ~300 ms, `agent_status` ainda `idle`) |
| `agent.prompt.wait.response.json` | `agent.prompt` com `wait` (volta quando assenta) |
| `agent.send_keys.response.json` | `agent.send_keys` com `["Escape"]` durante um turno |
| `agent.start.response.json` | a única chamada de `agent.start`, com `args` |
| `agent.wait.response.json`, `agent.read.response.json` | laboratório |
| `error.*.json` | erros reais provocados no laboratório ou com leituras inválidas (`error.invalid_key.json` foi reconstruído a partir da resposta impressa) |
| `events.subscribe.request.json` | forma da requisição usada pelo `HerdrBridge` (montada; globais sem `pane_id` + uma inscrição por pane) |
| `events.subscribe.response.json` | ack real |
| `event.<nome>.json` | primeiro evento real de cada tipo no laboratório; `<nome>` é o valor do campo `event` no fio |
| `event.pane.agent_status_changed.no-agent.json` | status depois que o Claude saiu do pane (sem `agent`) |
| `event.pane_agent_detected.released.json` | saída do agente (`released: true`, `final_status`) |
| `event.*.synthetic.json`, `workspace.list.linked-worktree.synthetic.json` | **sintéticos**, montados a partir do schema (sem worktree ligado no estado real; `workspace.move` e `worktree.create` não foram rodados) |
| `stream.status.*.jsonl` | fluxo real de uma conexão de `pane.agent_status_changed` (ack + eventos, uma linha por mensagem) |
| `stream.global.lab-lifecycle.jsonl` | todos os eventos globais do laboratório, em ordem, do `workspace_created` ao `workspace_closed` |

Todos os `.json` e cada linha dos `.jsonl` validam contra `herdr-api.schema.json` (`event.*` → `schemas.event`, `event.pane.*` → `schemas.subscription_event`, respostas → `success_response`/`error_response`).
