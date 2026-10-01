# Estudo: alertas pela Live Activity e presença no Mac

> Modelo fechado e aprovado pelo João em 2026-10-01. Este documento é o estudo, não o plano de implementação.
> O plano de implementação vem depois, por etapas (§9), para aprovação à parte.

## 0. Resumo

- **Problema:** com o MacBook em uso, o iPhone recebe pushes e banners de "terminou" e "precisa de você" que não agregam. A Live Activity é o fluxo de trabalho do João: ele acompanha e aprova pelo card, sem abrir o app.
- **Causa raiz:** com vários agentes, o card pula de agente a cada update. O agente do alerta perde a vez, e o daemon manda um **push de reserva**: todos os 5 pushes normais das últimas 24 h vieram daí. Além disso, os alertas dentro do card tocam mesmo com o João no Mac.
- **Modelo final ("Moshi+"):** as regras do Moshi (presença pelo bloqueio do Mac, card pelo último evento, atualizações silenciosas), mais quatro coisas:
  - aprovação pelo próprio card;
  - zero push com card na tela;
  - "terminou" tocando quando o João está fora;
  - um toque ao bloquear o Mac com algo não visto.
- **Validação:** em etapas independentes, começando por um modo sombra que só registra no log o que o modelo faria.

## 1. Como funciona hoje e por que incomoda

- **Card (§7.5):** um por aparelho; segue o agente com o evento mais recente, e mudança de `preview` conta como evento; no máximo 1 update a cada 10 s; p10 em troca de agente, status ou `pending`, p5 no resto.
- **Alertas:** com card e token, o alerta da §7.1 fica estacionado e vai dentro do update do card. Se o card não mostra o alerta, ele sai como push normal.
- **Supressão:** só com o app aberto naquele agente (`setForeground`) ou com "Turno concluído" desligado. O daemon não sabe nada sobre o Mac.

**Logs do `mochad` (2026-10-01, 00:28–02:12):**
- 111 updates do card (80 p10, 31 p5), alternando entre `w1E:pN`, `w1E:pM`, `w1E:pP` e `w17:p1M`;
- 5 pushes normais (3 `turnDone`, 2 `needsInput`), todos precedidos de `"<kind> alert of <agent> was not shown on the card"`.

**No código:**
- foco pelo maior `eventGenerations`, que sobe a cada `preview` (`AgentActivitySnapshot.swift:201-228`);
- limite de 10 s (`LiveActivityService.swift:332`);
- `reportUnshownAlerts` (`:349`) e `droppedAlerts` (`:251`) acionam `PushService.cardAlert` (`PushService.swift:137-153`);
- há ainda push direto por `cardIsHeldByAnotherAgent` (`PushService.swift:378,390`).

## 2. Como o Moshi faz

Fontes: docs, App Store, changelog do `moshi-hook`, instalação local e relato do João.

- **Card:** uma Live Activity, que mostra o último evento (relato do João). Atualiza a cada evento do hook (prompt, ferramentas com limite de frequência, fim do turno com resumo de até 80 caracteres), com teto de 10 eventos/min (Free) ou 60 (Pro).
- **Mensagens:** chegavam como atualização do card, sem banner (relato do João). Banner só para aprovação e erro.
- **Aprovar:** pelos botões da notificação (toque longo).
- **Presença:** `suppress-push-while-unlocked`. Lê `IOConsoleLocked` do IORegistry (`cli.macConsoleLocked`); sem leitura, mantém o push. É opt-in, e está ligado na config do João (`~/.config/moshi/config.toml`).
- **Antirruído:**
  - `stopCooldownSeconds = 5`;
  - teto de envios (`agentPushLimiter`);
  - silêncio para agentes aninhados;
  - sem push de aprovação automática;
  - notificação removida ao responder no terminal;
  - "terminou" arquivado em 10 min.
- **Arquitetura:** a decisão é na nuvem (`api.getmoshi.app`); o hook local só filtra e publica.

