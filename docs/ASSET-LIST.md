# Lista de assets para aperfeiçoar o que já existe

Só entram coisas para **sistemas que já estão no jogo**. Não há aqui funcionalidades novas.

As prioridades:
- **P1**: sem isto, o sistema parece inacabado ou fica desligado.
- **P2**: melhora muito.
- **P3**: acabamento.

## Formato de entrega (igual ao que já usamos)

| Tipo | Formato | Notas |
|---|---|---|
| Modelos | **GLB**, Y para cima, frente em −Z | Peças com nome. Articulações `jnt_*`, com os nomes dos ossos diferentes dos nomes das malhas. Até ~4 000 triângulos por pet, ~2 000 por adereço. Cores lisas por material (eu faço o bake dos studs). |
| Animações | **Dentro do GLB do pet**, um clip por nome | A raiz não se mexe. 30 fps. Só **rotação e translação** (a escala é ignorada). Depois corro `scripts/export-pet-anims.py`. |
| Efeitos | **PNG 1024×1024** com fundo transparente, em grelha 4×4 ou 8×8 | Cada frame centrado, mais um GIF de referência. |
| Ícones | **PNG 512×512** com fundo transparente | No estilo do pack: contorno escuro grosso, gradiente com brilho em cima. |
| Texturas | **PNG 512×512 ou 1024×1024** que repete | Sem texto. |

Bloco de estilo para colar no início de **todos** os prompts de modelos:

> *Low-poly stylized asset for a bright Roblox game, chunky bevelled blocks with faceted edges, flat saturated colours, subtle Roblox stud pattern only on large flat tops, friendly rounded proportions, readable silhouette from 30 metres, no text, no realistic textures. Matches the existing Free a Pet! map (white-and-gold plaza with a crystal fountain, blocky green forest, terracotta desert) and pets (Acorn Squirrel, Hopping Mushroom, Branch Deer, Running Cactus, Ball Scorpion, Sun Camel). Export GLB, Y-up, facing -Z, origin at the bottom centre, 1 unit = 1 metre.*

---

## A. Modelos 3D

### A1. Pets e batalha

| # | Asset | P | Para quê | Tamanho em jogo |
|---|---|---|---|---|
| 1 | **Inicial Forest** | P1 | Sem os 3 iniciais as batalhas ficam desligadas no jogo publicado | Adulto 4.5 studs |
| 2 | **Inicial Desert** | P1 | Idem | 4.5 |
| 3 | **Inicial Neutral** | P1 | Idem | 4.5 |
| 4 | **Pet Capsule** | P1 | Hoje é uma bola azul feita por código | 0.5 m |

**Iniciais.** O nome e o conceito ainda estão por decidir; abaixo estão as propostas do relatório anterior. Todos são rígidos, com as articulações `jnt_root`, `jnt_hips`, `jnt_head`, `jnt_tail_*` e `jnt_leg_FL/FR/BL/BR`. Cada um traz três fases de crescimento (Baby, Juvenile, Adult) como objetos separados.

- **Forest:** `[STYLE] A small brave forest starter creature: round fox-like cub made of moss-green and bark-brown blocks, leaf-shaped crest on its head, curled tail ending in a three-leaf sprout, cream belly, amber eyes, confident forward lean. Head 40% of its height. Adult 2.5 m tall.`
- **Desert:** `[STYLE] A small desert starter creature: sand-coloured fennec-like pup with oversized ears glowing warm orange at the tips, a sun-disc mark on its forehead, terracotta stripes on its back, short bushy tail, alert pose. Adult 2.5 m tall.`
- **Neutral:** `[STYLE] A small neutral starter creature themed on the white-and-gold plaza: round sky-blue and white puppy-like creature with gold trim, a tuft on its head shaped like a tiny fountain made of three translucent blue blocks, star-shaped gold collar tag, no elemental features. Adult 2.5 m tall.`

