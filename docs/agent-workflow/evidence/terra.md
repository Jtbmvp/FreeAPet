# Evidência Terra — auditoria studify + meshlab

Data: 2026-11-05. Só leitura. Sem Studio, sem instalações, sem assets gerados.
Ambiente: CachyOS, kernel 7.3.1, zsh, btrfs. Branch `feat/v3-systems`.
Fonte: `tools/roclicks-skills`, `a8b66c1` (`github.com/zriptic/roclicks-skills`), 0 alterações locais antes e depois.

## Resultado

| Item | Estado | Evidência |
|---|---|---|
| studify completo | PASS | 3 ficheiros lidos na íntegra; não existe `LESSONS.md` |
| meshlab: acesso | PASS | 27/27 ficheiros lidos por `sha256sum`; README, BRIEF, `run.luau`, `render.py` e ferramentas lidos (`bake_meshdata.luau` parcial); exemplo `Barrel.luau` lido |
| Sintaxe | PASS | Python 3/3 por `compile()`; Luau 20/20 sem erros de parse (`stylua --check`); 20/20 `require` relativos literais existem (sensível a maiúsculas); 0 ficheiros CRLF; 0 caminhos macOS/Windows |
| `render.py` no Blender 5.2.3 | PASS parcial | Ver "Teste Blender" |
| `pack_glb.py` no Blender 5.2.3 | PASS parcial | Opções e materiais presentes; exportação GLB NOT RUN |
| `run.luau` e ferramentas `.luau` | BLOCKED | Lune ausente |
| Galeria de referências online | PASS parcial | `/assets` 200 e âncora presente; as 142 imagens não foram verificadas |
| Studio, MaterialService, screenshots | NOT RUN | Terra não autorizada nesta reorganização |

## Caminhos e hashes

SHA-256, primeiros 12 caracteres:

- `tools/roclicks-skills/studify/SKILL.md` — `9aec10783f41`
- `tools/roclicks-skills/studify/references/INDEX.md` — `a0a32394396f`
- `tools/roclicks-skills/studify/references/style-notes.md` — `d3add18540d9`
- `tools/roclicks-skills/meshlab/README.md` — `fc24b3ab5961`
- `tools/roclicks-skills/meshlab/BRIEF.md` — `b862b75955da`
- `tools/roclicks-skills/meshlab/run.luau` — `e3636276279d`
- `tools/roclicks-skills/meshlab/render.py` — `138928714d10`
- Ferramentas: `bake_meshdata`, `count_mesh`, `export_parts`, `probe_shading` (`.luau`); `pack_glb`, `stud_normal` (`.py`)
- Exemplos: `Barrel`, `Bollard`, `Cabin`, `Cone`, `Crate`, `Forklift`, `Pallet`, `TreeBlob`
- Entradas de skill: `~/.codync/skills/studify/SKILL.md` encaminha para a fonte canónica; `.claude/skills/studify` e `.agents/skills/studify` são pastas idênticas à fonte (`diff -rq` vazio)

## Dependências

| Dependência | Encontrado | Nota |
|---|---|---|
| Lune | **Ausente** | Sem binário no PATH, `~/.rokit`, `~/.aftman` ou pacman; não consta de `rokit.toml` |
| Blender | 5.2.3 LTS em `/usr/bin/blender` (pacman); Flatpak 5.2 também instalado | README pede 4.x |
| Python | 3.14.8 | `zlib`, `struct`, `os`, `math` OK; `bpy` só dentro do Blender (esperado) |
| rokit | 1.2.0 | Projeto fixa só rojo 7.7.1, selene 0.32.0, stylua 2.6.0 |
| Pillow | Ausente | studify usa PIL na análise de referências; alternativas presentes: `magick`, `oiiotool`, `numpy` 2.5.4 |
| Vinegar | Flatpak 1.9.4 | Não testado; `vinegar` não está no PATH |

## Teste Blender

Comando: `blender -b --factory-startup --disable-autoexec -noaudio --python-exit-code 1 --python-expr <sonda> -- /nonexistent/never.obj /tmp/<inexistente>/never.png hero 1.4`

A sonda executa em memória o código real de `render.py`, com 3 substituições: `obj_import` → cubo primitivo, resolução 1024 → 16, `write_still=True` → `False`.

Resultado (saída 0, sem `DISPLAY` nem `WAYLAND_DISPLAY`):
- Motor `BLENDER_EEVEE`, vista `Standard`, textura `stud_normal.png` 128×128 carregada, render sem exceção.
- `obj_import` tem `filepath`, `forward_axis` e `up_axis`.
- glTF tem as opções usadas; `export_vertex_color` aceita `ACTIVE`.
- Aviso: `Material.use_nodes` e `World.use_nodes` serão removidos no Blender 6.0.
- Nada escrito: pasta de destino inexistente, sem `meshlab/out`, sem ficheiros novos em `~/.config/blender`.

Não provado: importação de um OBJ real, exportação GLB e fidelidade visual em relação ao Studio. Não foram inspecionados píxeis.

## Limitações

1. **Fluxo meshlab bloqueado até haver Lune.** Instalar exige autorização e altera `rokit.toml` ou o ambiente global. Depois disso, os primeiros testes sem escrita são `lune run meshlab/tools/count_mesh ""` e `lune run meshlab/tools/probe_shading Barrel`.
2. **Executar a partir de `tools/roclicks-skills/`.** `meshlab/out` e `meshlab/models` são relativos à pasta atual. `run.luau` e `export_parts` escrevem ficheiros; `stud_normal.py` sobrescreve `textures/stud_normal.png`.
3. **Ficheiros referidos mas ausentes:** `tools/bake_pbr.py`, `tools/rig_skinned.py` e as ferramentas SDF para criaturas.
4. **A doutrina RoClicks não é aprovação FreeAPet:**
   - studify proíbe MeshParts e exige Plastic; `docs/DECISIONS.md:52-53` regista `Map.Art` em MeshParts e água em Glass.
   - `roblox-game-pipeline/references/meshlab.md` diz "meshlab builds everything"; `WORKFLOW.md:4` anula esse default.
   - A paleta pastel e a galeria são exemplos de outros jogos.
5. **Referência visual do mundo por confirmar.** Não encontrei em `docs/DECISIONS.md` a aprovação de uma referência do mapa v3. `Free a Pet Map v3 (offline).html` e `design/terra` existem, mas não foram inspecionados nem tratados como aprovados.
6. **MaterialVariants por confirmar.** Não há `MaterialVariant` em `src/`, e o mapa vive no Studio. Os variantes só se confirmam com inspeção no Studio.
7. **Nome de ferramenta:** studify refere `screen_capture`; o MCP local expõe `capture_screenshot`. O servidor `roblox-studio` falhou a ligação nesta sessão (`CONNECTION_CLOSED`); as ferramentas `robloxstudio` não foram usadas.
8. **Risco Git:** `tools/roclicks-skills/` tem `.git` próprio e, tal como `.claude/skills/studify/` e `.agents/skills/studify/`, não está seguido nem ignorado no repositório. Um `git add .` criaria um repositório embutido. `AGENTS.md` chama "encaminhamentos" às entradas de skill, mas estas duas são cópias reais e podem divergir da fonte.

## Encerramento

- **Alterado:** só este relatório.
- **Testado:** tabelas acima.
- **Pendente:** decisão sobre Lune; referência visual aprovada do mundo; inspeção de MaterialService quando Atlas atribuir o Studio.
- **Ficheiros modificados:** `docs/agent-workflow/evidence/terra.md`.
