# Spirit Wolf

Modelo Meshy com rig (48 ossos, `SmartRigArmature`) animado por código. O rig, os nomes dos ossos, a pose de repouso e os pesos da malha **não foram alterados**: só foram acrescentadas animações.

## Ficheiros

| Caminho | O que é |
|---|---|
| `source/SpiritWolf_meshy_rigged.glb` | Modelo original, tal como foi entregue |
| `export/SpiritWolf.glb` | Modelo + 6 clips (para o site e para three.js) |
| `export/SpiritWolf.fbx` | Modelo + 6 takes, texturas embebidas (para o Roblox Studio) |
| `export/SpiritWolf_clips.json` | fps, durações, loop, marcadores, família de VFX e mapa de ossos |
| `scripts/wolf_lib.py` | Mapa do rig, FK/IK das patas, bake para ações do Blender, renders |
| `scripts/wolf_clips.py` | As 6 animações, uma função por clip |
| `scripts/build.py` | Bake + validação + exportação |

## Clips (30 fps)

| Clip | Duração | Loop | Marcadores | VFX |
|---|---|---|---|---|
| `Idle` | 4.0 s | sim | | |
| `Walk` | 1.0 s | sim | `step_HL` 0.00, `step_FL` 0.22, `step_HR` 0.50, `step_FR` 0.72 | |
| `Attack_SpiritPounce` | 1.6 s | não | `release` 0.42, `impact` 0.64 | corte: rastos de garras nas patas dianteiras, estilhaços na aterragem |
| `Attack_CrystalHowl` | 2.4 s | não | `release` 0.86, `impact` 1.00 | pulso: brilho nas hastes durante a carga, onda de choque radial |
| `Attack_RuneSlam` | 1.9 s | não | `release` 0.62, `impact` 0.74 | géiser: runa do ombro acende, espigões de cristal à frente |
| `Fainted` | 2.6 s | não | `ground` 1.46 | fica na pose final |

Todos os clips são no lugar (a raiz volta à origem; o Pounce avança cerca de 0.5 m e regressa). Não há canais de escala: os ossos do Roblox não escalam.

## Reconstruir

```bash
python design/pets/spirit-wolf/scripts/build.py            # bake + validação + exportação
python design/pets/spirit-wolf/scripts/build.py check      # só bake + validação
python design/pets/spirit-wolf/scripts/build.py strips DIR # tiras de frames por clip
```

Corre com o Python do Blender (`blender -b -P build.py -- export`) ou com o módulo `bpy` (`pip install bpy`). Foi construído com `bpy` 5.3.

A validação imprime, por clip, a altura mínima da malha em todos os frames. Estado atual: nenhum clip desce mais de 2 cm abaixo do chão.

## Mapa de ossos

| Parte | Ossos |
|---|---|
| Raiz / bacia | `Bone_000`, `Bone_001` |
| Coluna / peito | `Bone_013`, `Bone_012` (e `Bone_019`, `Bone_018` da juba) |
| Cabeça / focinho | `Bone_027`, `Bone_025`, `Bone_024` |
| Hastes | esquerda `Bone_023`, `Bone_022`; direita `Bone_021`, `Bone_020` |
| Cauda | `Bone_017` → `Bone_016` → `Bone_015` → `Bone_014` |
| Pata dianteira esquerda | `Bone_047…043` e `Bone_037…033` |
| Pata dianteira direita | `Bone_042…038` e `Bone_032…028` |
| Pata traseira esquerda | `Bone_011…007` |
| Pata traseira direita | `Bone_006…002` |

Notas do rig:

- As patas dianteiras têm **duas cadeias sobrepostas**, ambas com pesos. As animações movem as duas com a mesma transformação.
- As hastes são filhas do osso do peito, não da cabeça. As animações fazem-nas acompanhar a cabeça (por isso têm canal de translação).
- O focinho não tem maxilar separado: a boca não abre.

## Importar no Roblox Studio

Importar `export/SpiritWolf.fbx` com o 3D Importer (rig e animações). Os nomes dos takes são os nomes dos clips. A integração no jogo (dados Luau, `PetAnimator`) não foi feita.