**Pet Capsule:** `[STYLE] A pet capture capsule, 0.5 m sphere split horizontally into two halves: top half sky-blue, bottom half white, gold ring around the middle with a paw-print button at the front. The top half is a separate object hinged at the back (bone jnt_lid), the button is a separate object (bone jnt_button), root bone jnt_root at the bottom. Under 1,500 triangles.` Clips: `Throw` (0.6 s), `Shake` (0.5 s, one wobble), `Open` (0.4 s), `Lock` (0.4 s, button lights).

### A2. Mapa: corrigir o que está mal

| # | Asset | P | Problema hoje | Pedido |
|---|---|---|---|---|
| 5 | **Textura do chão (relva, areia, praça)** | P1 | Os studs estão 2× maiores que os normais do Roblox e o verde é demasiado lima, por isso o mundo parece um tapete gigante | Faço o re-bake no Blender com studs de 1×1 e cores menos saturadas. **Não precisas de fazer nada além de aprovar.** |
| 6 | **Tábua das placas das bases, sem texto** | P2 | "BASE n" vem pintado na textura | `[STYLE] A wooden-framed sign board 3 m wide and 1 m tall on a single post, red painted board with a white bevelled border, blank board face, no text or symbols.` |
| 7 | **Faixa do arco do portão da floresta, sem texto** | P2 | Ficou vazia depois de tirar o "SAFE ZONE" | `[STYLE] A wide arched banner board 19 m wide and 4 m tall, sky-blue with a gold border and white rivets, bevelled chunky edges, blank face, flat back.` |
| 8 | **Falésias com variação** (3 peças modulares) | P2 | A parede à volta do mapa é sempre o mesmo bloco | `[STYLE] Three modular cliff pieces, 20 m wide and 30–40 m tall, slate blue-grey stacked rock blocks with green grassy tops, each piece with a different silhouette: one with a ledge and hanging vines, one with a small waterfall notch, one with a crystal outcrop. Tileable side to side.` |

### A3. Mapa: encher os espaços vazios

Hoje as bases e os relvados da praça são grandes e lisos. Estes adereços dão escala e vida sem criar sistemas novos.

| # | Asset | P | Onde |
|---|---|---|---|
| 9 | **Kit de base** (casota, bebedouro, tapete de dormir, comedouro) | P2 | Dentro de cada base, para os pets terem para onde ir |
| 10 | **Kit da praça** (banco, candeeiro, canteiro, banca de mercado, caixote) | P2 | Nos relvados da praça e ao longo dos caminhos |
| 11 | **Kit da floresta** (cogumelo gigante, tronco caído, arbusto com bagas, pedra com musgo, ponte pequena) | P2 | Entre as áreas de spawn |
| 12 | **Kit do deserto** (ossos grandes, rocha em arco, cacto alto, tenda em ruínas, vaso de barro) | P2 | Idem |
| 13 | **Moldura da tabela global** (estrutura dourada com pódio) | P3 | Hoje são duas colunas e uma placa feitas por código |

Prompt de exemplo (troca o kit):
`[STYLE] A set of 5 separate props for a pet's home area in a stylized Roblox game: a small wooden pet house with a round door and red roof (2 m), a stone water bowl (1 m), a woven sleeping mat (2 m), a food bowl filled with acorns (0.8 m), a short white picket fence segment (3 m). Each prop a separate object, origin at its base.`

---

## B. Animações (para os 6 pets atuais e os 3 iniciais)

Já existem e estão ligadas: **Idle e Walk**. Faltam estas, por ordem de impacto:

