# Mapa V4: direção de arte

Autora: Iris (direção de arte, MIDAS). Para a Gaia construir. 2026-11-08.
Ordem de prioridade: `docs/DECISIONS.md` > `CONTRACT.md` (Forge) > este ficheiro > `README.md`/`layout.json` > studify/LihFolk.
Onde este ficheiro e o `layout.json` divergirem em cores, materiais, luz ou posições de arte, vale este.
Aprovação visual: só o JB. Nada aqui é "aprovado"; é a direção a construir e mostrar.

## 0. Bases da decisão (porquê estas escolhas)
- **Estilo**: pets "chunky" blocky com studs (DECISIONS 2026-10-26) → mundo stud-style (studify): `Plastic` + MaterialVariant em todas as peças, massas chunky, muito detalhe pequeno.
- **Paleta**: tirada do mapa v2 do Claude Design aprovado pelo developer (`design/map-v2/FreeAPetMap.rbxmx`, cores contadas por peça) e das cores de chão de `Config/MapTextures.luau`. Não uso a paleta do exemplar do studify nem do LihFolk (exemplos de outros jogos não são decisões).
- **Luz**: DECISIONS 2026-10-27 (LightingStyle Soft, `PrioritizeLightingQuality` false, sol baixo 15:36, latitude 25, bloom só nos Neon) + `ZoneMood` (safe neutra, floresta fresca, deserto quente).
- **Variantes no place** (medidas pela Gaia a 2026-11-07): `Studs`, `Universal`, `Inlet`. Usar só estas. Não há `Weld` nem `StudsNoGrid`.

## 1. Mapa e coordenadas

Eixo X = as três zonas lado a lado (como no V3). Origem = centro da fonte (o leaderboard está fixo em `(-176, 0, 0)` virado para +X, `Config.Gameplay`). Medidas em studs.

| Zona | X | Z (jogável) | Tamanho | `ZoneId` |
|---|---|---|---|---|
| Rebordo oeste | −225 … −200 | | 25 | (sem zona) |
| Safe Zone | −200 … 200 | −200 … 200 | 400 × 400 | `Base` |
| Forest | 200 … 560 | −215 … 215 | 360 × 430 | `Forest` |
| Desert | 560 … 1000 | −215 … 215 | 440 × 430 | `Desert` |
| Rebordo este | 1000 … 1025 | | 25 | (sem zona) |
| **Total** | −225 … 1025 | −242 … 242 | **1250 × 485** | |

O anel de planaltos (rebordo) fecha o mapa sem buracos: ≥ 16 de altura, 23-27 nos altos, massas a montar a borda com ~20 % de sobreposição (studify, "Highland borders"). Na Safe Zone a borda é muralha de pedra + colinas; na Forest, falésias de rocha com pinheiros; no Desert, mesas de arenito com estratos.

### 1.1 Esboço (vista de cima, norte = +Z)

```
 Z+242 ┌──────────────────────── rebordo (planaltos ≥16, sem buracos) ─────────────────────────┐
       │ SAFE ZONE (Base)           │ FOREST                  │ DESERT                          │
 Z+200 │ [B1]      [B5]      [B2]   │  cascata ▼ (430,+215)   │   (760,+140) Scorpion Canyon ◎  │
       │ 100²      100²      100²   │  ~~rio~~ lago            │        mesas ▲▲    (960,+150)   │
       │                            │ ◎Mushroom   ◎Deer Meadow│                     Sun Hollow◆ │
       │        ·· praça ··         │ (290,+120)  ~ (510,+120)│   Sun Arch ∩ (840,+30)          │
 Z  0  │LB▸   ⛲ fonte (0,0)  ══════╪═PORTÃO═══ ponte ═══════╪═CANHÃO══ oásis ≈ (880,−50)       │
       │(-176,0)                    │ (200,0)   ~ (450,0)     │ (560,0)  ◎Camel (900,−90)       │
       │ jardim/kiosques            │ ◎Squirrel   ~           │ ◎Cactus Flats (680,−120)        │
 Z−200 │ [B4]      ...      [B3]    │ (290,−120)  ~ ◆Hidden   │        dunas                    │
       │                            │             ~ (520,−160)│                                 │
 Z−242 └──────────────────────────── rebordo ──────────────────────────────────────────────────┘
      X−225        X0            X200                      X560                          X1025
◎ clareira de arena (Ø 56)   ◆ área do Raro (Rare = true)   ═ caminho principal   ~ rio   LB leaderboard
```

