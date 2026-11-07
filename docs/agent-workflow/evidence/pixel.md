# Evidência: Pixel, auditoria do roblox-vfx

2026-11-05. Só leitura nos ficheiros partilhados; testes com saída em `/tmp`, depois apagada. Studio não usado (nem inspeções). Nenhum efeito, asset, configuração ou mecânica alterado.

**Resultado:** a skill está completa e legível. Desenhar texturas, gerar flipbooks em Blender headless e empacotar o runtime funcionam. Faltam Pillow, o caminho de preview em Linux e o Blender MCP. O Studio MCP não foi testado, por regra.

## Skills acessíveis

| Fonte | Estado |
|---|---|
| `tools/roclicks-skills/roblox-vfx/` (commit `a8b66c1`) | 20 ficheiros legíveis: `SKILL.md`, `LESSONS.md`, 8 referências, 4 scripts, 4 templates, licenças |
| `SKILL.md` e `LESSONS.md` | Lidos. SHA-256 começam por `8bf171b0ca147b87` e `3e7d14aa5142ec45` |
| `~/.codync/skills/roblox-vfx/SKILL.md` | Encaminha para a fonte canónica |
| `.agents/skills/roblox-vfx`, `.claude/skills/roblox-vfx` | `diff -rq` igual à fonte, mas são **cópias**, não encaminhamentos: 0 symlinks e inodes diferentes |
| Árvore da skill antes e depois dos testes | Hash `330ee303ff8a132a` igual; `git status` limpo; 0 `__pycache__` |

## Dependências

| Dependência | Exigida por | Estado |
|---|---|---|
| Python 3 | Todos os scripts | OK, 3.14.8 |
| numpy | `vfxtex`, `clip_frames` | OK, 2.5.4 |
| **Pillow** | `vfxtex check` e `review`, `clip_frames` | **FALTA** |
| ffmpeg, ffprobe | `clip_frames` | OK, n9.0.2 |
| Blender | `vfxblender` | OK, 5.2.3 LTS, em headless, com numpy próprio |
| luau-compile | Não exigido pela skill; usei-o para validar | Fora do PATH; existe em `build/coder-studio-resume-2026-11-04/luau-ubuntu.zip` |

## Testes

| Comando | Resultado |
|---|---|
| `vfxtex` como biblioteca: `draw_flipbook`, `draw_texture` | PASS: PNG e JSON criados |
| `vfxtex.py check`, `review` | BLOCKED: `ModuleNotFoundError: No module named 'PIL'` |
| `vfxtex.py preview` | FAIL: `Roblox Studio's content/textures folder was not found` |
| `vfxtex.py clean-preview` | NOT RUN: procura as mesmas pastas, que não encontra |
| `bundle_runtime.py` | PASS: `.rbxmx` válido com Emit, Build, Capture e Shapes |
| `clip_frames.py` com vídeo sintético | BLOCKED: falta Pillow. O ffmpeg e o ffprobe funcionaram |
| `vfxblender.py` em `blender -b` | PASS: arc, ring, cone, swirl, shell, `export_glb`, `flipbook` (folha de 1024×1024) |
| `luau-compile --null` nos 4 templates | PASS: compilam; comportamento no Studio NOT RUN |

## Caminhos

- `_studio_texture_dirs()` só conhece macOS e `%LOCALAPPDATA%`; em Linux devolve `[]`.
- A pasta real no Vinegar existe: `~/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions/version-fee454b8e2094ba9/content/textures`. Contém a versão do Studio no caminho, por isso muda com as atualizações.
- A convenção da skill `<game>/vfx/<effect>/` ainda não existe no projeto. Não a criei.

## Ferramentas MCP

| Exigida | Servidor | Estado |
|---|---|---|
| `execute_luau`, `import_rbxm`, `capture_screenshot`, `get_runtime_logs`, `eval_client_runtime` | `robloxstudio` | Expostas (esquema carregado). Ligação NOT RUN: Studio não autorizado |
| `upload_image` | `roblox-studio` | **Indisponível:** `CONNECTION_CLOSED` nesta sessão |
| `execute_blender_code`, `look` | `blender` | **Indisponível:** `Could not connect to Blender`; não há processo Blender aberto |

## Limitações

1. **Pillow:** sem ele não há `check`, `review` nem análise de clips de referência. Não instalei. Precisa de autorização do Atlas.
2. **Preview:** o fluxo sem upload não funciona em Linux. Corrigir exige alterar o script ou copiar as texturas à mão para a pasta do Vinegar; o carregamento no Studio não foi testado.
3. **Upload:** o caminho que a skill indica (`upload_image`) está em baixo. `upload_asset` em `robloxstudio` existe, mas a skill diz que esse servidor não tem autenticação de upload; não testei.
4. **Blender:** o headless cobre a geração, mas `look` e `execute_blender_code` precisam do addon ligado.
5. **Regra da skill em conflito:** proíbe `set_script_source` para Luau, que as instruções do servidor `robloxstudio` permitem para substituir scripts inteiros. Sigo a skill.
6. **Cópias de skills:** `AGENTS.md` chama-lhes encaminhamentos, mas são cópias e podem divergir da fonte.
7. **Estilo:** `LESSONS.md` e os exemplos da skill não são decisões aprovadas do FreeAPet. Nenhum VFX aprovado por esta auditoria.

## Fecho

- **Alterado:** só este ficheiro, e a pasta `evidence/`, que não existia.
- **Testado:** tabelas acima.
- **Pendente:** decisões do Atlas sobre Pillow, preview em Linux e cópias de skills; Studio e addon Blender.
