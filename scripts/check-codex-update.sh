#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERDR=/opt/homebrew/bin/herdr
JQ=/usr/bin/jq
VERSION_FILE="$ROOT/MochaKit/Sources/MochaDaemonCore/Codex/CodexAppServerProcess.swift"
SCHEMA_COPY="$ROOT/MochaKit/Fixtures/codex/schema/methods.json"
LAB="$HOME/Developer/mocha-lab/codex-update"
LAB_HOME="$LAB/codex-home"
WORK="$LAB/work"
SOCKET="$LAB/app-server.sock"
AUTH_SOURCE="$HOME/Developer/mocha-lab/S7/codex-home/auth.json"
REAL_CONFIG="$HOME/.codex/config.toml"
SUITES='CodexHandshakeIntegrationTests|CodexThreadCycleIntegrationTests|CodexEventCensusIntegrationTests|CodexSchemaIntegrationTests'

codex=""
for candidate in /opt/homebrew/bin/codex /usr/local/bin/codex "$HOME/.local/bin/codex"; do
    if [ -x "$candidate" ]; then
        codex="$candidate"
        break
    fi
done

mkdir -p "$LAB_HOME"
installed=""
if [ -n "$codex" ]; then
    installed="$(CODEX_HOME="$LAB_HOME" "$codex" --version 2>/dev/null | awk '{print $NF}')"
fi
validated="$(sed -n 's/.*lastValidatedVersion = "\(.*\)".*/\1/p' "$VERSION_FILE")"

is_newer() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

if [ "${1:-}" = "--hook" ]; then
    if [ -n "$installed" ] && is_newer "$installed" "$validated"; then
        message="Codex $installed está instalado, mas o Mocha só foi validado até a $validated. Rode scripts/check-codex-update.sh antes de mexer no Codex do daemon ou do app (AGENTS.md, Atualização do Codex)."
        "$JQ" -n --arg m "$message" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
    fi
    exit 0
fi

if [ -z "$installed" ]; then
    echo "❌ codex não encontrado em /opt/homebrew/bin, /usr/local/bin nem ~/.local/bin." >&2
    exit 1
fi
echo "Codex instalado: $installed · validado: $validated"

config_fingerprint() {
    if [ -f "$REAL_CONFIG" ]; then
        echo "$(stat -f '%m %z' "$REAL_CONFIG") $(shasum -a 256 "$REAL_CONFIG" | awk '{print $1}')"
    else
        echo ausente
    fi
}

before="$(config_fingerprint)"
workspace=""

cleanup() {
    local status=$?
    if [ -n "$workspace" ]; then
        "$HERDR" workspace close "$workspace" >/dev/null 2>&1 || true
    fi
    pkill -f -- "--listen unix://$SOCKET" >/dev/null 2>&1 || true
    pkill -f -- "--remote unix://$SOCKET" >/dev/null 2>&1 || true
    local after
    after="$(config_fingerprint)"
    if [ "$before" != "$after" ]; then
        echo "❌ O ~/.codex/config.toml mudou durante a validação (antes: $before · depois: $after). Algum codex rodou fora do CODEX_HOME do lab: confira o arquivo antes de qualquer outra coisa." >&2
        exit 1
    fi
    echo "~/.codex/config.toml intacto ($after)."
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$WORK"
if [ ! -f "$LAB_HOME/auth.json" ]; then
    if [ ! -f "$AUTH_SOURCE" ]; then
        echo "❌ O lab não tem login. Rode: CODEX_HOME=$LAB_HOME codex login" >&2
        exit 1
    fi
    install -m 600 "$AUTH_SOURCE" "$LAB_HOME/auth.json"
fi
if [ ! -f "$LAB_HOME/config.toml" ]; then
    printf 'check_for_update_on_startup = false\n\n[projects."%s"]\ntrust_level = "trusted"\n' "$WORK" > "$LAB_HOME/config.toml"
    chmod 600 "$LAB_HOME/config.toml"
fi
if [ ! -d "$WORK/.git" ]; then
    git -C "$WORK" init -q -b codex-update
    printf 'lab do check-codex-update\n' > "$WORK/README.md"
    git -C "$WORK" add README.md
    git -C "$WORK" -c user.name=mocha-lab -c user.email=lab@localhost -c commit.gpgsign=false commit -qm lab
fi

rm -rf "$LAB/schema"
CODEX_HOME="$LAB_HOME" "$codex" app-server generate-json-schema --out "$LAB/schema/stable" >/dev/null
CODEX_HOME="$LAB_HOME" "$codex" app-server generate-json-schema --experimental --out "$LAB/schema/experimental" >/dev/null

pkill -f -- "--listen unix://$SOCKET" >/dev/null 2>&1 || true
rm -f "$SOCKET"

created="$("$HERDR" workspace create --cwd "$WORK" --label mocha-lab-codex-update --no-focus --env "CODEX_HOME=$LAB_HOME")"
workspace="$("$JQ" -r '.result.workspace.workspace_id' <<<"$created")"
server_pane="$("$JQ" -r '.result.root_pane.pane_id' <<<"$created")"

"$HERDR" pane run "$server_pane" "env CODEX_HOME=$LAB_HOME $codex app-server --listen unix://$SOCKET" >/dev/null
ready=0
for _ in $(seq 1 40); do
    sleep 0.25
    if [ -S "$SOCKET" ]; then
        ready=1
        break
    fi
done
if [ "$ready" != 1 ]; then
    echo "O App Server do lab não subiu. Tela:" >&2
    "$HERDR" pane read "$server_pane" --source recent-unwrapped >&2
    exit 1
fi

split="$("$HERDR" pane split "$server_pane" --direction right --cwd "$WORK" --env "CODEX_HOME=$LAB_HOME" --no-focus)"
tui_pane="$("$JQ" -r '.result.pane.pane_id' <<<"$split")"
for _ in $(seq 1 20); do
    sleep 0.25
    if grep -q '[^[:space:]]' <<<"$("$HERDR" pane read "$tui_pane" --source visible)"; then
        break
    fi
done

if MOCHA_INTEGRATION=1 MOCHA_CODEX_LAB="$LAB" MOCHA_CODEX_LAB_PANE="$tui_pane" MOCHA_CODEX_VERSION="$installed" \
    "$ROOT/scripts/test.sh" --filter "$SUITES"; then
    if is_newer "$installed" "$validated"; then
        sed -i '' "s/lastValidatedVersion = \"$validated\"/lastValidatedVersion = \"$installed\"/" "$VERSION_FILE"
        cp "$LAB/schema-methods.json" "$SCHEMA_COPY"
        echo "✅ Codex $installed validado. CodexExecutable.lastValidatedVersion agora é $installed e a cópia do schema foi atualizada: commite as duas mudanças."
    else
        echo "✅ Codex $installed continua validado."
    fi
else
    echo "❌ Algo mudou no Codex $installed. As falhas acima trazem o payload ou a tela real: ajuste o daemon com um teste de regressão antes de subir a versão validada." >&2
    exit 1
fi
