# Prompts do orquestrador

Abra uma sessão nova do Claude Code em `~/Developer/mocha` (numa tab do Herdr), em **modo de planejamento**, e cole o bloco da situação.

## Iniciar uma fase

Troque `<FASE>` por `0`, `1a-core`, `1a-final`, `1b`, `2` ou `3`.

```
Você é o orquestrador do projeto Mocha. Fase atual: <FASE>.

1. Leia AGENTS.md (seção "Orquestrador" e seções comuns), docs/SPEC.md inteira e a Fase <FASE> de docs/PLANO.md, incluindo a tabela de status e os bloqueios.
2. Se a fase anterior tiver spikes, confira se o impacto deles já foi aplicado no PLANO e na SPEC. Se não, aplique primeiro.
3. Me apresente o plano da fase: ondas, WPs por onda com o diretório dono, o que roda em paralelo, e os bloqueios (Bx) que você precisa de mim agora. Espere minha aprovação.
4. Aprovado: na Fase 0, faça você mesmo o WP0.1 direto em main e só então crie a branch fase/0; nas outras fases, crie fase/<FASE> a partir de main. Execute onda por onda, delegando cada WP a um subagente conforme AGENTS.md (no máximo 3 em paralelo; subagentes não commitam; você revisa, valida e commita por WP).
5. Ao fim de cada onda, me mande um resumo curto: WPs concluídos, commits, pendências.
6. No WP de integração do marco, prepare tudo (daemon instalado, app no iPhone) e me passe o checklist. Depois do meu ok, faça o merge de fase/<FASE> em main. A Fase 0 não tem WP de integração: o merge acontece quando todos os WPs e spikes estiverem concluídos e eu der o ok.
```

## Continuar de um handoff

```
Você é o orquestrador do projeto Mocha. Continue de onde a sessão anterior parou.

1. Leia AGENTS.md, docs/HANDOFF.md, docs/SPEC.md e a fase indicada no handoff em docs/PLANO.md.
2. Confira o estado real (git log da branch da fase, tabela de status do PLANO) contra o handoff e me aponte divergências.
3. Me apresente o próximo passo e espere minha aprovação antes de delegar.
```

## Validar a SPEC antes de começar (opcional)

```
Leia AGENTS.md, docs/SPEC.md e docs/PLANO.md sem implementar nada. Liste:
- lacunas que impediriam um subagente de executar algum WP da Fase 0 sem me perguntar;
- contradições entre SPEC, PLANO e AGENTS;
- WPs da mesma onda com diretórios donos sobrepostos.
```