### 1.2 Safe Zone (X −200…200)
- **Fonte de spawn** (`spawn_fountain`, herói da zona) em `(0, 0)`: praça circular Ø 100 em `Pavement`, fonte em 3 andares, 26-28 de altura com o `FountainBeacon` por cima (tem de ser ≥ 1,5× a peça mais alta da zona e ver-se de todos os portões). Degraus a subir 0,5 + 0,5 até à bacia (altitude, não plano único).
- **5 bases de 100 × 100** com a entrada virada para a fonte:
  | Base | `PlotIndex` | Centro (X, Z) | Entrada | Acento da base |
  |---|---|---|---|---|
  | B1 | 1 | (−150, +150) | lado SE | `#FF6F91` |
  | B2 | 2 | (+150, +150) | lado SW | `#FFC83D` |
  | B3 | 3 | (+150, −150) | lado NW | `#B57CFF` |
  | B4 | 4 | (−150, −150) | lado NE | `#FF8A3D` |
  | B5 | 5 | (0, +150) | lado S | `#7A9BFF` |
  - Chão da base 1,0 acima do Terrain (pad `Universal` com relva clara). Cerca de 3,5 (postes `Studs` 1×3,5×1 a cada 6, 2 travessas), branca `#FFFFFF` com remate na cor da base. Portão de 12 de largura. Placa `Sign` 8 × 2,8 ao lado do portão, a 4 de altura.
  - `PetArea` 76 × 56 no meio; 6 `Slots` 9 × 9 em fila dupla junto ao fundo; `Spawn` a 6 da entrada, por dentro.
  - A cor de acento vai só em remates (topo da cerca, bandeira, placa); nunca no chão.
- **Corredores** entre bases: 50 de largura (passa uma arena de raio 15 + câmara). Boulevard este-oeste de 30 de largura da fonte ao portão da floresta, em `Cobblestone`.
- **Oeste** `(−176, 0)`: canteiro do leaderboard, virado a +X. Não pôr nada alto entre ele e a fonte.
- **Sul** `(0, −150)`: jardim com lago pequeno e 2-3 kiosques de toldo às riscas (vocabulário stud: 4 postes, balcão, toldo bicolor). Reserva para Shop/Codes futuros; sem gameplay agora.
- **Portão para a Forest** em `(200, 0)`: arco de pedra `#8F9BB0` com ameias, abertura 24 × 14, com a madeira e as folhas da floresta do lado de dentro (a arte do portão pertence à zona onde se entra).
- Árvores: só um tipo, blob de flor de cerejeira (rosa `#FF9CC8`), 15-18 de altura, ~12 no total, nos cantos entre bases e na borda.

### 1.3 Forest (X 200…560)
- **Caminho principal** de terra (`Ground`) 24 de largura, do portão (200, 0) à ponte (450, 0) e ao canhão (560, 0), com curvas suaves (nenhuma aresta reta > 20).
- **Rio**: nasce na falésia norte, **cascata** em `(430, +215)` com 24 de queda para um lago Ø 40; corre para sul em meandro (x 420-480), 16-22 de largura, sai por baixo da falésia sul em `(470, −215)`. Água `Terrain Water` com 2,5-3 de fundo (confirmar que o jogador vadeia e não nada; se nadar, baixar). Margens em `Mud`. Dois degraus (rápido de pedras a meio). **Ponte** de madeira em arco em `(450, 0)`, 14 de largura.
- **Clareiras de arena** (Ø 56, chão plano ± 0,5, nada acima de 6 dentro do círculo, nenhuma copa por cima):
  | Clareira | Centro | Spawn (`SpeciesId`) |
  |---|---|---|
  | Mushroom Hollow | (290, +120) | `HoppingMushroom` |
  | Squirrel Glade | (290, −120) | `AcornSquirrel` |
  | Deer Meadow | (510, +120) | `BranchDeer` |
  | Hidden Rare Glade | (520, −160), acesso por trilho de 8 | `BranchDeer`, `Rare = true` |