| # | Clip | P | Duração | Loop | Onde aparece | Movimento |
|---|---|---|---|---|---|---|
| 14 | `Hit` | P1 | 0.3–0.4 s | não | Cada golpe recebido | Cabeça e corpo para trás, encolhe e recupera |
| 15 | `Faint` | P1 | 1.0 s | não | Desmaio | Cambaleia, cai de lado e fica parado no último frame |
| 16 | `Attack` | P1 | 0.6–0.8 s | não | Cada ataque | Antecipa e investe. Esquilo: chicote da cauda. Cogumelo: salta e cai de chapéu. Veado: investe com as hastes. Cacto: rodopia de braços abertos. Escorpião: ferroada por cima do corpo. Camelo: empina e pisa |
| 17 | `BattleIdle` | P2 | 1.2–1.6 s | sim | Durante a batalha | Corpo baixo, peso a balançar, cabeça no adversário |
| 18 | `Happy` | P2 | 1.0 s | não | Captura, vitória, subir de nível, depositar na base | Dois saltos e abana a cauda |
| 19 | `Carried` | P2 | 1.0 s | sim | Ao colo do jogador | Patas a balançar e cabeça a olhar à volta (hoje fica rígido) |
| 20 | `Sleep` | P3 | 2.0 s | sim | Na base, quando está parado há algum tempo | Deitado, a respirar devagar |
| 21 | `Special` | P3 | 0.9–1.2 s | não | O ataque forte | Carrega e liberta |

Prompt base: `Animate the existing rig of <SPECIES> for a stylized Roblox creature game. Clip "<CLIP>", <DURATION>, 30 fps, <loop / one-shot>. In-place: the root bone does not move. Motion: <MOVEMENT>. Snappy cartoony timing with clear anticipation and overshoot, readable from 15 m. Rotate bones only (no scaling). Export the GLB with the rig and every clip.`

**Mais impacto com menos trabalho:** começa por `Hit` e `Faint` num só pet (o esquilo). Eu confirmo que o caminho funciona, e só depois fazes os outros.

---

## C. Efeitos (VFX)

Hoje uso as partículas nativas do Roblox (faíscas e fumo genéricos). Estas folhas dão identidade aos efeitos:

| # | Efeito | P | Quando aparece | Aspeto |
|---|---|---|---|---|
| 22 | `fx_hit_star` | P1 | Qualquer golpe | Estrela branca e amarela com 6 lascas, 8 frames |
| 23 | `fx_leaf_burst` | P1 | Ataques Forest | Folhas chanfradas a rodar para fora, 16 frames |
| 24 | `fx_sand_blast` | P1 | Ataques Desert | Leque de areia com brilho laranja, 16 frames |
| 25 | `fx_capture_flash` | P1 | A cápsula fecha | Anel branco que passa à cor da raridade, 8 frames |
| 26 | `fx_faint_puff` | P2 | Desmaio | Nuvem de pó cinzenta, 8 frames |
| 27 | `fx_heal_rings` | P2 | Fonte (Heal team) | Anéis verdes a subir, 8 frames |
| 28 | `fx_levelup` | P2 | Subir de nível | Seta dourada a subir com estrelas, 8 frames |
| 29 | `fx_battle_ring` | P2 | Chão da arena (hoje são 28 blocos Neon) | Textura circular estática 1024×1024 com runas de patas |
| 30 | `fx_cash_pop` | P2 | Dinheiro a entrar na base | Moeda ou nota a saltar com brilho, 8 frames |
| 31 | `fx_release_poof` | P2 | Soltar um pet | Nuvem de relva ou areia com corações pequenos, 8 frames |
| 32 | `fx_shield_hex` | P3 | Bolha do Release Shield (hoje é ForceField) | Padrão hexagonal azul que repete, 512×512 |
| 33 | `fx_theft_alert` | P3 | Por cima de um pet a ser desafiado | Ponto de exclamação vermelho a pulsar, 8 frames |

Prompt base: `Game VFX sprite sheet for a stylized Roblox game, <DESCRIPTION>, <8 frames in a 4x2 grid / 16 frames in a 4x4 grid>, 1024x1024 PNG, transparent background, each frame centred and the same size, bold flat shapes with a thick dark outline like a mobile game icon pack, at most 3 shading steps, no text. Palette: <COLOURS>.`

Paletas: Forest `#5FCB4A #38B26B #2E7D32`. Desert `#FFB84D #E07A1F #B5531A`. Neutral e cura `#6FD3FF #FFFFFF #FFD23F`.

---

## D. Ícones (PNG 512×512, estilo do pack)