## 3. Modelo final

| # | Regra |
|---|---|
| R1 | **Canal.** Aparelho com card e token de update recebe tudo pelo card; nenhum push da §7.1. Push só sem card (antes do token, ou com o card dispensado) |
| R2 | **Card.** Segue o último evento, como hoje. Atualiza no máximo a cada **6 s** (hoje 10), com `NSSupportsLiveActivitiesFrequentUpdates`. p10 em troca de agente, status, `pending` e update com alerta; p5 em conteúdo do mesmo agente. **Nunca para por causa da presença**: com o Mac desbloqueado, tudo continua em tempo real, só sem alerta |
| R3 | **Pedido real** (aprovação ou pergunta com `PendingRequest`). Toma o card na hora, fura o limite uma vez e segura o card até ser resolvido. O mais antigo vem primeiro; o segundo espera a vez, sem push. No celular expira em ~10 min (580 s); no Mac continua valendo. **`blocked` sem pedido** (diálogo de confiança da pasta, pedido expirado, sinal secundário) ganha **um ciclo** com alerta e depois volta à regra do último evento. Nunca passa na frente de um pedido real nem prende o card |
| R4 | **"Terminou".** Espera 5 s depois do `Stop`: se o agente voltar a trabalhar, sai sem tocar. Senão, entra numa fila curta, só de "terminou", e ganha o card por um ciclo com o alerta, mesmo com outros eventos chegando. Depois o card volta ao último evento. Ordem do foco: pedido real → "terminou" vencido → último evento. Um ciclo pode ser **só o alerta, com o mesmo conteúdo**, quando o card já mostra aquele estado. O item só sai da fila quando o APNs confirma a entrega |
| R5 | **Presença** pelo `IOConsoleLocked` do IORegistry, lido na hora do alerta (sem permissão). Desbloqueado: update sem alerta. Bloqueado ou tampa fechada: update com alerta (som, banner, tela acende). Sem leitura: toca |
| R6 | **Ao bloquear o Mac** com algo não visto naquele aparelho, ou seja, que **foi silenciado** enquanto o Mac estava desbloqueado (pedido ainda aberto ou agente ainda `blocked`; "terminou" com o status cru do Herdr ainda `done`): **um** toque, pelo mais urgente (pedido antes de "terminou", depois o mais recente). Cada item toca no máximo uma vez, não a cada bloqueio. A transição é detectada por polling a cada ~3 s, num ator único de presença compartilhado pelos dois serviços |
| R7 | **Início do card** (push-to-start). Hoje ele já sai sem `sound` (`startAlert`, `AgentActivitySnapshot.swift:84`), mas a Apple diz que o alerta do push-to-start "light up their device and display the expanded presentation". **Decisão do João (2026-10-01): fica como hoje.** O card nasce na hora, sem som, e a tela acende uma vez por sessão de trabalho. Adiar o início foi descartado |
| R8 | **Card dispensado.** O app não fica sabendo com o app suspenso (`activityStateUpdates` só roda com o app vivo). Ao rodar de novo, ele registra os cards encerrados no livro de tokens e manda `endedActivityId` no próximo envio (WebSocket ou `POST /v1/live-activity`). O daemon volta ao push até surgir card novo. Se o APNs devolver `invalidToken` (U1), o daemon também volta ao push e repassa ao `PushService` o alerta daquele update. Se o APNs devolver 200 para card dispensado, os alertas se perdem até o app rodar: decidir depois do U1. O card renasce quando um agente volta a trabalhar depois de todos pararem |
| R9 | **Toggle** "Silenciar enquanto uso o Mac" em Ajustes › NOTIFICAÇÕES, ligado por padrão. Desligado: toca sempre, sem olhar o bloqueio |
| R10 | **Push da §7.1** (só sem card): título, corpo, `time-sensitive` para pedido, ações Permitir/Negar/Responder, `collapse-id` por agente, validade de 1 h ou 10 min. Também segue R5: desbloqueado, não sai |

