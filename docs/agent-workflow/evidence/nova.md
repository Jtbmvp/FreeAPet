# Evidência Nova — auditoria roblox-ui-maker (2026-11-05)

Âmbito: validar acesso e bloqueios Linux, sem instalar nem alterar o jogo. Sem chamadas ao Studio nesta auditoria. Execução dos scripts só numa cópia em `/tmp`, já apagada.

## Veredicto
Acesso completo: PASS. Pipeline Linux: BLOCKED em `gen.py` (sem Pillow) e na análise Luau (sem `luau-analyze`). Importação e verificação no Studio: NOT RUN (sem autorização nesta fase).

## Acesso e fonte
- Fonte canónica: `tools/roclicks-skills/roblox-ui-maker/`, commit `a8b66c1`, árvore limpa, 53 ficheiros.
- `diff -rq` da fonte contra `.agents/skills/roblox-ui-maker` e `.claude/skills/roblox-ui-maker`: sem diferenças.
- Wrapper `~/.codync/skills/roblox-ui-maker/SKILL.md` aponta para a fonte canónica.
- Skills do meu papel/Codync acessíveis: `roblox-ui-maker`, `studify`, `roblox-vfx`, `roblox-game-pipeline`. Li apenas a `roblox-ui-maker`.

| Lido integralmente | sha256 (16) |
|---|---|
| SKILL.md | 207cd05140f1af49 |
| LESSONS.md | 69be43cd992e40a6 |
| STYLE.md | ebbd47987bb367bb |
| PATTERNS.md | 92eadeb74ae90e81 |
| PIPELINE.md | 6b8211d47f3f129a |
| REVIEW_LOOP.md | 2bf054b69d5ea8de |
| VERIFY.md | 020a1991572712e4 |
| ROBLOX_FACTS.md | 8d5fc6b1bf180c1f |
| UI_RESOURCES.md | 0aae026e14f49fe7 |

Scripts e templates: lidos em parte e analisados com `grep`; `cdp.mjs` e `mockshot.mjs` lidos por inteiro. Sem chamadas de rede escondidas nos passos principais; `fit_text.py` e `calibrate_rows.py` lançam subprocessos (`exec`, `shell=True`), por isso rever antes de usar.

## Ambiente
CachyOS, Linux 7.3.1. Python 3.14.8 com numpy. Node 26.12.1 (cumpre o mínimo 22; `fetch` e `WebSocket` globais presentes). `file`, `curl`, `ffmpeg`, `magick` (WEBP leitura/escrita), `rojo`, `selene`, `stylua` e `rokit` presentes. Vinegar e Sober em Flatpak. `pgrep` não mostrou `RobloxStudioBeta` durante a auditoria.

## Resultados (cópia em /tmp, com stud de teste)
| Passo | Estado | Resultado |
|---|---|---|
| `python3 -I -B build.py` | PASS | 8 páginas + index |
| Pré-visualização `http.server` em 127.0.0.1 | PASS | servida para os passos seguintes |
| Chromium headless a 2x | PASS | PNG 3840x2160; fontes web carregadas; ícones ausentes, como esperado neste teste |
| `export.mjs hud` sem `CHROME` | FAIL | caminho macOS por omissão |
| `CHROME=<playwright> export.mjs hud` | PASS | `hud.json` + 1 raster; aviso de 7 imagens em falta |
| `read_reference.py`, `copy_icons.py`, `gen.py` | BLOCKED | `ModuleNotFoundError: PIL` |
| `mock.py` | BLOCKED | falta `Data_Manifest.luau`, gerado pelo `gen.py` |
| `mockshot.mjs`, `mockdiff.py`, `scripts/remake/*` com PIL | NOT RUN | dependem de PIL/`gen.py` |
| `ledger.py`, `assets.py` | BLOCKED | faltam os ficheiros gerados a montante |
| `luau_to_rbxmx.py`, `bundle.py` | PASS | XML válido; `GameUIBuild.rbxmx` com 15 itens |
| `selene templates/luau` | PASS com ressalva | 0 erros de parse, 74 avisos, 3 erros `assert` com 1 argumento em `NumberFormat.luau:95-97` |
| `luau-analyze` | BLOCKED | comando inexistente |
| `node --check` e `ast.parse` em todos os scripts | PASS | sem erros |
| `https://fonts.googleapis.com`, `https://ui-resources.com` | PASS | HTTP 200 |

Integridade após os testes: `git status` da fonte canónica vazio, 0 `__pycache__`, sem portas 8870/9333/9334 abertas.

