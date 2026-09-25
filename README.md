# Mocha ☕

A personal iOS app that turns the Claude Code sessions running in [Herdr](https://herdr.dev) on my MacBook into a native chat on my iPhone.

- 💬 **Agent chat first**: read, prompt, interrupt, approve and answer Claude from the phone.
- 🗂️ **Herdr-aware drawer**: workspaces, worktrees, tabs and live agent status.
- 🔔 **Push and Live Activity**: sent straight from the Mac to APNs, with no cloud relay.
- 🔒 **Tailnet only**: the phone reaches the Mac through Tailscale. Nothing is exposed to the internet.

Not on the App Store. Built for a single user and a single host.

## How it works 🧩

```
iPhone (Mocha) ──wss over Tailscale──► mochad (Swift LaunchAgent on the Mac)
                                          ├─ Herdr socket API   (agents, status, prompts)
                                          ├─ Claude Code JSONL  (chat history, live)
                                          ├─ Claude Code hooks  (turn done, approvals)
                                          └─ APNs               (alerts, Live Activity)
```

## Docs 📚

- [`docs/SPEC.md`](docs/SPEC.md): source of truth (PT-BR).
- [`docs/PLANO.md`](docs/PLANO.md): phases, work packages and status (PT-BR).
- [`AGENTS.md`](AGENTS.md): rules for the AI agents building it.
- [`prompts/orquestrador.md`](prompts/orquestrador.md): kickoff prompt for the orchestrator session.

## Status 🚧

Planning complete. Implementation starts with phase 0.
