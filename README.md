# Free a Pet!

Jogo Roblox de colecionar animais com roubo. O código vive nesta pasta e é sincronizado para o Roblox Studio com o **Rojo**. O mapa, os modelos e a UI são feitos no Studio.

## Estrutura

```
src/shared/   → ReplicatedStorage.Shared       (Config, Types: usados pelo servidor e cliente)
src/server/   → ServerScriptService.Server     (lógica do jogo, autoridade total)
src/client/   → StarterPlayerScripts.Client    (input e UI)
docs/         → DECISIONS.md, OPEN.md
```

Todos os números do jogo estão em `src/shared/Config/`. Os marcados `PLACEHOLDER` são para afinar a testar.

## Primeira vez

1. Instalar as ferramentas (dentro desta pasta):
   ```bash
   rokit install
   ```
## Trabalhar

O plugin do Rojo não carrega no Studio via Vinegar (Linux), por isso o código entra no Studio através da **MCP do Studio** (`robloxstudio-mcp`):

1. `scripts/build-sync.sh` compila `build/Shared.rbxm`, `build/Server.rbxm` e `build/Client.rbxm`.
2. O Claude apaga as versões antigas no Studio e importa estas com `import_rbxm`:
   - `Shared` → `ReplicatedStorage`
   - `Server` → `ServerScriptService`
   - `Client` → `StarterPlayer.StarterPlayerScripts`
3. Play: no Output aparecem `[FreeAPet] Server started` e `[FreeAPet] Client started`.

Os ficheiros em `src/` são a fonte da verdade: **não edites estes scripts dentro do Studio**, porque a próxima importação apaga essas alterações.

Verificar o código antes de guardar:
```bash
selene src
stylua --check src
```

## Gravação (M4)

- ProfileStore em `src/server/Vendor` (ver `docs/third_party`).
- No Studio a gravação vai para `PlayerData_Studio`, nunca para os dados do jogo publicado.
- Precisa de **Game Settings → Security → Enable Studio Access to API Services** ligado.

## GUI e ícones

- Estilo: `src/shared/UITheme.luau`. Ícones por chave: `src/shared/Config/UI.luau`.
- `assets/ui-upload/` tem exatamente os ícones do jogo, com o nome da chave (ex.: `cash.png`).
- Enviar para o Roblox (uma vez): Studio → **View → Asset Manager → Bulk Import** → escolher todos os ficheiros de `assets/ui-upload/`. Depois copiar cada ID para `Config/UI.luau`.
- Ver os ícones no Studio antes do upload: `scripts/studio-icon-preview.sh` (repetir depois de o Studio atualizar).

## Milestones

M0 Setup → M1 World → M2 Animals → M3 Core loop → M4 Persistence → M5 Exposure → M6 Research → M7 Trading → M8 UI, mobile, leaderboards.
