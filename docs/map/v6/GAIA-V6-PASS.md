# Mapa V6: passagem da Gaia (pedido do JB, 2026-11-09)

Place "Free a Pet!" (109653985388163), mapa em `Workspace.Map.Collision.NewMap_V6`.
Não mexi em `Map.Zones`, `Map.SpawnAreas`, `Map.Bases`, `Map.FX.V3Presentation`, `Lobby.Spawn`, no nome e no pivô de `Lobby.Plaza.spawn_fountain`, nem no material ou na textura do Ground.

## Backups (ServerStorage)
- `GaiaV6Backup_20261109`: cópia do NewMap_V6 e do Lighting antes de começar, mais o `MapV6Mood_orig`.
- `GaiaV6Removed_20261109`: tudo o que saiu do mapa, por motivo, cada peça com o atributo `GaiaOrigPath`:
  - `BuriedTiles` (234);
  - `HiddenInside` (1654);
  - `ReliefDupPlates` (162);
  - `OldMushroomGrove`;
  - `OldPyramidTemple`;
  - `OldPortalSurface`;
  - `GateForestOldIcon`.

## Alterado
1. **Falhas**
   - (a) As costelas de `Desert.Bones` formam agora 4 arcos contínuos (28 peças).
   - (b) `Mountains.GapFill` tapa o fosso entre o anel e o Background em todo o perímetro (608 peças, topo entre 30 e 40).
   - (c) Os `Bush_Big` têm verdes escuros em 3 tons e alguns têm bagas.
   - (d) `Mountains.BoundaryWalls` são 4 paredes invisíveis no eixo do anel, de y0 a y160, com `CanQuery=false`. `East.East_Raise` sobe a crista em z3600-3650.
   - (e) Removi os ladrilhos enterrados, as peças totalmente escondidas dentro de outras e as placas finas duplicadas do Relief.
2. **Cascata e lago**
   - `Lake_Waterfall.WaterFX`: 3 beams de água a correr (textura própria), espuma, salpicos, névoa, ondulação no lago e luz fria.
   - `LakeLife`: caminho de pedras desde o caminho principal até uma rocha-miradouro junto à queda, juncos e taboas, 3 rãs, libélulas e borboletas.
3. **Floresta**
   - 45 ladrilhos novos em `Forest.Path` (`PathTile_DarkN/W/E`) dão 3 entradas para a Dark Forest.
   - Moví 56 árvores, decorações e montes do Relief para longe dos caminhos e das SpawnAreas (espaço livre de 8 ou mais studs).
4. **Dark Forest** (`Forest.MushroomGrove`, refeita; ficaram só o `ExpandedFloor` e o `FloorTexture`)
   - anel de pedras escuras em volta da área do HoppingMushroom;
   - 20 árvores retorcidas com cogumelos luminosos;
   - 7 cogumelos gigantes com luz;
   - grupos de cogumelos luminosos e um anel de fadas;
   - santuário rúnico, pedras com runas e um tronco caído;
   - 3 arcos de entrada.
   - O nevoeiro e a luz vêm do `MapV6Mood` (abaixo).
5. **Deserto**
   - `PyramidTemple` nova em (1200,3464): 12 andares, base 72, 48 de altura, pyramidion dourado, escadaria sul e porta superior. À frente tem um portal de pilones com hieróglifos e o disco solar alado, e uma avenida.
   - `Egypt_Avenue`: 4 colunas de lótus, 2 obeliscos, 2 esfinges e 2 braseiros com fogo.
   - `Egypt_Props`: 6 colunas partidas, 6 grupos de ânforas, 3 muros com hieróglifos, uma cabeça de faraó meio enterrada, um sarcófago, um escaravelho e 2 estátuas de chacal.
   - O nevoeiro e a luz ao entrar vêm do `MapV6Mood`.
6. **VFX da água**
   - Cascata: ver o ponto 2.
   - Fonte do spawn: os 8 `FallSheet` e o jato ganharam beams de água a correr, e as bacias ganharam ondulação.
7. **`Gates.Gate_Forest`**: o ícone passou a ser um pinheiro (`TreeIcon`), dos dois lados.
8. **`Lobby.SpawnPortal`**
   - O portal (não a pedra) tem agora 3 camadas: fundo escuro, corpo luminoso e pele `ForceField` animada. Tem ainda um vórtice de partículas, névoa a sair, um anel de runas e luz.
   - Detalhes de arena (`ArenaDetails`): um anel embutido no chão com linha central e emblema, cantos vermelho e azul com estandartes, pilaretes e 2 tochas.

## Nevoeiro e luz por zona (`src/client/MapV6Mood.client.luau`)
- O script antigo procurava `Workspace.NewMap_V6`, que não existe, por isso nunca fazia nada.
- Agora encontra o `Map.Collision.NewMap_V6` e usa limites absolutos iguais aos `Map.Zones`.
- A Dark Forest e o Desert têm um perfil de entrada e um perfil de fundo, misturados pela profundidade a que o jogador está: o nevoeiro aumenta e a luz muda à medida que se entra.
- Sai do mapa e repõe a luz anterior. Convive com o `ZoneMood`.

## Texturas
- `tools/vfx/make-water-textures.ps1` gera `water_streaks.png` e `water_ripple.png`.
- Subiram para o grupo 11782476: estrias `rbxassetid://102210963899605` (estava em revisão de moderação quando subiu) e ripple `rbxassetid://122444912584703` (aprovada).
