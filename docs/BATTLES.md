# Batalhas selvagens — proposta para rever

Estado: **aprovado e programado** (27 out 2026). Desligado no jogo publicado até chegar a arte dos iniciais; ligado no Studio com o Debug.
Todos os números vão para a Config (`Config/Battle.luau`) e afinam-se a jogar.

## Decisões do developer (27 out 2026)

| # | Pergunta | Resposta |
|---|---|---|
| 1 | Onde decorre a batalha | **No próprio sítio**: arena circular no chão, câmara de batalha, o mundo continua à volta. |
| 2 | Perder (todos os pets da equipa desmaiam) | **Desmaiam e curas na Spawn Fountain** (grátis). O selvagem foge. Sem perder Cash. |
| 3 | Como começa um jogador novo | **Esperar pela arte dos 3 iniciais.** As batalhas ficam desligadas (`battles.enabled = false`) até lá; apanhar com E continua a funcionar. No Studio ligo-as para testar. |
| 4 | Números | **Proposta do Claude** (este documento). |
| 5 | Item de captura | **Pet Capsule**. |

## Como joga

1. **Escolher a luta.** Vês um pet selvagem a passear e aproximas-te. O prompt passa a **"Battle"** (segurar E). Não há encontros aleatórios nem lutas automáticas.
   Só podes lutar se tiveres pelo menos um pet na equipa com vida.
2. **Entrada (cutscene curta, ~1.5 s).**
   - Aparece um anel no chão (~30 studs) à volta de ti e do selvagem.
   - O teu primeiro pet salta para o anel e o selvagem vira-se para ele.
   - A câmara roda para o lado.
   - Aparece o banner "A wild Branch Deer (Lv 6) appeared!".
3. **Proteção.**
   - Ninguém te pode roubar a ti nem ao selvagem durante a batalha. O anel é a "bolha".
   - O medidor de exposição pausa.
   - O jogador fica parado atrás do seu pet.
4. **Turnos.** Em cada turno escolhes uma ação:
   - **Ataque**: um dos 4.
   - **Pet Capsule**: tentar apanhar.
   - **Switch**: trocar de pet; gasta o turno.
   - **Run**: fugir; resulta sempre contra selvagens.

   Quem tem mais Speed ataca primeiro. O selvagem escolhe um ataque ao acaso, e usa mais o forte quando o tem.
5. **Fim.**
   - **Ganhar**: o selvagem desmaia e foge. Os teus pets que lutaram ganham XP.
   - **Apanhar**: o selvagem entra na Pet Capsule. Vai para a tua base, ou fica contigo se a base estiver cheia, como hoje.
   - **Fugir**: nada muda.
   - **Perder**: os teus pets ficam com 0 de vida. Só voltam a lutar depois de curados na fonte.
6. **Vida.** A vida não volta sozinha entre batalhas. Recupera na **Spawn Fountain** (prompt "Heal team", grátis) e fica guardada no save.
7. **Afastar-se.** Se não escolheres nada durante 60 s, ou se te afastares, contas como fugido.

## Tipos

| Ataque \ Pet que leva | Forest | Desert | Neutral |
|---|---|---|---|
| **Forest** | ×0.67 | **×1.5** | ×1 |
| **Desert** | **×1.5** | ×0.67 | ×1 |
| **Neutral** | ×1 | ×1 | ×1 |

Forest e Desert são fortes um contra o outro (DESIGN-v2 §4). O mesmo tipo resiste. Os iniciais Neutral não têm vantagem nem fraqueza.

## Estatísticas base (nível 1)

| Espécie | Tipo | Raridade | HP | Attack | Defense | Speed | Papel |
|---|---|---|---|---|---|---|---|
| Acorn Squirrel | Forest | Common | 40 | 45 | 35 | 60 | Rápido e frágil |
| Hopping Mushroom | Forest | Uncommon | 50 | 40 | 50 | 35 | Resistente |
| Branch Deer | Forest | Rare | 60 | 60 | 50 | 55 | Equilibrado e forte |
| Running Cactus | Desert | Common | 45 | 45 | 45 | 50 | Equilibrado |
| Ball Scorpion | Desert | Uncommon | 45 | 60 | 55 | 40 | Bate forte |
| Sun Camel | Desert | Rare | 70 | 55 | 55 | 40 | Tanque |

- **Crescimento com o nível:** cada stat = base × (1 + 0.1 × (nível − 1)). Ao nível 10 fica quase o dobro; ao nível 30, quase 4×.
- **Nível máximo:** 30.
- O tamanho (size) e a fase de crescimento **não** contam na batalha: só o nível. Assim o dinheiro e a força ficam separados, e um pet grande não é automaticamente o mais forte.

## Ataques (4 por espécie)

| Ataque | Tipo | Poder | Usos por batalha |
|---|---|---|---|
| Tackle (todos) | Neutral | 40 | ∞ |
| Assinatura física | Neutral | 55 | 15 |
| Ataque do tipo | Tipo da espécie | 50 | ∞ |
| Ataque forte do tipo | Tipo da espécie | 85 | 5 |