**Descartados:**
- fila de vez com rodízio entre agentes: virou carrossel e criava risco de orçamento;
- presença por teclado/mouse com espera de 15 s: o bloqueio é mais simples e é o hábito do João;
- silêncio para subagentes: o Mocha não escuta `SubagentStop`, e o único alerta de subagente é aprovação, que precisa tocar.

## 4. Casos

1. **No Mac, 3 agentes.** O card pula entre mensagens, "Concluído" e pedido, sempre em silêncio. Aprovar no terminal tira o pedido do card.
2. **Café: bloqueou com `pM` "Concluído" não visto.**
   - Ao bloquear: 1 toque com `pM`.
   - `pP` pede aprovação: toca, e você aprova pelo card com Face ID; o card mostra "Aprovado".
   - Ao desbloquear, tudo volta ao silêncio.
3. **Tampa fechada na tomada, 4 agentes; `pN` e `pM` terminam com 3 s de diferença.**
   - Depois da espera de 5 s, `pN` toca; um ciclo depois (10 s até a E4, depois 6 s), `pM` toca.
   - O card volta ao último evento, em silêncio.
4. **Dois pedidos fora do Mac.** `pP` toca; `pM` espera sem som. Respondido `pP`, o card vai para `pM`, que toca.
5. **Card dispensado.** O próximo "terminou" com o Mac bloqueado chega como push normal. O card renasce depois.
6. **Saiu sem bloquear.** Nada toca: o pedido aparece no card sem som. É o custo da regra; o bloqueio automático do macOS ajuda.
7. **No Mac, nenhum card aberto, você manda um prompt.** O card nasce na hora, sem som; a tela do iPhone acende uma vez (R7, como hoje).
8. **Tampa fechada na bateria.** O Mac dorme de verdade, e tudo para, inclusive os agentes.
9. **Mensagem na fila do Claude.** O turno acaba e a próxima mensagem começa em menos de 5 s: o "terminou" não toca.

## 5. Comparativo

| | Mocha hoje | Moshi | Mocha final |
|---|---|---|---|
| Push com card | Reserva quando o card perde o alerta | Banner para aprovação | Nunca |
| Card | Último evento, 10 s | Último evento, 10–60/min | Último evento, 6 s |
| Aprovar | Pelo card | Pela notificação | Pelo card |
| Pedido | Toca; pode virar push | Banner | Segura o card; toca fora do Mac |
| "Terminou" | Toca sempre; pode virar push | Só atualiza o card | Espera 5 s; toca fora do Mac; ganha um ciclo |
| Presença | Nenhuma | Bloqueio (opt-in) | Bloqueio (ligado por padrão) |
| Ao bloquear | — | Push volta | 1 toque pelo item não visto |
| Card dispensado | Daemon não sabe | Não confirmado | Volta o push |
| Decide onde | Mac | Nuvem | Mac |

## 6. Evidências técnicas

- **Bloqueio** (`ioreg`, 2026-10-01, macOS 27, 430 amostras):
  - desbloqueado: `IOConsoleLocked = No`;
  - bloqueado com a tampa aberta: `Yes`, com `CGSSessionScreenIsLocked = true`;
  - tampa fechada (`AppleClamshellState = Yes`): continua `Yes`, e o processo seguiu lendo a cada 2 s por ~9 min.
- **Energia** (`pmset -g log`):
  - na tomada com `caffeinate -dimsu`, a tampa fechada leva a "Entering **DarkWake** state due to 'Clamshell Sleep'", e o sistema segue rodando (4 h em 30/09);
  - na bateria, "Entering **Sleep** state".
  - O `pmset` tem `sleep 1`: sem `caffeinate`, o Mac dorme em 1 min.
