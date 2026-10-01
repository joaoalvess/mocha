#!/usr/bin/env bash
set -euo pipefail

LAST="24h"
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      LAST="$2"
      shift 2
      ;;
    --file)
      FILE="$2"
      shift 2
      ;;
    *)
      echo "uso: $0 [--last <tempo, ex.: 24h, 90m>] [--file <saída salva do log show --style compact>]" >&2
      exit 64
      ;;
  esac
done

LAGS="$(mktemp)"
trap 'rm -f "$LAGS"' EXIT

read_log() {
  if [[ -n "$FILE" ]]; then
    /usr/bin/grep ' mochad\[' "$FILE"
  else
    /usr/bin/log show --style compact --last "$LAST" \
      --predicate 'subsystem == "com.joaoalves.mocha" AND process == "mochad"' 2>/dev/null
  fi
}

read_log |
  /usr/bin/awk -v lags="$LAGS" -v last="${FILE:-últimas $LAST}" '
    function field(name,   i, parts) {
      for (i = 1; i <= NF; i++) {
        if (index($i, name "=") == 1) {
          split($i, parts, "=")
          return parts[2]
        }
      }
      return ""
    }
    function after(word,   i) {
      for (i = 1; i < NF; i++) {
        if ($i == word) return $(i + 1)
      }
      return ""
    }
    / shadow alert / {
      key = after("of") " " field("gen")
      would = field("would")
      if (would == "cancelled") {
        cancelled[key] = 1
      } else {
        outcome[key] = would
        kind[key] = after("alert")
        channel[key] = field("channel")
      }
      next
    }
    / shadow lock-ring / {
      if (after("lock-ring") == "none") lockNone++
      else lockRing[after(after("lock-ring"))]++
      next
    }
    / card update of / {
      hour = $1 " " substr($2, 1, 2)
      priority = after(after("of"))
      updates[priority]++
      if (priority == "p10") p10ByHour[hour]++
      hours[hour] = 1
      print field("lag") > lags
      next
    }
    / push (turnDone|needsInput) of / {
      pushes[field("fallback")]++
      pushKinds[after("push")]++
      next
    }
    / presence: / {
      presence[after("presence:")]++
      next
    }
    END {
      for (key in outcome) {
        if (key in cancelled) {
          totals["cancelled"]++
          continue
        }
        totals[outcome[key]]++
        byKind[kind[key] " " outcome[key]]++
        byChannel[channel[key]]++
      }
      for (key in cancelled) {
        if (!(key in outcome)) totals["cancelled"]++
      }
      hourCount = 0
      peak = 0
      for (hour in hours) {
        hourCount++
        if (p10ByHour[hour] > peak) peak = p10ByHour[hour]
      }
      printf "Período: %s\n\n", last
      printf "Alertas do modelo novo (um por agente e geração)\n"
      printf "  tocaria: %d  silêncio: %d  cancelado (espera de 5 s): %d\n", totals["ring"], totals["silent"], totals["cancelled"]
      printf "  turnDone: tocaria %d, silêncio %d\n", byKind["turnDone ring"], byKind["turnDone silent"]
      printf "  needsInput: tocaria %d, silêncio %d\n", byKind["needsInput ring"], byKind["needsInput silent"]
      printf "  canal: card %d, push %d\n\n", byChannel["card"], byChannel["push"]
      printf "Pushes da §7.1 (roteamento atual)\n"
      printf "  total: %d (turnDone %d, needsInput %d)\n", pushes["yes"] + pushes["no"], pushKinds["turnDone"], pushKinds["needsInput"]
      printf "  de reserva do card (somem no modelo novo): %d\n\n", pushes["yes"]
      printf "Toques ao bloquear o Mac\n"
      printf "  tocaria: %d (needsInput %d, turnDone %d)  nada a tocar: %d\n", lockRing["needsInput"] + lockRing["turnDone"], lockRing["needsInput"], lockRing["turnDone"], lockNone
      printf "  transições: locked %d, unlocked %d, unknown %d\n\n", presence["locked"], presence["unlocked"], presence["unknown"]
      printf "Updates do card\n"
      printf "  p10: %d  p5: %d  horas com update: %d\n", updates["p10"], updates["p5"], hourCount
      if (hourCount > 0) printf "  p10 por hora com update: média %.1f, pico %d\n", updates["p10"] / hourCount, peak
    }
  '

if [[ -s "$LAGS" ]]; then
  /usr/bin/sort -n "$LAGS" | /usr/bin/awk '
    { values[NR] = $1 }
    END { printf "  lag: mediana %.1f s, máximo %.1f s\n", values[int((NR + 1) / 2)], values[NR] }
  '
fi