- **Herói**: a Grande Árvore, 55 de altura, à beira do Deer Meadow `(530, +160)`, vê-se do portão.
- **Nevoeiro fundo** (FX da Gaia): bolsas a NE (x 480-560, z +150…+215) e SE (x 480-560, z −120…−215) em volta da Rare Glade. O caminho principal fica limpo.
- Árvores: **uma receita** (blob de voxels do studify: tronco quadrado ~40 % da altura, copa de ~7 camadas, uma cor por árvore), 18-32 de altura, ~45 no jogo + pinheiros escalonados só nos planaltos do rebordo. Densas nas bordas, abertas nas clareiras e no caminho.

### 1.4 Desert (X 560…1000)
- **Entrada em canhão** em `(560…600, 0)`: corredor de arenito de 30 de largura e 40 de comprimento com paredes de 20-24. Esconde a troca de luz e de céu (a regra do LihFolk: trocas fortes num canhão ou túnel).
- **Caminho** de arenito (`Sandstone`, mais claro e liso do que as dunas) de 24 de largura até ao oásis.
- **Oásis** `(880, −50)`: lago Ø 50 (`Terrain Water`), anel de `Grass`, 5-7 palmeiras, sombra. É o único sítio verde.
- **Herói**: **Sun Arch**, arco de arenito de 45 de altura e 40 de vão em `(840, +30)`, sobre o caminho.
- **Mesas e cânions** a norte (x 700-1000, z +80…+215): mesas de 25-40 com estratos `#D9733A`/`#B9532E` e topo `#F6CF74`.
- **Dunas** a sul (x 620-1000, z −120…−215): ondulações de 4-10 em `Sand`.
- **Clareiras de arena** (Ø 56):
  | Clareira | Centro | Spawn (`SpeciesId`) |
  |---|---|---|
  | Cactus Flats | (680, −120) | `RunningCactus` |
  | Scorpion Canyon | (760, +140) | `BallScorpion` |
  | Camel Oasis | (900, −110) | `SunCamel` |
  | Sun Hollow | (960, +150), dentro das mesas | `SunCamel`, `Rare = true` |
- **Calor** (FX da Gaia): `desert_dust` e tremura do ar nas dunas e no Sun Hollow; nada no oásis.
- Vegetação: saguaros `#4F9C3F` de 15-30 (ver-se de longe), figueiras-da-índia `#5CB042` baixas, arbustos secos `#B8884A`, ossadas `#F4EAD3`. Palmeiras só no oásis.

## 2. Paleta por zona (hex)

Uma cor dominante por zona, neutros e **um acento que nenhuma outra zona usa**. Saturação no herói, nos interativos e nas recompensas, nunca no chão.
**Cor de interativo do jogo inteiro**: ciano `#4CC3FF` (Neon) só em coisas que se usam (beacon da fonte, pads de spawn, brilho das clareiras em batalha). Não o usar em decoração.

### 2.1 Terrain (cores globais: cada material tem uma só cor no place inteiro)
`Terrain:SetMaterialColor`. Por isso **cada zona usa materiais diferentes**.

| Material | Cor | Zona / uso |
|---|---|---|
| `Grass` | `#6FD86B` | Safe Zone (relvado), anel do oásis |
| `Pavement` | `#D9DEEA` | praça da fonte |
| `Cobblestone` | `#A3AEC0` | boulevards da Safe Zone |
| `Slate` | `#8F9BB0` | falésias e colinas da Safe Zone (pedra periwinkle) |
| `LeafyGrass` | `#43AD3B` | chão da Forest |
| `Ground` | `#8A5A3B` | caminhos da Forest |
| `Mud` | `#5E4A36` | margens do rio |
| `Rock` | `#6E7A70` | falésias da Forest (rocha com musgo) |
| `Sand` | `#F2BD63` | dunas e chão do Desert |
| `Sandstone` | `#D9733A` | paredes de canhão, caminho do Desert |
| `Limestone` | `#F6CF74` | topos das mesas, cristas de duna |
| `Concrete` | `#B9532E` | estratos escuros das mesas (só faces verticais) |
| `Salt` | `#F4EAD3` | salinas pequenas no Sun Hollow |
| Água | `WaterColor #3FB6E8`, `WaterTransparency 0.35`, `WaterWaveSize 0.05`, `WaterWaveSpeed 4`, `WaterReflectance 0.05` | rio, lago da cascata, oásis, lago da praça |