- **Ritmo atual:** média de ~46 p10/h e pico de ~130 p10/h. No pico, o limite de 10 s já segura (~5 de 6 vagas por minuto). Com 6 s, o pico estimado é de 300–600 p10/h.
- **Orçamento iOS:** ~60 p10/h medido no simulador sem `FrequentUpdates` (SPEC §7.3). O p5 levou 45,7 s e 84 s, e um se perdeu (`docs/spikes/S4.md`). O APNs responde 200 mesmo quando o iPhone segura o update.

## 7. O que falta descobrir

| # | Pergunta | Como | Quando |
|---|---|---|---|
| U1 | O que o APNs responde para update de card dispensado (200 ou 410)? Define o que fazer no R8 | Dispensar o card e mandar `mochad apns liveactivity update` com o token antigo | Antes da E2 |
| U2 | Status cru do Herdr para o Codex. O `TreeComposer.swift:124` troca o status do Herdr pelo do app-server, que nunca dá `done` (`CodexProjection.swift:15-21`), então "não visto" no Codex exige guardar o status do Herdr antes dessa troca. Falta confirmar no laboratório que o Herdr marca `done` para panes do Codex | Leitura do código + laboratório `mocha-lab-…` | Antes da E3 |
| U3 | Com `FrequentUpdates` e 6 s, os pedidos ainda chegam na hora com 4 agentes por 1 h? | Teste no iPhone | E4 |
| U4 | Como o alerta do card aparece com o iPhone desbloqueado e no Watch | Teste no iPhone | E3 |
| U7 | Confirmar que o push-to-start sem `sound` só acende a tela, sem som nem vibração | Teste no iPhone | E3 |
| — | Resolvidos: U5 (bloqueio no macOS 27, §6), U6 (card do Moshi = último evento, relato do João), app suspenso não percebe card dispensado (código, R8) | — | — |

## 8. Como validar

1. **Testes de linha do tempo** (`scripts/test.sh`), com `ManualClock` e sonda de bloqueio falsa. Cada caso da §4 vira um teste que confere o foco a cada ciclo, a prioridade, se tocou e se algum push saiu.
2. **Modo sombra** (E1):
   - o daemon registra `shadow lock=… focus=… alert=ring|silent|dropped reason=… p=…` sem mudar nada;
   - depois de um dia de uso, um resumo mostra quantos alertas tocariam e quantos ficariam em silêncio, os pushes evitados e os toques ao bloquear;
   - o João aprova pelos números.
3. **Métricas depois de ligar:** push da §7.1 com card ativo = **0**; p10/h; alertas tocados × silenciados; latência entre o evento e o card.
4. **Checklist no iPhone** com os casos 1–9.

## 9. Etapas (cada uma independente; dá para parar em qualquer uma)

| Etapa | Muda | Alívio | Aceite |
|---|---|---|---|
| E1 | Log por update (`focus`, `p`, `alert`), sonda de bloqueio, status cru do Herdr e modo sombra | Só dados | Um dia de log e o resumo aprovado pelo João |
| E2 | R1, R3, R4 (fila de "terminou" e espera de 5 s, ainda sem presença) e R8 | Acabam os pushes com card, sem perder o "terminou" | U1; push com card = 0; nenhum "terminou" sem alerta |
| E3 | R5, R6, R7 e R9 | Acaba o som no Mac | U2, U4 (e U7, se o R7 ficar como hoje); casos 1–9 com o intervalo configurado |
| E4 | Intervalo de 6 s e `FrequentUpdates` | Card mais ao vivo | U3 |

## 10. Onde o código muda (orientação para o plano)

- **`MochaProtocol/Device.swift`** (orquestrador):
  - `DevicePreferences.silenceWhileAtMac` (padrão `true`, `decodeIfPresent`);
  - `LiveActivityRegistration.endedActivityId`.
- **Novo `MochaDaemonCore/Presence/`:**
  - sonda do `IOConsoleLocked` (IOKit, `IORegistryEntryCreateCFProperty` na raiz);
  - polling de ~3 s com aviso de transição;
  - fake em `MochaTestSupport`.
