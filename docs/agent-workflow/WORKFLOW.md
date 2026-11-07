# Workflow FreeAPet

## Âmbito e decisões
Reorganização autorizada em 2026-11-05: ambiente e agentes, sem novas funcionalidades nem alteração de mecânicas. Nenhum design novo foi aprovado. Instruções desta tarefa prevalecem sobre defaults de exemplos RoClicks (meshlab obrigatório, estilo automático, proibições específicas de outros jogos).

## Execução
1. Atlas recebe objetivo e encaminha em até 5 linhas: responsável, resultado, ficheiros, critério e dependências. Não elaborar um plano de jogo para uma tarefa de manutenção.
2. Responsável verifica Git, preserva alterações alheias e lê só a skill necessária. Usar fonte canónica completa; LESSONS.md obrigatório quando existe. Não reler ficheiros inalterados na mesma tarefa; guardar caminho+hash em vez de transcrições extensas.
3. Um dono por ficheiro. Mudanças de contrato entre UI/gameplay/arte exigem passagem entre os responsáveis; nunca editar simultaneamente o mesmo ficheiro. Um agente de cada vez no Studio, incluindo inspeções: Atlas atribui dono, place/studio ID, operação e liberta ao terminar. Durante esta reorganização só Coder recebe a inspeção Studio de leitura.
4. Executar uma alteração pequena e verificável, reutilizando sistemas e assets funcionais. Não instalar dependências desconhecidas nem apagar código, assets, configurações ou vaults. Backup antes de substituir configuração.
5. Sentinel valida evidência, distinguindo PASS, FAIL, BLOCKED e NOT RUN. QA técnica não equivale a aprovação visual.
6. Encerrar: **Alterado / Testado (com evidência) / Pendente / Ficheiros modificados**. Só abrir nova tarefa quando a anterior tiver handoff claro.

## Arte e interfaces
Referências aprovadas do FreeAPet são a fonte de estilo; exemplos e lições de outros jogos não são aprovações deste. Registar referência e estado de aprovação no handoff. Sem referência aprovada, pedir uma antes de desenhar. Nova possui look/layout, Pixel VFX e direção de pets, Terra ambiente. Coder integra dados/comportamento sem redesenhar UI.
Medir escala em studs, proporções, pivots, iluminação e composição. Interfaces compactas com verificação desktop e telefone. Capturas Studio identificadas por cenário/viewport; sem acesso visual pedir screenshot ao Chefe. Nunca declarar visual aprovado sem confirmação dele. Sem mudanças nesta reorganização, não é necessária aprovação visual de assets novos.

## Skills e contexto
Atlas: pipeline. Terra: studify. Pixel: vfx + studify. Nova: ui-maker. Coder: luau/architecture/game-systems conforme tarefa. Sentinel: testing + pipeline/references/qa.md. roblox-game-score e roblox-trailer ficam disponíveis sob demanda; meshlab é toolkit, sem SKILL.md. Não carregar tudo.
Codync reutiliza wrappers personalizados em ~/.codync/skills; Codex e Claude têm cópias completas separadas em .agents/skills e .claude/skills, verificadas por hash e preservadas. Não assumir partilha automática entre motores. A pasta .agents é protegida nesta sessão: a consolidação física fica manual/opcional. Carregar recursos relativos sempre a tools/roclicks-skills/<skill>, não à pasta do wrapper.

## Persistência
Decisões curtas no docs/DECISIONS.md, handoffs/evidências nesta pasta e issues/PRs GitHub quando pedidos. Markdown local pode ser aberto no Obsidian; pode e deve retirar-se do vault LIH.FOLK.VAULT o que for útil para o jogo, sem obrigação e dentro da licença (nada de o redistribuir no repositório público; assets só privados no Roblox; Dataset só para estudo); não escrever nele por iniciativa. O repositório é público: publicar só com `scripts/publish-clean.sh`, nunca `feat/v3-systems`. Nunca guardar chaves/tokens em relatórios.

## Estado e restauro
Backup: backups/agents-reorganization-20261105-143229/ (patch binário, ficheiros alterados/não seguidos, skills Codync e configuração anterior dos seis bots). Não restaurar por cima de trabalho posterior. Para reverter papéis usar team-before.json via update_bot; para skills comparar e restaurar apenas os caminhos reorganizados. Não usar reset --hard.
