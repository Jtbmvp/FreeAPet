# Mapa V4: contrato que o código exige

Tirado por grep de `src/` em `origin/v3-integration` (commit `ac190e5`, 2026-11-08). Autor: Forge (Coder).
Para cada contrato: caminho ou nome exato, atributos e tipos, quem o lê e o que parte se faltar.
As linhas referem-se a esse commit. Se um contrato tiver de mudar, vai num PR de código à parte.

Legenda: **OBRIGATÓRIO** = o serviço fica bloqueado ou dá erro sem ele; **RECOMENDADO** = degrada com aviso; **OPCIONAL** = só melhora.

## 0. Raiz

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Workspace.Map` | qualquer contentor (hoje é uma Folder) | `AnimalService.luau:342`, `BaseService.luau:117`, `ZoneService.luau:142`, `BattleService.luau:837`, `MapPolishService.luau:31` (todos com `WaitForChild` sem timeout); `ZoneMood.luau:76` (timeout de 15 s) | **OBRIGATÓRIO.** Ficam à espera para sempre. |

Todos os filhos abaixo são lidos **no arranque, uma só vez**. Trocar o mapa a meio do jogo não é suportado.

**Atenção:** o `Main.server.luau:35-37` arranca os serviços **em série** (`service.Start()` síncrono), por esta ordem: … `MapPolishService` (2.º), … `BaseService`, `ZoneService`, `AnimalService`, … `BattleService`, … `PlayerDataService` (último). Um `WaitForChild` sem timeout que nunca resolve **bloqueia todos os serviços seguintes**, incluindo o carregamento dos dados dos jogadores. Por isso os contratos OBRIGATÓRIOS abaixo deitam abaixo o jogo inteiro, não só o seu sistema.

## 1. `Map.SpawnAreas` (pets selvagens)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Map.SpawnAreas` | Folder | `AnimalService.luau:343` (`WaitForChild`, sem timeout) | **OBRIGATÓRIO.** O `AnimalService.Start` bloqueia: não se cria `workspace.Animals`, não há selvagens e o `SpawnWild` devolve sempre `nil`. |
| Filhos **diretos** `BasePart` (as subpastas são ignoradas) | Part, usada como retângulo | `AnimalService.luau:344` (`GetChildren`) | Peças dentro de subpastas não contam. |
| attr `SpeciesId` | string, um id de `Config.Species` (`AcornSquirrel`, `HoppingMushroom`, `BranchDeer`, `RunningCactus`, `BallScorpion`, `SunCamel`) | `AnimalService.luau:346` | Sem ele a área serve qualquer espécie do `BiomeId`. Com um id inexistente, a área nunca é usada. |
| attr `BiomeId` | string, uma chave de `Config.Biomes` (`Forest`, `Desert`) | `AnimalService.luau:345` | Uma área sem `SpeciesId` **e** sem `BiomeId` dá erro de tipo e o arranque parte. Mantenham os dois atributos sempre. |
| attr `Rare` | boolean | `AnimalService.luau:348` | `true` = área escondida do Raro do dia (`DayCycleService.luau:30`). Se não existir, o Raro nasce na área normal da espécie. |
| Geometria | Size.X × Size.Z = retângulo de spawn e de passeio (Y ignorado); o pet nasce a Y = centro da área + 2.5 studs (e depois cai) | `AnimalService.luau:73-85` e `:121` | Uma área rodada é suportada (CFrame local). Deve ficar **à altura do chão**: o spawn não faz raycast. Os atributos `FaP_SourceSpawnShape`/`Radius` não são lidos (o círculo vira o quadrado inscrito). |

Hoje: 8 Parts, uma por espécie, mais `RarePetSpawn_BranchDeer` e `RarePetSpawn_SunCamel`. Os nomes são livres; contam os atributos.

