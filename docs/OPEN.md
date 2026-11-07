> **Nota (2026-11-07):** documento histórico em parte. O roubo de pets saiu do jogo, que agora assenta em batalhas, e o código entra no Studio pela MCP, não pelo plugin do Rojo. Em caso de conflito, prevalece `docs/DECISIONS.md`.

# Perguntas em aberto

Do brief (secção 7). Não inventar respostas: perguntar ao developer, uma de cada vez.

| # | Pergunta | Estado | Proposta do Claude |
|---|---|---|---|
| 1 | O dono sai do jogo com um animal solto: o que acontece? | **Decidido: B** (2026-10-26) | Fica solto e pode ser roubado até ao reset do dia. |
| 2 | Origem das mutações sem ovos. | Depois do protótipo | — |
| 3 | Velocidade de crescimento, limite de soltos, duração do dia e todos os números. | Afinar a testar | Valores atuais em `src/shared/Config`. |
| 4 | Limite para multiplicadores pagos. | Depois do protótipo, mas importante | — |
| 5 | Segurança nas trocas e contas alternativas. | **Decidido: proposta aceite** (2026-10-26) | Confirmação dupla que reinicia a cada alteração + contagem de 3 s; só animais na base; servidor valida tudo no momento da troca; conta com pelo menos 3 dias e máximo de trocas por dia. |
| 6 | As trocas entram no protótipo? | **Decidido: sim** (2026-10-26) | Milestone própria M7 Trading, depois da Persistence. |
| 7 | Comportamento exato do hazard da Forest. | **Decidido: A** (2026-10-26) | Subida mais lenta + nevoeiro (só no ecrã do jogador) que engrossa com o medidor. |
| 8 | Tolerância a desconexões. | **Decidido: B** (2026-10-26) | Animal transportado volta ao bioma de origem; sem período de tolerância. |
| — | O Sun Camel é o mesmo animal que o antigo Marshmallow Camel? | **Decidido: sim** (2026-10-26) | Nome no jogo: Sun Camel. |