Máximo de 3-5 materiais por vista (Safe 4, Forest 4 + água, Desert 4-5). Nada de `Brick`/`WoodPlanks` em encostas.

**Studs no Terrain** (decisão aberta do README §1): proposta da arte = sim, com **variantes próprias para Terrain** (`TerrainGrassStud`, `TerrainSandStud`…) feitas a partir das texturas de `assets/map-textures/` (2 × 2 studs por azulejo, DECISIONS 2026-10-27), `ColorMap` neutra para a cor do Terrain tingir. Só se aplicam no corte, porque os overrides do `MaterialService` são globais. A verificar no Studio antes do corte.

### 2.2 Props (peças `Plastic` + variante)

| Função | Safe Zone | Forest | Desert |
|---|---|---|---|
| Dominante | pedra `#8F9BB0`, banda `#7D889C` | copa `#2F9A3A` / `#47AA42` / `#267F32` (uma por árvore) | arenito `#D9733A`, estrato `#B9532E` |
| Secundária | remate `#F3F6FA`, cerca `#FFFFFF` | tronco `#6B3F22` / `#8A5A3B` | topo de mesa `#F6CF74`, areia `#F2BD63` |
| Madeira | `#8A5A3B` | ponte `#6B3F22` | palmeira `#8A5A3B` |
| Verde | relva alta `#6FD86B` (mais escura `#4FBF55`) | pinheiro `#196647`, musgo `#4D9A3A`, erva `#2E9E3E` / `#3DBA4A` | saguaro `#4F9C3F`, figueira `#5CB042`, fronde `#47AA42` |
| Pedra | `#A3AEC0` | rocha com musgo `#6E7A70` / `#5B665D` | rocha quente `#C9824F` |
| Flores | flor de cerejeira `#FF9CC8`, `#FF6F91` | `#FFD23F`, `#FF6F91` | flor de cacto `#FF9CC8` |
| **Acento exclusivo** | ouro `#FFC83D` (aros da fonte, coroa) | pirilampos `#FFE58A` (FX) | laranja de calor `#FFB347` (bandeiras, toldos do oásis) |
| Outros | — | cogumelo `#E5432F` + pé `#EFE2C6` (≤ 2 de altura; ver nota) | osso `#F4EAD3`, arbusto seco `#B8884A` |

- Leitura dos pets: os pets têm de contrastar com o chão (razão ≥ 3). Cogumelos decorativos ficam pequenos (≤ 2 de altura) e **fora das áreas de spawn** do `HoppingMushroom`; o mesmo para catos baixos nas áreas do `RunningCactus`. O Acorn Squirrel (castanho) contra `LeafyGrass` e o Sun Camel contra `Sand` testam-se no teste de cinzento (abaixo).
- Variantes por função (iguais em todas as cópias): estrutura (postes, travessas, molduras, caixotes) = `Studs`; massas, painéis e grandes superfícies = `Universal`; rochas = sem variante, `TopSurface = Inlet` só no topo. Peças < 0,5 = `Plastic` liso. `Neon` só em acentos finos e pads.

## 3. Props do LihFolk Asset Pack

