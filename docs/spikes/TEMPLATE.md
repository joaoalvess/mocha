# Sx: <título>

**Data**: AAAA-MM-DD
**Versões**: Claude Code x.y.z · Herdr x.y.z · Tailscale x.y.z · iOS xx · Xcode xx (o que se aplicar)
**Resultado**: aprovado | aprovado com ajustes | reprovado

## Pergunta

O que o spike precisava responder, em uma a três frases.

## Resposta

A conclusão, direta.

## Evidências

Comandos executados, payloads reais (redigidos), medições e capturas. Cada afirmação importante tem sua evidência aqui.

## Decisões

Lista numerada do que passa a valer. Cada item cita a § da SPEC a atualizar. Quem aplica na SPEC é o orquestrador, a partir da seção "Impacto".

## Impacto

| Onde | O que muda |
|---|---|
| SPEC §x.y | texto novo, pronto para colar |
| PLANO WP-… | … |

## Armadilhas

Comportamentos inesperados e como evitá-los na implementação.

## Limpeza

O que o spike criou fora do repositório (workspace `mocha-lab-<Sx>` e `~/Developer/mocha-lab/<Sx>/`, config do Tailscale, arquivos temporários) e como foi desfeito.
