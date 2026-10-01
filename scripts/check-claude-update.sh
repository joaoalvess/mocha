#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERDR=/opt/homebrew/bin/herdr
JQ=/usr/bin/jq
VERSION_FILE="$ROOT/MochaKit/Sources/MochaDaemonCore/App/ClaudeCodeVersion.swift"
LAB="$HOME/Developer/mocha-lab/claude-update"
SUITES='ClaudeScreenIntegrationTests|ClaudeImagePasteIntegrationTests|RealTranscriptCensusTests|ClaudeHooksRealSettingsTests'

installed="$(claude --version 2>/dev/null | awk '{print $1}')"
validated="$(sed -n 's/.*lastValidated = "\(.*\)".*/\1/p' "$VERSION_FILE")"

is_newer() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

if [ "${1:-}" = "--hook" ]; then
    if [ -n "$installed" ] && is_newer "$installed" "$validated"; then
        message="Claude Code $installed está instalado, mas o Mocha só foi validado até a $validated. Rode scripts/check-claude-update.sh antes de mexer em controles, hooks ou transcripts (AGENTS.md, Atualização do Claude Code)."
        "$JQ" -n --arg m "$message" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
    fi
    exit 0
fi

echo "Claude Code instalado: $installed · validado: $validated"

mkdir -p "$LAB"
[ -f "$LAB/settings.json" ] || echo '{}' > "$LAB/settings.json"

created="$("$HERDR" workspace create --cwd "$LAB" --label mocha-lab-claude-update --no-focus)"
workspace="$("$JQ" -r '.result.workspace.workspace_id' <<<"$created")"
pane="$("$JQ" -r '.result.root_pane.pane_id' <<<"$created")"
trap '"$HERDR" workspace close "$workspace" >/dev/null 2>&1 || true' EXIT

"$HERDR" pane run "$pane" "claude --setting-sources project,local --settings $LAB/settings.json --model opus" >/dev/null

ready=0
for _ in $(seq 1 60); do
    sleep 0.5
    screen="$("$HERDR" pane read "$pane" --source visible)"
    if grep -qi "trust" <<<"$screen"; then
        "$HERDR" pane send-keys "$pane" enter >/dev/null
    elif grep -Eq "(manual mode|accept edits|plan mode|auto mode) on" <<<"$(grep -v "^[[:space:]]*$" <<<"$screen" | tail -1)"; then
        ready=1
        break
    fi
done
if [ "$ready" != 1 ]; then
    echo "O Claude do laboratório não ficou pronto. Tela:" >&2
    echo "$screen" >&2
    exit 1
fi

if MOCHA_INTEGRATION=1 MOCHA_CLAUDE_LAB_PANE="$pane" "$ROOT/scripts/test.sh" --filter "$SUITES"; then
    if is_newer "$installed" "$validated"; then
        sed -i '' "s/lastValidated = \"$validated\"/lastValidated = \"$installed\"/" "$VERSION_FILE"
        echo "✅ Claude Code $installed validado. ClaudeCodeVersion.lastValidated agora é $installed: commite a mudança."
    else
        echo "✅ Claude Code $installed continua validado."
    fi
else
    echo "❌ Algo mudou no Claude Code $installed. As falhas acima trazem a tela real: ajuste o ClaudeScreen/transcript com um teste de regressão antes de subir a versão validada." >&2
    exit 1
fi