Pack local: `C:\Users\duart\Projects\FreeAPet\LIH.FOLK.VAULT.V2.FULL\LihFolk Asset Pack\` (fora do Git). Envio com `scripts/opencloud-upload.ps1` (guia em `docs/agent-workflow/OPEN-CLOUD-UPLOAD.md`), **sempre como privado**. Nada do `Dataset/`. Nenhum ficheiro do pack entra no Git.

**Veredicto de estilo (vi as folhas `Models/Kits/_sheets/`):** os modelos do pack são low-poly lisos e facetados com cores cozidas, não são stud-style. Os materiais são PBR (o studify proíbe-os nas peças). Por isso o pack é **uma camada de acento** (≤ 10 % dos props por zona) e o grosso constrói-se em Parts com studs. Nada de árvores, cercas, muros, arcos nem escadas do pack: misturavam duas linguagens.

| Uso | Zona | Assets (caminho no pack) | Notas |
|---|---|---|---|
| **Céu do mapa todo** | todas | `Skies/clear_day_cumulus_007/` (`SkyBk/Dn/Ft/Lf/Rt/Up.png`) | Nuvens grandes e azul limpo, combina com o cartoon. O céu não traz o sol pintado (`celestial_bodies_shown = False`), por isso fica `CelestialBodiesShown = true` (sol do Roblox). Reserva: `Skies/clear_day_azure_004/`. 6 imagens para enviar. |
| Lanternas (levam a `PointLight` `V3WarmLamp`) | Safe (praça, portões das bases), Desert (oásis) | `Models/Kits/Props/Lantern_01.glb`, `Lantern_05.glb`, `Lantern_09.glb` | Penduradas em postes de Parts (o poste é stud, a lanterna é o acento). Escala para ~1,8 de altura. |
| Barris e caixotes | Safe (kiosques do jardim sul), Desert (acampamento do oásis) | `Models/Kits/Props/Barrel_01.glb`, `Barrel_04.glb`, `Crate_01.glb`, `Crate_05.glb` | Em grupos ímpares (1 grande, 2 médios), ≤ 8 por zona. |
| Placas de direção | Forest (bifurcações para as clareiras e a Rare Glade), Desert (entrada das mesas) | `Models/Kits/Props/Sign_01.glb`, `Sign_05.glb` | ≤ 6 no mapa. Sem texto colado; o símbolo da placa chega. |
| Rochas pequenas de preenchimento | Forest (bordas do caminho e do rio, nunca nas clareiras) | `Models/Kits/Nature/Rock_03.glb`, `Rock_05.glb`, `Rock_09.glb`, `Boulder_07.glb` | O topo verde e o cinzento combinam com `Rock #6E7A70`. ≤ 40. As rochas grandes e as falésias são Parts/Terrain. Não usar no Desert (cinzento a mais). |

Regras de importação (skill `lihfolk-assets`): GLB a 1 stud por unidade, `MeshPart.Color` branco (as cores vêm cozidas), `Anchored`, `CanCollide`/`CanQuery` off, `CollisionFidelity = Box`. **Clonar no Studio** cada asset enviado, sem reimportar, para as malhas se agruparem num só desenho. Os triângulos de cada um estão no catálogo (`Models/Kits/CATALOG.csv`, coluna `tris`): lanterna ~1,5-1,8k, barril 1,7k, caixote 1-1,1k, placa ~0,8k, rocha 0,2-0,4k. Por isso estes props pesam muito mais do que Parts: respeitar os limites da tabela.
Não usados: `Nature/PineTree_*` (cone liso, não é a receita de voxels), `Modular/*` (pedra cinzenta medieval), `Materials/*` (PBR), `Furniture`, `Weapons`, `Emblems`.

## 4. Iluminação (compatível com `ZoneMood`)

### 4.1 Global (no Studio, fixo; o `ZoneMood` não mexe)
`Lighting.LightingStyle = Soft`, `PrioritizeLightingQuality = false`, `Lighting.Technology` não se usa. Efeitos com os nomes que o `ZoneMood` procura: `FreeAPetAtmosphere`, `FreeAPetBloom`, `FreeAPetColor`, `FreeAPetSunRays` e um `Sky`. **Um só céu para o mapa todo** (os céus não se misturam; ver §3).
`ClockTime` igual nas 3 zonas (15.6) para o sol não saltar quando se muda de zona; o ambiente muda por cor.