## Pressupostos macOS e bloqueios Linux
1. Chrome: `cdp.mjs:16` e `remake/fit_text.py:22` usam `/Applications/...` e `REVIEW_LOOP.md:12` repete-o. Não há `google-chrome` nem `chromium` no PATH. Solução sem instalar: `CHROME=~/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome` (caminho frágil, depende da versão).
2. Pillow: falta no Python do sistema. Bloqueia `gen.py`, `read_reference.py`, `copy_icons.py`, `mockdiff.py` e a maioria de `remake/`. `mockshot.mjs` chama `python3` do PATH, por isso um venv tem de estar ativo. Decisão de instalação fica com o Chefe/Atlas.
3. `luau-analyze`: falta. O checklist de importação não fecha sem ele; o Selene não substitui a análise. Decisão de instalação pendente.
4. `sips` não existe (`SKILL.md:61`, `LESSONS.md:26`, `STYLE.md:9`, `UI_RESOURCES.md:40`). Alternativa disponível: `magick`.
5. `mcp__Claude_Browser__*` e `preview_start`/`.claude/launch.json` são do Claude desktop e não estão disponíveis aqui. Alternativa para revisão do Chefe: PNG headless a 2x ou galeria enviada pelo Codync. Limite: o `?check` no painel fica substituído por avaliação com Chromium headless.
6. Fontes: Montserrat e Fredoka não estão instaladas localmente. `build.py` e `mock.py` dependem de Google Fonts online.
7. `mcp__Roblox_Studio__*` chama-se aqui `mcp__roblox-studio__*` e estava desligado nesta sessão (`CONNECTION_CLOSED`); `upload_image` indisponível até reconectar.
8. `ledger.py` lê stdin sempre que não é TTY e fica pendurado em execução automática: usar `</dev/null` quando não há JSON.
9. `cdp.mjs` deixa diretórios `cdp-*` em `/tmp`. Limpeza manual; não bloqueia.

## NOT RUN (exige janela Studio atribuída)
`import_rbxm` com caminhos em Vinegar/Flatpak; `Builder.build()`/`fit()`; `PropertySweep`; harness em edit mode; cliques em playtest. Por confirmar em Vinegar, porque a skill os mediu noutro ambiente: inset de 58 px, captura "2x retina", capturas magenta/sem GUI e 15 fps sem foco.

## Conflitos com o FreeAPet (lições da skill não são decisões aprovadas)
- Fluxo: a skill e `roles/nova.md` exigem HTML e aprovação antes de importar; `WORKFLOW.md` diz que nenhum design novo foi aprovado. O pacote Luau do Claude Design (`design/hud-user-2026-11-03/claude-design-2026-11-05/`) não segue este fluxo nem está aprovado.
- Alvo: `WORKFLOW.md` e `roles/nova.md` pedem desktop + telemóvel; o pedido anterior do HUD era só telemóvel horizontal.
- Tipografia: a skill prefere Montserrat 800; o HTML do Chefe usa Montserrat 900 e Fredoka 700. Os documentos do Roblox indicam que não se podem importar fontes e a Creator Store não tem Fredoka.
- Stud: a skill manda usar textura de ui-resources; o design do Chefe traz a sua própria `stud.png`.
- Ícones: a skill exige um único pack; o projeto tem "Stylized Game Essentials", ícones próprios, "Free Icon Pack 3.0.1" e 25 PNG no pacote Claude Design. Só encontrei licença em `assets/ui-icons/License_and_Info/`.
- Robux: as regras de glifo da skill não se aplicam enquanto vigorar SEM Robux.
- Estrutura: a skill usa `ui/` + `roblox/ui/`, `StarterGui` e `ServerStorage.<Gui>Build`; o projeto usa `src/` com Rojo e ScreenGui criado em runtime. Definir com Coder antes da primeira importação.
- Entrega: a skill proíbe `set_script_source`/`edit_script_lines` e manda usar `.rbxmx` + `import_rbxm`; as entregas anteriores da Nova usavam lotes MCP.

## Trabalho anterior a esta ordem
Antes desta auditoria, ao abrigo do pedido de HUD do Atlas:
- Leituras no Studio via `execute_luau` e simulador, sem escritas.
- Upload de 2 imagens: stud `rbxassetid://139585613893189`, hex `rbxassetid://73084826815812`. Ainda sem referência no código.
- `pip install` de fonttools, brotli e pillow em `/tmp/nova-playwright`; esse venv já não existe.
- Pastas não seguidas: `design/hud-user-2026-11-03/claude-design-2026-11-05/` e `implementation/font-conversion/`.
- Nada em `src`. Rebuild do HUD em pausa.

## Alterado / Testado / Pendente / Ficheiros
- **Alterado:** apenas este relatório.
- **Testado:** acesso, paridade das cópias, ferramentas Linux e pipeline até `export.mjs`/`bundle.py`, conforme a tabela.
- **Pendente:** decidir Pillow e `luau-analyze`; referência aprovada do HUD e destino do pacote Claude Design; desktop + telemóvel ou só telemóvel; janela Studio para confirmar os factos acima.
- **Ficheiros modificados:** `docs/agent-workflow/evidence/nova.md`.
