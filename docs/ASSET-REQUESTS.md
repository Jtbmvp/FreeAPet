# Pedidos de arte para o Claude Design (conceito v2)

Para fazeres no Claude Design. Mantém o estilo atual: blocos chanfrados e facetados, textura de studs, contorno escuro nos ícones.
Formatos: **modelos e animações → GLB** (como as folhas atuais: peças com nomes, articulações `jnt_*`, clips com nome); **efeitos → folhas de sprites PNG** (fundo transparente, 1024×1024, grelha 4×4 ou 8×8 frames, cada frame centrado) **+ um GIF/vídeo de referência**; **ícones → PNG 512×512** no estilo do pack.

## A. Animações novas para os 6 pets (e para os iniciais)
Já existem: `Idle` (loop) e `Walk` (loop). Faltam, em cada folha, com estes nomes exatos:
| Clip | Duração | Loop | O que mostra |
|---|---|---|---|
| `BattleIdle` | 1.2–1.6 s | sim | Postura de luta: corpo baixo, a balançar, olhar em frente |
| `Attack` | 0.6–0.8 s | não | Investida física: recua, salta para a frente, volta |
| `Special` | 0.9–1.2 s | não | Ataque do tipo: carrega energia (cabeça/cauda para trás) e liberta |
| `Hit` | 0.3–0.4 s | não | Leva um golpe: recua e encolhe |
| `Faint` | 1.0 s | não | Desmaia: cai de lado, termina parado no chão |
| `Happy` | 1.0 s | não | Vitória/captura: salta e abana |
Regras: a raiz do pet não se desloca (só as articulações), para o jogo controlar a posição. Anima só **rotação e translação** das `jnt_*` (a escala é ignorada no Roblox). Exporta todos os clips no mesmo GLB do pet; depois corre `python3 -I scripts/export-pet-anims.py`.

## B. Os 3 iniciais (folhas completas como as atuais)
Um **Forest**, um **Desert** e um **Neutro** (tema "Plaza"/cidade: azul, branco e dourado da Safe Zone). Cada um com: paleta, vistas, 3 fases de crescimento, rig, `Idle`, `Walk` + os 6 clips da secção A. Nome e conceito: propõe-me 2–3 ideias por tipo e escolhemos.

## C. Item de captura (*Pet Crate* — nome provisório)
- Modelo GLB pequeno (≈0.5 m), estilo caixa de transporte/cápsula com studs, cores do tipo neutro.
- Clips: `Throw` (gira no ar), `Shake` (abana 3×, 1.8 s), `Open` (abre e liberta), `Lock` (fecha com sucesso).

## D. Efeitos (folhas de sprites PNG)
| Efeito | Uso | Descrição |
|---|---|---|
| `fx_hit_star` | todo o golpe físico | Estrela de impacto branca/amarela, 8 frames |
| `fx_leaf_burst` | ataques Forest | Folhas verdes a rodar e espalhar, 16 frames |
| `fx_spore_cloud` | ataques Forest | Nuvem de esporos verde-clara a crescer, 16 frames |
| `fx_sand_blast` | ataques Desert | Rajada de areia em leque, 16 frames |
| `fx_sun_beam` | ataques Desert | Feixe/anel de luz dourada (pode ser textura de Beam 512×128) |
| `fx_heat_wave` | ataques Desert | Distorção ondulada laranja, 16 frames |
| `fx_sparkle` | Neutro, raro, cura | Brilhos em estrela azul/branco, 8 frames |
| `fx_capture_flash` | captura | Flash circular branco→cor do tipo, 8 frames |
| `fx_faint_puff` | desmaio | Nuvem de poeira cinza, 8 frames |
| `fx_heal_rings` | fonte de cura | Anéis verdes a subir, 8 frames |
| `fx_battle_ring` | início de batalha | Anel de chão (textura circular 1024×1024, não animado) |

## E. Cutscene e transição de batalha
- **Transição de entrada**: 1 imagem 1920×1080 de "studs a fechar o ecrã" (padrão de studs no estilo do pack) — eu animo-a por código.
- **Banner "A wild … appeared!"**: moldura PNG 1024×256 no estilo do pack (texto fica por código).
- **Música**: não é preciso; uso o catálogo de áudio do Roblox (gratuito e licenciado).

## F. Ícones novos (PNG 512×512, estilo do pack)
- Tipos: `type_forest` (folha), `type_desert` (sol), `type_neutral` (estrela/escudo azul).
- Batalha: `battle` (espadas cruzadas ou patas a chocar), `run` (fugir), `team` (3 patas), `crate` (item de captura).
- Tablet: `tablet` (o aparelho), `index` (livro/grelha de silhuetas), `inventory` (mochila de pets), `heal` (coração com cruz).

## G. Tablet (opcional)
- Moldura PNG do tablet 1600×1000 (ecrã transparente ao centro, botões laterais) no estilo do pack — eu ponho o conteúdo por cima.

## H. Para enviar já (Bulk Import no Studio)
- `assets/ui-upload/hex_fill.png` e `assets/ui-upload/hex_frame.png` (árvore da pesquisa). Depois cola os dois `rbxassetid://…` em `Config/UI.luau` (`hex_fill`, `hex_frame`).
- Ícone novo pedido: `loose_pets` (pata a sair de uma porta aberta, ou 3 pegadas) para o nó "More Loose Pets"; hoje usa o cadeado aberto, que se confunde com "bloqueado".