### 4.2 `Map.FX.V3Presentation.LightingProfiles` (JSON, colar como está)
```json
{
 "safe": {
  "Lighting": {"ClockTime": 15.6, "GeographicLatitude": 25, "Brightness": 2.4, "Ambient": "#6E6E7D", "OutdoorAmbient": "#9696A0", "ColorShift_Top": "#FFF0D7", "ColorShift_Bottom": "#000000", "EnvironmentDiffuseScale": 0.3, "EnvironmentSpecularScale": 0, "GlobalShadows": true, "ShadowSoftness": 0.4, "ExposureCompensation": 0},
  "Atmosphere": {"Density": 0.25, "Offset": 0.1, "Color": "#C8E1FF", "Decay": "#78A0D2", "Glare": 0, "Haze": 0.8},
  "Bloom": {"Intensity": 0.5, "Size": 24, "Threshold": 1.3},
  "ColorCorrection": {"TintColor": "#FFFFFF", "Brightness": 0.02, "Saturation": 0.1, "Contrast": 0.08},
  "SunRays": {"Intensity": 0.04, "Spread": 0.6},
  "Sky": {"CelestialBodiesShown": true, "SunAngularSize": 14, "StarCount": 0}
 },
 "floresta": {
  "Lighting": {"ClockTime": 15.6, "GeographicLatitude": 25, "Brightness": 2.1, "Ambient": "#505A50", "OutdoorAmbient": "#80907C", "ColorShift_Top": "#F0FFDC", "ColorShift_Bottom": "#000000", "EnvironmentDiffuseScale": 0.25, "EnvironmentSpecularScale": 0, "GlobalShadows": true, "ShadowSoftness": 0.5, "ExposureCompensation": 0},
  "Atmosphere": {"Density": 0.36, "Offset": 0.15, "Color": "#C8DCC8", "Decay": "#6E826E", "Glare": 0, "Haze": 1.6},
  "Bloom": {"Intensity": 0.6, "Size": 28, "Threshold": 1.3},
  "ColorCorrection": {"TintColor": "#F2FFF4", "Brightness": 0, "Saturation": 0.05, "Contrast": 0.06},
  "SunRays": {"Intensity": 0.08, "Spread": 0.5},
  "Sky": {"CelestialBodiesShown": true, "SunAngularSize": 14, "StarCount": 0}
 },
 "deserto": {
  "Lighting": {"ClockTime": 15.6, "GeographicLatitude": 25, "Brightness": 2.8, "Ambient": "#786E64", "OutdoorAmbient": "#AA9682", "ColorShift_Top": "#FFDCAA", "ColorShift_Bottom": "#000000", "EnvironmentDiffuseScale": 0.3, "EnvironmentSpecularScale": 0, "GlobalShadows": true, "ShadowSoftness": 0.3, "ExposureCompensation": 0},
  "Atmosphere": {"Density": 0.3, "Offset": 0.25, "Color": "#FFE6C3", "Decay": "#D79B6E", "Glare": 0.35, "Haze": 2.0},
  "Bloom": {"Intensity": 0.6, "Size": 24, "Threshold": 1.25},
  "ColorCorrection": {"TintColor": "#FFF5E6", "Brightness": 0.03, "Saturation": 0.12, "Contrast": 0.1},
  "SunRays": {"Intensity": 0.06, "Spread": 0.6},
  "Sky": {"CelestialBodiesShown": true, "SunAngularSize": 16, "StarCount": 0}
 }
}
```
`Ambient` ≤ `OutdoorAmbient` em todos os canais (regra do Roblox). A transição de 3 s do `ZoneMood` cobre a troca; a mudança Forest→Desert faz-se dentro do canhão.

### 4.3 `MobileOverrides` (iguais para as 3 zonas: o `ZoneMood` aplica-os por grupo, não por zona)
```json
{
 "Lighting": {"EnvironmentDiffuseScale": 0, "EnvironmentSpecularScale": 0, "ShadowSoftness": 0.2},
 "Bloom": {"Intensity": 0.3, "Size": 16},
 "SunRays": {"Enabled": false}
}
```
Não pôr cores nem `Atmosphere` aqui (ficariam iguais nas 3 zonas).