## 2. `Map.Zones` (zona do jogador)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Map.Zones` | Folder | `ZoneService.luau:143` (`WaitForChild`, sem timeout) | **OBRIGATÓRIO.** O `ZoneService.Start` bloqueia e o atributo `Zone` do jogador nunca se atualiza. |
| Filhos diretos `BasePart` com attr `ZoneId` | caixa (OBB: X, Y e Z contam, rotação suportada) | `ZoneService.luau:144`, `ZoneAt` em `:29-36` | Um ponto fora de todas as caixas dá `"None"`. Se as caixas se sobrepõem, ganha a primeira da lista (ordem não garantida); não as sobreponham. |
| valores de `ZoneId` | string: `"Base"`, `"Forest"`, `"Desert"` (o resto também passa) | `ZoneMood.luau:11` (iluminação safe/floresta/deserto), `Soundscape.luau:17-25` (música e ambiente), `CarryService.luau:70` e `BattleService.luau:414` (`origin.place` do pet apanhado, que fica no save), `DebugHud.luau:35` | Com outro valor: música de praça, iluminação "safe" e um `place` estranho no save. Mantenham estes três ids, ou combinem antes. A altura (Y) das caixas tem de cobrir o jogador a saltar. |
| attr `HazardZone` (Fog/Heat) | — | **não é lido** em `src/` | Não é contrato de código. Os volumes de nevoeiro/calor são só visuais/FX. |

## 3. `Map.Bases` (bases dos jogadores)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Map.Bases` | Folder | `BaseService.luau:117`, `ZoneService.luau:148` (`WaitForChild`, sem timeout) | **OBRIGATÓRIO.** Sem bases e sem spawn dos jogadores. |
| Cada base = filho direto **`Model`** | Model (as Folders são ignoradas pelo BaseService) | `BaseService.luau:13-24` | Nº de bases = jogadores máximos; o jogador a mais fica sem base (aviso `No free plot`). Ponham o Max Players igual ao nº de bases. |
| attr do Model `PlotIndex` | number, único (1..N, é a ordem de atribuição) | `BaseService.luau:22`, copiado para `player.PlotIndex` em `:61` | **OBRIGATÓRIO.** Sem ele, o `table.sort` compara `nil` e dá erro → o BaseService parte. |
| attr do Model `OwnerUserId` | number, **escrito** pelo código | `BaseService.luau:60/81` | Não o ponham no mapa. |
| `Plot.Spawn` | BasePart, filho direto | `BaseService.luau:43` | **OBRIGATÓRIO.** Erro ao fazer spawn (índice de `nil`). O jogador aparece a +4 studs acima do CFrame. |
| `Plot.SafeZone` | BasePart, filho direto, caixa OBB | `ZoneService.luau:149` (`InSafeZone`, `InOwnBase`, `FindArenaCenter` empurra as arenas para fora) | **RECOMENDADO.** Sem ele: a base deixa de ser zona segura e podem nascer arenas de batalha dentro da base. Hoje: 100×30×100. |
| `Plot.Sign` com um `TextLabel` chamado **`Label`** algures dentro (SurfaceGui) | qualquer, procura recursiva | `BaseService.luau:28-36` | Aviso `has no Sign with a Label`; não aparece "X's Base"/"Free Base". |
| `Plot.PetArea` | BasePart, filho direto, retângulo X×Z | `BaseService.luau:107-110` → `HomeService.luau:126` | Os pets da base ficam parados no slot (`ParkAt`) em vez de passear. |
| `Plot.Slots` | Folder/Model, filho direto | `BaseService.luau:92` | Sem slots: não se podem pôr pets na base. |
| `Plot.Slots.*` | BaseParts, filhos diretos, com attr `SlotIndex` (number 1..N, únicos) | `BaseService.luau:95-101`, `HomeService.luau:71/77/123/164` | Uma pad sem `SlotIndex` dá erro de comparação com `nil`. São precisas pelo menos `Config.Economy.baseStartingSlots` = **6** por base (mais se houver upgrades). O pet fica em cima da pad (topo + Size.Y/2). |

## 4. `Map.Collision` (chão e obstáculos para raycasts)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Map.Collision` | Model/Folder com as peças sólidas (chão, árvores, rochas, paredes) | `BattleService.luau:170` (rodar a arena para a vista mais limpa), `BattleCamera.luau:136`, `AttackPresentation.luau:68` (chão dos FX), `LeaderboardService.luau:34` (chão do quadro), `BattleObstacles.luau:138` | **RECOMENDADO.** Sem ele não há leaderboard (`buildBoard` devolve `nil`), as arenas não se rodam e a câmara e os FX usam só o Terrain. |
| peças com `CanCollide=true` e `CanQuery=true` | BasePart | `AttackPresentation.luau:64` (`RespectCanCollide`) | O chão dos ataques cai para os pés do pet. |
| `board_panel` (procura recursiva dentro de `Collision`) | BasePart | `LeaderboardService.luau:65` | **OPCIONAL.** Sem ele, o código constrói postes e painel próprios. |
| Posição do quadro de líderes | fixa em `Config.Gameplay.leaderboard.position = (-176, 0, 0)`, virado para +X | `Config/Gameplay.luau:46-47`, raycast de cima em `LeaderboardService.luau:39` | Se a praça mudar de sítio, é preciso atualizar a Config (contrato de código: PR à parte). |