- **`PushService`:**
  - sai a maquinaria de fallback (`parkedAlerts`, `missedCardAlerts`, `cardAlert`, `cardAlertWindow`, `cardIsHeldByAnotherAgent`, `LiveActivityAlertFallback`);
  - `recipients` exclui aparelhos com card;
  - R5, R9 e a espera de 5 s do `turnDone`.
- **Ator único de presença**, compartilhado. O `PushService` pergunta ao `LiveActivityService` (estado em memória) quais aparelhos têm card e o que está pendente, em vez de ler o `hasLiveActivityCard` gravado em disco (`DeviceRecord.swift:37`, `PushService.swift:390`). O R6 também vale para aparelho sem card, via push.
- **`AgentActivitySnapshot` / `LiveActivityService`:**
  - mecânica do R4/R6 (achados da revisão):
    - update só com alerta, sem mudança de conteúdo (hoje `:356` exige conteúdo novo);
    - sai o atalho `:308-311`, que marca o alerta como mostrado sem tocar;
    - os prazos dos 5 s e da fila entram no `nextDeadline` (`:556-570`);
    - a fila de "terminou" só é esvaziada no `.delivered` (`:485`);
  - furar o limite para pedido real: `:332` e `:569`;
  - status cru do Herdr guardado no snapshot fora de `Observation`, para que `done`→`idle` não vire evento e roube o foco;
  - alerta só com o Mac bloqueado (ou toggle desligado);
  - saem `reportUnshownAlerts`, `droppedAlerts` e `settleAlertsOutsideTheCard`;
  - o `blocked` sem pedido entra na preempção;
  - fila curta de "terminou" com a espera de 5 s;
  - furar o limite para pedido;
  - toque único na transição para bloqueado;
  - R7: sem mudança no início do card;
  - `endedActivityId`;
  - status cru do Herdr para "não visto";
  - `updateInterval` 6 (só na E4).
- **App:**
  - toggle em `Settings/SettingsScreen.swift` e setter no `AppSession.swift`;
  - `AgentsActivityController.forget` avisa o daemon;
  - `App/Info.plist` com `NSSupportsLiveActivitiesFrequentUpdates` (orquestrador, E4).
- **SPEC:** §6 (Ajustes), §7.1, §7.3, §7.5 e protocolo. **PLANO:** fase nova `alertas`.

## 11. Riscos

- **Esquecer de bloquear:** nada toca (caso 6). É escolha consciente, igual ao Moshi.
- **Orçamento p10 com 6 s:** o APNs não avisa quando o iPhone estrangula. Mitigação: U3, e voltar a 10 s se precisar.
- **Card dispensado com o app fechado:** o daemon só sabe quando o app roda; até lá, depende do U1.
- **`IOConsoleLocked`** não é API documentada. É a mesma que o Moshi usa, e foi validada no macOS 27. Sem leitura, toca (falha segura).

## 12. Fontes

- Moshi: getmoshi.app/docs/live-activity, /docs/notifications, /docs/hook-settings, /docs/hooks, /docs/agents-usages, /guides/claude-code; App Store id6757859949; github.com/rjyo/homebrew-moshi/releases.
- Local: `~/.config/moshi/config.toml`, `/opt/homebrew/var/log/moshi-hook.log`, strings do binário `moshi-hook`.
- Apple:
  - UNNotificationInterruptionLevel;
  - sending-notification-requests-to-apns (p5 "opportunistic");
  - starting-and-updating-live-activities-with-activitykit-push-notifications (`NSSupportsLiveActivitiesFrequentUpdates`, `frequentPushesEnabled`);
  - ActivityKit AlertConfiguration.
- Mocha: SPEC §7.1, §7.3, §7.5, §8.3; `docs/spikes/S4.md`; logs do `mochad`, `pmset` e `ioreg` de 2026-10-01.
