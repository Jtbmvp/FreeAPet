# Free a Pet!

> Nome provisório: o título do jogo ainda não está decidido.

Jogo Roblox de colecionar animais com roubo. O código vive nesta pasta e é sincronizado para o Roblox Studio com o **Rojo**. O mapa, os modelos e a UI são feitos no Studio.

## Estrutura

```
src/shared/   → ReplicatedStorage.Shared       (Config, Types: usados pelo servidor e cliente)
src/server/   → ServerScriptService.Server     (lógica do jogo, autoridade total)
src/client/   → StarterPlayerScripts.Client    (input e UI)
docs/         → DECISIONS.md, OPEN.md, PROTOTYPE-STATUS.md, BATTLES.md, SCALE.md, ASSET-LIST.md…
design/       → mapa V2 e pets exportados (map-v2/, pets/)
scripts/      → build-sync, exportação de pets/animações, texturas
```

Todos os números do jogo estão em `src/shared/Config/`. Os marcados `PLACEHOLDER` são para afinar a testar.

## Primeira vez

1. Instalar as ferramentas (dentro desta pasta):
   ```bash
   rokit install
   ```
2. No Studio, instalar o plugin **Rojo 7.7.1** (a mesma versão do `rokit.toml`). Uma versão antiga do plugin (ex.: 7.2.1) desliga-se com o erro "Can't parse JSON".
   - No Vinegar (Linux), o ficheiro `Rojo.rbxm` da [release 7.7.1](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.1) vai para:
     `~/.var/app/org.vinegarhq.Vinegar/data/vinegar/prefixes/studio/drive_c/users/<utilizador>/AppData/Local/Roblox/Plugins/`
   - Fechar e voltar a abrir o Studio.

## Trabalhar

O código entra no Studio pelo **plugin do Rojo** (confirmado a funcionar no Vinegar com o Rojo 7.7.1, 1 nov 2026):

1. Na pasta do projeto:
   ```bash
   rojo serve
   ```
   O servidor fica em `localhost:34872`.
2. No Studio: **Plugins → Rojo → Connect** (`localhost:34872`).
3. Play: no Output aparecem `[FreeAPet] Server started` e `[FreeAPet] Client started`.

### Alternativa: MCP do Studio

Se o plugin do Rojo não ligar, o código pode entrar pela **MCP do Studio** (`robloxstudio-mcp`):

1. `scripts/build-sync.sh` compila `build/Shared.rbxm`, `build/Server.rbxm` e `build/Client.rbxm`.
2. O agente apaga as versões antigas no Studio e importa estas com `import_rbxm`:
   - `Shared` → `ReplicatedStorage`
   - `Server` → `ServerScriptService`
   - `Client` → `StarterPlayer.StarterPlayerScripts`

Os ficheiros em `src/` são a fonte da verdade: **não edites estes scripts dentro do Studio**, porque a próxima sincronização apaga essas alterações.

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

## Estado

O que já existe, o que está testado e o que falta: `docs/PROTOTYPE-STATUS.md`. Decisões tomadas: `docs/DECISIONS.md`. Perguntas em aberto: `docs/OPEN.md`.

## Milestones

M0 Setup → M1 World → M2 Animals → M3 Core loop → M4 Persistence → M5 Exposure → M6 Research → M7 Trading → M8 UI, mobile, leaderboards.