### 4.4 Mood por zona (para quem afina)
| Zona | Sensação | Como se lê sem sombras (telemóvel abaixo de qualidade 4) |
|---|---|---|
| Safe | manhã clara de aldeia, acolhedora, nada escuro | relva lima, pedra periwinkle, ouro na fonte |
| Forest | fresca, verde, profundidade com névoa ao fundo e raios de sol | verdes mais escuros que a Safe, troncos castanhos, ciano da água |
| Desert | quente, brilhante, ar com calor ao fundo | areia, laranja de arenito, verde só nos catos e no oásis |
- Luzes locais: só `V3WarmLamp` (o `ZoneMood` liga as 4 mais próximas, sem sombras). Lanternas na praça e nas entradas das bases; 2-3 no oásis. Total ≤ 26.
- Testes: cinzento (`ColorCorrection.Saturation = -1`: caminho, pets e interativos separam-se do chão) e sem sombras (`GlobalShadows` off: as zonas continuam distintas).

## 5. Orçamento de desempenho (telemóvel primeiro)

Valores-guia do LihFolk (regras práticas, não limites do Roblox): telemóvel 300k-600k triângulos visíveis; 3k-10k instâncias por zona decorada; ≤ 12 luzes locais à vista, 0 com sombra; ≤ 40 emissores por zona.

| Zona | Peças (BaseParts) | Triângulos (peças + malhas) | Malhas do pack | Luzes `V3WarmLamp` | Emissores |
|---|---|---|---|---|---|
| Safe Zone | ≤ 6 000 (bases 5 × ≤ 600, praça e fonte ≤ 1 500, decoração ≤ 1 500) | ≤ 150k | ≤ 120 | ≤ 14 | ≤ 10 |
| Forest | ≤ 7 000 (árvores ~45 × ≤ 60 = 2 700) | ≤ 200k | ≤ 150 | ≤ 4 | ≤ 15 |
| Desert | ≤ 5 500 | ≤ 150k | ≤ 120 | ≤ 8 | ≤ 12 |
| Rebordo (todo) | ≤ 1 500 | ≤ 40k | 0 | 0 | 0 |
| **Mapa** | **≤ 20 000** | **≤ 540k** (cabe no telemóvel com o streaming) | | **≤ 26** | |

- `StreamingEnabled` ligado (Opportunistic, Improved, PauseOutsideLoadedArea). Heróis (fonte, Grande Árvore, Sun Arch, cascata) com `ModelStreamingMode = Persistent` para se verem de longe; o resto `Atomic` por modelo.
- Decoração: `Anchored`, `CanCollide`/`CanTouch`/`CanQuery` desligados, `CastShadow` off em peças pequenas, Neon e longe. Só troncos, rochas grandes, falésias, cercas e pontes colidem (em `Map.Collision`).
- Cada árvore ≤ 60 peças, cada prop pequeno ≤ 30. Clonar modelos acabados, não regenerar. Uma travessa longa em vez de cinco.
- Malhas do pack: clonar no Studio (não reimportar), `RenderFidelity = Automatic`, `CollisionFidelity = Box`. Texturas ≤ 512.
- Nenhuma peça de detalhe coplanar com o Terrain: pelo menos **0,1 stud** acima ou dentro (regra da equipa).
- Medir no Studio com a emulação de telemóvel e, se possível, num telemóvel real.

## 6. Checklist da Gaia antes de mostrar ao JB
- [ ] Fonte visível de todos os portões; Grande Árvore visível do portão da floresta; Sun Arch visível à saída do canhão.
- [ ] Clareiras Ø 56 livres (nada > 6 dentro, nenhuma copa por cima).
- [ ] Teste de cinzento e teste sem sombras feitos e com screenshots identificadas (zona, câmara, data).
- [ ] Pets de referência (3-9) e um R15 de 5 ao lado de cercas (3,5), portões, árvores (15-35) e herói, em screenshots.
- [ ] Orçamento da §5 medido por zona (peças, triângulos, luzes, emissores).
