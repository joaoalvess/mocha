#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
design="$(dirname "$here")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 "$here/build.py"
swiftc -O "$here/snap.swift" -o "$work/snap"
"$work/snap" "$design/mock.html" "$work" >/dev/null

while read -r id name; do
  cp "$work/$id.png" "$design/mock/$name.png"
done <<'MAP'
s-pair 01-pareamento
s-pair-cam 01b-lendo-qr
s-pair-err 01c-erro-pareamento
s-home 02-home
s-home-off 02b-home-sem-conexao
s-home-empty 02c-home-vazia
s-uso 03-uso-plano
s-det 04-detalhe-agente
s-det-need 04b-detalhe-precisa-de-voce
s-chat-a 05-chat-inicio-turno
s-chat-b 05b-chat-fim-turno
s-chat-exp 06-card-expandido
s-chat-work 07-chat-trabalhando
s-chat-type 08-chat-digitando
s-chat-menu 09-menu-slash
s-chat-clear 09b-confirma-clear
s-chat-perm 10-pedido-aprovacao
s-chat-q 10b-pergunta
s-chat-q-step 10c-pergunta-passo
s-chat-q-last 10d-pergunta-ultima
s-drawer 11-gaveta-arvore
s-drawer-rec 11b-gaveta-recentes
s-settings 12-ajustes
s-inbox 13-inbox
s-lock 14-tela-bloqueada
s-banner 14b-banner
s-term 15-terminal
s-chat-sub 16-chat-subagente
s-sub-run 16b-transcript-subagente
s-sub-done 16c-transcript-concluido
s-home-sub 17-home-subagentes
s-det-sub 18-detalhe-subagentes
s-chat-wf 19-chat-workflow
MAP