## 5. Chão para a batalha (BattleService)

- `groundAt` (`BattleService.luau:102-125`): raycast **Exclude** desde +6 studs para baixo até 60 studs, ignorando `Workspace.Battles`, `Workspace.Animals`, `Map.Art` e as personagens. Ou seja, **tudo** o resto em `Workspace` conta como chão, incluindo FX e volumes de zona com `CanQuery=true`.
  - Volumes invisíveis (`Zones`, `SafeZone`, `SpawnAreas`, FX) devem ter **`CanQuery=false`**, senão a arena ou o pet ficam pousados em cima deles. Em alternativa, ponham-nos sem colisão e dentro de `Map.Art`.
  - Copas de árvores abaixo de 6 studs acima do jogador também apanham o raio.
- `FindArenaCenter` (`ZoneService.luau:87-109`): a arena precisa de um círculo livre de `SafeZone`s com raio `ARENA_FOOTPRINT_RADIUS` (≥ `Config.Battle.arenaRadius` = 15 studs + câmara/banco, `BattleService.luau:70-75`) e só se desloca no máximo esse raio + 1. Os corredores entre bases e o mato têm de ter espaço; senão aparece "There's not enough space here for a battle".
- `clearestFacing` faz raycasts **Include** só em `Map.Collision` (ver 4).

## 6. Fonte de cura (`spawn_fountain` → `HealPoint`)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `spawn_fountain` em qualquer sítio dentro de `Map` (procura recursiva, a primeira encontrada) | Model (usa o `GetPivot`) ou BasePart | `BattleService.luau:838` | **RECOMENDADO.** Aviso `No spawn_fountain in the map: no healing point` → não há cura no mundo. |
| `HealPoint` | **criado pelo código** em `Workspace.Battles.HealPoint` (no chão debaixo da fonte, `InteractionRadius` = 30) | `BattleService.luau:843-853`, `ContextActions.luau:245-247` | Não o ponham no mapa. Só tem de haver chão por baixo da fonte (ver 5). |

