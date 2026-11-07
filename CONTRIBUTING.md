# Colaborar no FreeAPet

Guia para colaboradores e para o Claude Code deles. O Claude deve ler também `AGENTS.md` e `docs/agent-workflow/WORKFLOW.md`.

## Começar
1. Aceita o convite do GitHub e clona: `git clone https://github.com/Jtbmvp/FreeAPet.git`
2. Trabalha a partir de `v3-integration`: `git switch v3-integration && git switch -c feat/<tema>`
3. Instala as ferramentas com `rokit install` e a proteção: `cp scripts/git-hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push`
4. Pede ao JB acesso à place do Studio (Team Create). Modelos e arte não estão no repositório.

## Regras
- Abre PR para `v3-integration`. O JB/Atlas revê e integra. Não faças push direto nem force-push.
- Combina antes de mexer: um responsável por ficheiro e **só um agente de cada vez no Studio**. Nunca interrompas um playtest alheio.
- Alterações de jogo pequenas e verificáveis. Aprovação visual é só do JB; QA técnica não é aprovação.
- Nunca faças commit de chaves, tokens ou cookies. O repositório é **público**.
- Só o Studio recebe assets: nada de zips, modelos pesados ou ficheiros acima de 50 MB no Git.

## LihFolk Vault
Podes retirar do vault o que for útil para o jogo, sem obrigação de o usar. Vem da fonte oficial (https://github.com/lihfolk-cy/v2-vault), não deste repositório, e a licença é a de lá:
- Código e ideias podem entrar no jogo. Neste repositório público, adapta em vez de colar módulos inteiros.
- Os assets do pack só podem ser carregados no Roblox como **privados** e nunca entram no Git.
- O Dataset é só para estudo, não entra no jogo.

## Skills
A fonte RoClicks (`tools/roclicks-skills/`) não vem no repositório. A revisão fixada está em `docs/agent-workflow/`; pede ao JB se precisares dela.
