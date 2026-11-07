# Recursos e dependências

Fonte instalada: tools/roclicks-skills, commit a8b66c1bb9cad59cc7c188a0688e80a0637a9f55. Inventário de 138 ficheiros com SHA-256: roclicks-manifest.json. Sem consulta a uma versão remota nem atualização automática. Não há LESSONS.md nas skills pipeline, studify, game-score ou trailer; só em UI e VFX.

| Responsável / recurso | Ler por tarefa | Ferramentas |
|---|---|---|
| Atlas / pipeline | SKILL, rules/gotchas antes do Studio, referência da fase e templates quando necessários | MCP Studio, ferramentas de cada especialista; companions opcionais não são instalados automaticamente |
| Terra / studify | SKILL, references/style-notes e INDEX, 3–6 imagens pertinentes e referências aprovadas do projeto | Studio e captura visual; variantes MaterialService existentes, escala em studs |
| Pixel / VFX | SKILL, LESSONS, design/craft; textures/motion/mesh/camera/flipbooks conforme efeito | scripts/vfxtex.py, vfxblender.py, clip_frames.py, bundle_runtime.py; templates Emit/Build/Capture/Shapes; Python+numpy, Pillow para revisão, ffmpeg e Blender quando usados |
| Nova / UI | SKILL+LESSONS; STYLE, PATTERNS, PIPELINE, REVIEW_LOOP, VERIFY, ROBLOX_FACTS, UI_RESOURCES conforme etapa | scripts de medição/export/gen/ledger/assets/bundle/mock/check_copies; styles e templates/examples + luau/client completos; Python+Pillow+numpy, Node>=22, Chrome/CDP, luau-analyze, Studio; icon pack licenciado e texturas fornecidas pelo projeto |
| Pixel/Terra / meshlab | README+BRIEF; Shapes/Props e exemplos antes de modelar | Lune runner/run.luau, EditableMeshShim, Organic/Voxel, Blender render.py+stud_normal.png, bake/count/export/pack_glb; StudioBuild e MeshDataLoader na integração futura |
| Sob demanda / score | SKILL e cue sheet | ACE-Step/claude-music separado, ffmpeg, credenciais upload apenas quando autorizado; não há scripts próprios nesta skill |
| Sob demanda / trailer | SKILL; recording/editing/luau-api/specs/shot-list/worked example; shots.template.json | build_kit, CameraRig, TrailerDriver, record, edit, qa, check_luau; gravação macOS não funciona diretamente Linux; ffmpeg/Pillow e adaptação de fontes/captura |

## Linux
Node 26.12.1, Python 3.14, numpy, Blender 5.2.3, ffmpeg e ffprobe encontrados. Pillow, Lune e luau-analyze ausentes do ambiente padrão. Não equivale a inexistência de executáveis em arquivos/ambientes privados; ver evidências dos especialistas.
Chrome padrão upstream aponta para /Applications. tools/agent-workflow/run-ui-linux.sh seleciona Chromium existente na cache Playwright e exporta CHROME, sem instalar nada; o comando roda no diretório atual. Não muda scripts RoClicks.
vfxtex preview só reconhece pastas macOS/Windows: integração futura deve descobrir content/textures da versão ativa do Vinegar, em vez de pressupor LOCALAPPDATA. Não copiar texturas nesta reorganização.
Modelos Lune/Blender e material variants precisam de teste completo antes de prometer produção. Ter Blender no PATH não prova compatibilidade de todas as APIs do toolkit.

## Confirmações dos especialistas
Pixel: 20/20 ficheiros VFX legíveis, geração PNG/flipbook e bundle PASS, quatro templates compilam; Blender headless gera formas, GLB e flipbook. Check/review/clip_frames bloqueados por Pillow. Preview falha no Linux; upload_image CONNECTION_CLOSED na sua sessão; addon Blender indisponível. Ver evidence/pixel.md.
Terra: studify integral e 27/27 ficheiros meshlab acessíveis; sintaxe Python 3/3 e parse Luau 20/20 PASS. Teste parcial render.py Blender 5.2.3 PASS, sem provar OBJ/GLB real nem fidelidade visual. Referências a bake_pbr.py, rig_skinned.py e SDF não fornecidas. Não aplicar regras Plastic/MeshParts upstream aos materiais já aprovados FreeAPet. Referência do mapa v3 e MaterialVariants ficam por confirmar numa tarefa de mundo futura; não bloqueiam esta reorganização. Ver evidence/terra.md.

## Repositório local
O checkout tools/roclicks-skills tem .git próprio; está agora ignorado pelo Git principal para evitar gitlink acidental. Nada apagado. A revisão fixa e hashes estão nesta pasta para preservar proveniência. Uma máquina nova precisa de obter separadamente o checkout zriptic/roclicks-skills nessa revisão; esta reorganização não instalou nem atualizou o upstream.