## 7. `Map.Art` (malhas só visuais) e texturas

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Map.Art` | Model/Folder | `MapPolishService.luau:31` (`WaitForChild`, **sem timeout**) | **OBRIGATÓRIO enquanto o MapPolishService existir:** é o 2.º serviço a arrancar; sem `Art`, bloqueia para sempre e **nenhum serviço seguinte arranca** (o servidor fica morto). Hoje existe e está vazio (0 descendentes). Mantenham uma pasta `Art`, mesmo vazia, ou mudem o código num PR à parte. |
| Texturas | MeshParts cujo **pai** se chama como uma chave de `Config.MapTextures` (o sufixo `.001` é ignorado): `Desert_c_EEA84F`, `Desert_c_EFAB52`, `Desert_c_F0AF56`, `Desert_c_F1B65D`, `Desert_c_F2BD63`, `Desert_c_F3C369`, `Desert_c_F5C96F`, `Desert_hot_dune`, `Desert_sun_sand`, `Forest_c_379437`, `Forest_c_3DA139`, `Forest_c_43AD3B`, `Forest_c_47B83D`, `Forest_c_70D04A`, `Forest_meadow_green`, `SafeZone_boulevard_slate`, `SafeZone_plaza_lawn`, `SafeZone_plaza_paving`, `SafeZone_reserved_lawn`, `SafeZone_trim_white` | `MapPolishService.luau:32-41`, `Config/MapTextures.luau` | **OPCIONAL.** Sem correspondência, nada muda. Todos os ids estão vazios: no jogo publicado não faz nada, só no Studio com Debug. O V4 pode ignorar isto ou trazer uma lista nova de pastas (PR de Config). |
| `Art` excluído dos raycasts de chão | — | `BattleService.luau:110`, `TeamFollower.luau:104` | Arte só visual deve estar em `Art` (ou com `CanQuery=false`), senão conta como chão. |
| Arte pequena em `Art`/`FX` | BaseParts com maior lado ≤ 40 e altura ≥ 1.5 | `BattleObstacles.luau:154-163` | Ficam transparentes localmente na batalha quando tapam a câmara. |

## 8. `Map.FX` e apresentação V3 (cliente, ZoneMood)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `Map.FX` | Folder | `ZoneMood.luau:77` (timeout de 15 s) | Aviso `[ZoneMood] V3 presentation unavailable`: não há iluminação por zona nem controlo de FX. O jogo funciona. |
| `Map.FX.V3Presentation` | contentor com 3 `StringValue` de JSON: `LightingProfiles` (chaves `safe`, `floresta`, `deserto`; grupos `Lighting`, `Atmosphere`, `Bloom`, `ColorCorrection`, `SunRays`, `Sky`; cores `"#RRGGBB"`), `MobileOverrides`, `VFXProfiles` (lista de `{id, timing?, desktopOverrides?, mobileOverrides?}`) | `ZoneMood.luau:78-86` | JSON inválido ou em falta → aviso `Invalid V3 presentation profiles`, sem iluminação por zona. |
| Lighting | `Lighting.FreeAPetAtmosphere`, `FreeAPetBloom`, `FreeAPetColor`, `FreeAPetSunRays` e um `Sky` | `ZoneMood.luau:91-97` | Só não se animam (sem erro). Não é mapa, mas faz parte do pacote. |
| Emissores (qualquer sítio dentro de `Map`, também os que chegam depois) | `ParticleEmitter` com attr `FaP_EffectId` (string; especiais: `desert_dust`, `clearing_glow`), `FaP_DesktopRate`/`FaP_MobileRate` (number) | `ZoneMood.luau:165, 204-232` | Ficam ligados sempre (sem limite de distância de 150 studs nem perfil mobile). |
| Luzes | `PointLight` chamado `V3WarmLamp` | `ZoneMood.luau:167, 235-250` | Ficam como estão; quando existem, só as 4 mais próximas ficam ligadas e sem sombras. |
| Feixe | `Beam` chamado `FountainBeacon` | `ZoneMood.luau:169` | Opcional. |

## 9. Tag `BattleHideable` (cliente, BattleObstacles)

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| Tag CollectionService `BattleHideable` em props (árvores, rochas, arbustos) **dentro de `Map.Collision`** | BasePart ou Model (Model = todas as BaseParts dentro) | `BattleObstacles.luau:20, 140-152, 197` | **RECOMENDADO.** Sem tag, os props de `Collision` nunca escondem e tapam a câmara da batalha. Não ponham a tag em chão, falésias nem peças grandes: escondem-se mesmo. |

## 10. Outros pontos procurados no mapa

| Contrato | Tipo | Lido por | Se faltar |
|---|---|---|---|
| `OriginalClipData` (procura recursiva em `Map`); o pai é o modelo da cápsula | qualquer | `CapsuleSequence.luau:36-38` | Só se `ReplicatedStorage.Assets.BattleCapsule` não existir. Opcional. |
| `FaP_MapVersion` | — | **não é lido** em `src/` | Não é contrato de código (pode ficar como metadado do mapa). |
| `SpawnLocation` | — | não é lido; o spawn real é `Plot.Spawn` | Mantenham pelo menos um SpawnLocation de segurança perto das bases (só para quem fica sem base). |

## Resumo para quem construir o V4

1. A estrutura mínima para o jogo arrancar: `Workspace.Map` com `SpawnAreas`, `Zones`, `Bases` e `Art` (mesmo vazio).
2. Bases: Models com `PlotIndex`, `Spawn`, `SafeZone`, `Slots/*` (`SlotIndex` 1..≥6), `PetArea` e `Sign/…/Label`.
3. `Zones`: caixas com `ZoneId` ∈ {`Base`, `Forest`, `Desert`}, sem sobreposições.
4. `SpawnAreas`: Parts diretas, à altura do chão, com `SpeciesId`, `BiomeId` e `Rare`.
5. `Collision`: chão e obstáculos; props com a tag `BattleHideable`; `board_panel` e `spawn_fountain` opcionais mas recomendados.
6. Volumes invisíveis com `CanQuery=false`.
7. Para mudar ids de zona, biomas, a posição do leaderboard ou nomes de pastas, é preciso um PR de código/Config à parte.
