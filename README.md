# Free a Pet!

> Nome provisório: o título do jogo ainda não está decidido.

Jogo Roblox de colecionar pets e **batalhar com eles**. Apanhas pets na natureza, crias uma equipa de até 3 e lutas em batalhas por turnos. Há também base, investigação, trocas, índice e tabelas de líderes. O roubo de pets saiu do jogo.

O código vive nesta pasta. Entra no Roblox Studio através da **MCP do Studio**; já não usamos o plugin do Rojo. Mapa, modelos e assets vivem no Studio e no Roblox.

## Estrutura

```
src/shared/   → ReplicatedStorage.Shared       (Config, tipos: servidor e cliente)
src/server/   → ServerScriptService.Server     (lógica do jogo, autoridade total)
src/client/   → StarterPlayerScripts.Client    (input e UI)
tests/        → testes
docs/         → decisões, batalhas, escala, workflow dos agentes
scripts/      → sincronização, publicação limpa, exportações e texturas
```

Os números do jogo estão em `src/shared/Config/`.

## Primeira vez

1. Instalar as ferramentas com `rokit install`. O `rojo` fica só como compilador local dos `.rbxm`; não é preciso o plugin nem `rojo serve`.
2. Ligar a MCP do Studio (`robloxstudio-mcp`) ao teu agente e abrir a place.

## Trabalhar

1. `scripts/build-sync.sh` compila `build/Shared.rbxm`, `build/Server.rbxm` e `build/Client.rbxm`.
2. O agente substitui as versões no Studio com `import_rbxm`:
   - `Shared` → `ReplicatedStorage`
   - `Server` → `ServerScriptService`
   - `Client` → `StarterPlayer.StarterPlayerScripts`
3. Só um agente de cada vez no Studio, e nunca interrompas um playtest de outra pessoa.

`src/` é a fonte da verdade: **não edites estes scripts dentro do Studio**, porque a próxima sincronização apaga essas alterações.

Antes de guardar:
```bash
selene src
stylua --check src
```

## Gravação

- ProfileStore em `src/server/Vendor` (ver `docs/third_party`).
- No Studio a gravação vai para `PlayerData_Studio`, nunca para os dados do jogo publicado.
- Precisa de **Game Settings → Security → Enable Studio Access to API Services** ligado.

## Documentação

Decisões: `docs/DECISIONS.md` (a mais recente prevalece). Batalhas: `docs/BATTLES.md`. Regras de equipa e agentes: `AGENTS.md`, `CONTRIBUTING.md` e `docs/agent-workflow/WORKFLOW.md`.