| # | Ícone | P | Substitui |
|---|---|---|---|
| 34 | `trade` (duas setas a trocar entre dois pets) | P1 | O separador Trade usa a seta "upgrade" |
| 35 | `index` (livro com grelha de silhuetas) | P1 | O Index usa o distintivo "rare" |
| 36 | `inventory` (mochila com uma pata) | P2 | Usa a caixa de transporte |
| 37 | `loose_pets` (pegadas a sair por uma porta) | P2 | "More Loose Pets" usa o cadeado aberto, que parece "bloqueado" |
| 38 | `type_forest`, `type_desert`, `type_neutral` | P2 | Hoje o tipo é só texto e cor |
| 39 | `capsule`, `run`, `switch`, `heal`, `defend` | P2 | Os botões de batalha são só texto |
| 40 | `tablet` (o aparelho) | P3 | O botão do HUD usa a caixa de transporte |

Prompt: `Game UI icon, 512x512 PNG, transparent background, <SUBJECT>, thick dark navy outline, saturated glossy gradient with a soft white highlight on top, chunky rounded shapes, same style as a cartoony mobile game icon pack, centred, no text.`

---

## E. Som (do catálogo do Roblox; eu escolho e ligo, não precisas de gerar nada)

| # | Grupo | P | Sons |
|---|---|---|---|
| 41 | Interface | P1 | Clique, abrir e fechar o tablet, erro, sucesso, notificação |
| 42 | Economia | P1 | Cash a entrar (suave), comprar, recompensa |
| 43 | Pets | P1 | Apanhar, pousar, soltar, chegar à base, cada espécie a "falar" (curto) |
| 44 | Batalha | P1 | Início, golpe normal, golpe forte, super efetivo, desmaio, cápsula a abanar, captura, subir de nível, vitória, derrota |
| 45 | Música | P2 | Praça (calma), floresta, deserto, batalha (loop curto) |
| 46 | Ambiente | P2 | Fonte, cascata, pássaros na floresta, vento no deserto |
| 47 | Perigos | P3 | Batida do coração a 75% de exposição (hoje é um bip genérico) |

---

## F. Apresentação do jogo

| # | Asset | P | Para quê |
|---|---|---|---|
| 48 | **Ícone do jogo** 512×512 | P1 | É o que as pessoas veem antes de entrar |
| 49 | **3 thumbnails** 1920×1080 | P1 | Página do jogo |

Ícone: `Roblox game icon, square, bright and bold: a cute blocky Acorn Squirrel and Sun Camel bursting out of an opened sky-blue pet capsule in front of a white-and-gold crystal fountain, sparkles, big chunky title text "FREE A PET!" in white with a thick navy outline, saturated colours, high contrast, readable at small size.`

Thumbnail 1: `Roblox game thumbnail 16:9, a player character in a blocky green forest facing a wild Branch Deer inside a glowing blue battle ring, move buttons hinted at the edges, action pose, sparks, bright saturated stylized look.`

Thumbnail 2: `Roblox game thumbnail 16:9, a cosy player base full of blocky pets (squirrel, mushroom, cactus, camel) wandering on grass with floating "+$" coins, a "Ana's Base" sign, warm afternoon light.`

Thumbnail 3: `Roblox game thumbnail 16:9, a player sneaking away carrying a glowing rare Sun Camel over their head across a terracotta desert, another player chasing, dramatic sunset light.`

---

## Ordem para não desperdiçar trabalho

1. **Eu, já:** o re-bake do chão (#5), o som (#41–47) e o "juice" com partículas nativas. Não dependem de ti.
2. **Tu:** `Hit` e `Faint` só do esquilo (#14–15). Eu ligo-os, confirmamos, e depois fazes os outros 5 pets.
3. **Tu:** os 3 iniciais (#1–3), que ligam as batalhas no jogo publicado, e a Pet Capsule (#4).
4. **Tu:** os ícones P1 (#34, #35) e os efeitos P1 (#22–25).
5. **Tu:** as tábuas sem texto (#6, #7) e os kits de adereços (#9–12). Eu distribuo-os pelo mapa.
6. **Tu:** o ícone e os thumbnails (#48–49), mesmo antes de publicar.
7. O resto (P3) no fim.