| Espécie | Assinatura (55) | Tipo (50) | Forte (85) |
|---|---|---|---|
| Acorn Squirrel | Tail Smack | Acorn Toss | Nut Barrage |
| Hopping Mushroom | Bounce | Spore Puff | Cap Slam |
| Branch Deer | Antler Charge | Leaf Blade | Forest Rush |
| Running Cactus | Spin Dash | Needle Shot | Thorn Storm |
| Ball Scorpion | Pinch | Sand Sting | Venom Tail |
| Sun Camel | Stomp | Sun Beam | Solar Flare |

Não há efeitos de estado (veneno, sono…) nesta primeira versão, para ficar simples e legível. Podem entrar depois.

## Dano

```
dano = arredondar_cima( poder × (Attack ÷ Defense do alvo) × 0.4 × tipo × aleatório(0.85–1.0) )
```
O dano é sempre pelo menos 1.

Exemplo: Acorn Squirrel nível 5 usa Acorn Toss (50) contra um Running Cactus nível 5:
- Attack 63, Defense do cactus 63, Forest contra Desert ×1.5.
- 50 × 1 × 0.4 × 1.5 ≈ **27–30** de dano, num cactus com 63 HP.
- Ou seja, dois a três golpes.

## Níveis dos selvagens

| Bioma | Common | Uncommon | Rare (e Raro do dia) |
|---|---|---|---|
| Forest (perto) | 1–4 | 3–6 | 6–10 |
| Desert (longe) | 5–8 | 7–10 | 10–14 |

Pets que já tens (dados do save) começam no **nível 1, com 0 XP**. Os que apanhares em batalha mantêm o nível do selvagem.

## XP

- **Vitória:** cada pet que lutou ganha **10 + 5 × nível do selvagem**.
- **Captura:** dá metade dessa XP.
- **Próximo nível:** precisa de **20 + 15 × nível atual**. Do 1 para o 2 são 35 XP; do 9 para o 10 são 155 XP.
- **Ritmo:** cerca de 3 vitórias contra pets do mesmo nível para subir um nível no início, e um pouco mais depois.

## Pet Capsule

- **Preço:** $50 cada. Ficam guardadas no save.
- **Comprar:** dentro da batalha. Se não tiveres nenhuma, o botão passa a "Buy & throw $50", que compra e lança.
- **Loja:** quando houver uma loja, também lá.
- **Hipótese de apanhar:**
  ```
  hipótese = base da raridade × (1.5 − vida que resta em fração), entre 5% e 95%
  ```
  | Raridade | Base | Com vida cheia | Com 10% de vida |
  |---|---|---|---|
  | Common | 0.60 | 30% | 84% |
  | Uncommon | 0.40 | 20% | 56% |
  | Rare | 0.20 | 10% | 28% |
- **Se falhar:** a cápsula abana, abre-se, e o selvagem ataca nesse turno.
- **Animação:** a cápsula abana 1 a 3 vezes conforme a hipótese, com o efeito `fx_capture_flash`. Usa os clips Throw / Shake / Open / Lock quando a arte chegar.

## O que muda noutros sistemas

- **Apanhar com E:** com `battles.enabled = true`, deixa de existir para pets selvagens (passa a "Battle"). Com `false`, tudo fica como hoje.
- **Save:** cada pet guarda `level`, `xp` e `hp`. O jogador guarda `capsules`.
- **Tablet:** a ficha passa a mostrar o nível, a barra de XP, a vida e os 4 ataques com os usos.
- **Spawn Fountain:** ganha o prompt "Heal team", com o efeito `fx_heal_rings`.
- **Roubar pets soltos por batalha** (passo 6 da ordem) usa este mesmo sistema; o stun sai nessa altura.

## Assets que ajudam (não bloqueiam)

- Animações dos pets: `BattleIdle`, `Attack`, `Hit`, `Faint`. Sem elas, uso movimentos simples por código (saltar, recuar, cair).
- Modelo e clips da Pet Capsule.
- Efeitos: `fx_hit_star`, `fx_leaf_burst`, `fx_sand_blast`, `fx_capture_flash`, `fx_faint_puff`, `fx_heal_rings`, `fx_battle_ring`.
- Ícones de tipo e de batalha.
- Sons do catálogo do Roblox.

Até a arte chegar, uso partículas nativas e formas simples, como já está em [ASSET-REQUESTS.md](ASSET-REQUESTS.md).

## Afinações feitas a testar

- **Ataque forte dos selvagens:** escolhido com uma hipótese própria de **20%** (`wildStrongMoveChance`), enquanto tiver usos. Na primeira versão era ~50% e um selvagem de nível baixo vencia pets mais fortes logo no primeiro turno.
- **Ritmo do ecrã:** o servidor espera que o cliente acabe de mostrar os eventos (~0.95 s cada) antes de mexer no mundo. Assim a cápsula aterra no pet antes de ele ir para a base.
