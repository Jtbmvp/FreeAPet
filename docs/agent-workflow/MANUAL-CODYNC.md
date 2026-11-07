# Ações manuais Codync

Os seis papéis foram alterados e lidos de volta com sucesso. Modelos, fallbacks, pastas e conectores foram preservados.

## Seleção de skills por agente
Na configuração de cada bot no Codync, abrir Skills/Extensions e manter ativas só as skills personalizadas seguintes:

| Bot | Skills Codync a manter ativas |
|---|---|
| Atlas | roblox-game-pipeline |
| Terra | studify |
| Pixel | roblox-vfx, studify |
| Nova | roblox-ui-maker |
| Coder | nenhuma das quatro RoClicks; usar as skills locais Luau/architecture/game-systems por tarefa |
| Sentinel | nenhuma das quatro RoClicks; usar roblox-testing local e references/qa.md por tarefa |

Estado observado em 2026-11-05: os seis bots tinham as quatro RoClicks ativas. A ferramenta update_bot não expõe o campo skills; não foi feita escrita direta na base de dados. As instruções já limitam as leituras ao necessário, mas os toggles acima ainda precisam de ajuste. Não desinstalar as skills: desativar apenas no bot que não as usa.

## Wrappers existentes
As quatro skills personalizadas em ~/.codync/skills já apontam para o RoClicks completo. save_skill recusou alterações por não terem sido criadas pelo Atlas. Não foram substituídas nem duplicadas. Se quiseres incorporar o contexto adicional pela UI, acrescentar ao fim de cada uma:

> Ler /home/jbernardo/Projetos/FreeAPet/docs/agent-workflow/WORKFLOW.md uma vez por tarefa. Resolver scripts, templates e referências na pasta original /home/jbernardo/Projetos/FreeAPet/tools/roclicks-skills/<nome-da-skill>/; não nesta pasta. Usar referências aprovadas FreeAPet; exemplos RoClicks não autorizam redesenhos. Carregar só recursos necessários.

Este acréscimo é opcional: os novos papéis já remetem para o workflow e para a fonte completa.

## Duplicados locais
.agents/skills e .claude/skills contêm as quatro skills completas, iguais ao RoClicks por SHA-256 (skill-copy-audit.json). Não são versões desatualizadas face à fonte instalada. Foram mantidas para não apagar configurações existentes. A pasta .agents é protegida e uma tentativa de mover a pasta falhou com EXDEV; nenhum original foi removido.
AGENTS.md e CLAUDE.md já encaminham para a fonte canónica. Uma futura atualização do RoClicks deve repetir a comparação de hashes antes de atualizar cópias. Não é obrigatório consolidar fisicamente para trabalhar.

## Dependências
Não foi instalada nenhuma. Consultar relatórios evidence/ antes de instalar: pode existir um ambiente virtual reutilizável. Gravação trailer usa screencapture/osascript macOS e precisa de adaptação Linux; não executar record.py neste sistema. Lune/luau-analyze ausentes do PATH padrão; geração score depende de ACE-Step/claude-music separado, sem instalação automática.
