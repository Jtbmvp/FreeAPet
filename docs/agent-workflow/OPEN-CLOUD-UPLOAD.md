# Upload de assets pela Open Cloud

A MCP do Studio não tem chave Open Cloud. O upload faz-se com `scripts/opencloud-upload.ps1` (PowerShell 7) e o Studio usa depois os IDs.

## Chave
- Lê-se de `$env:ROBLOX_OPEN_CLOUD_KEY` ou de um ficheiro local fora do Git (por omissão `API Key OpenCloudRoblox.txt` na raiz do clone, em `.git/info/exclude`).
- Precisa do âmbito `asset:read` + `asset:write`. **Nunca** se faz commit da chave nem se escreve num log ou relatório.
- Os assets ficam no grupo dono do jogo, **jot4b Productions** (`11782476`); `-UserId` muda o dono.

## Usar
```powershell
pwsh scripts/opencloud-upload.ps1 assets/map-textures/Grass_a.png
pwsh scripts/opencloud-upload.ps1 assets/map-textures -Recurse -DescriptionText "Texturas do chão"
pwsh scripts/opencloud-upload.ps1 tree.fbx -DisplayName "Tree_Oak_A" -Json
```
| Ficheiro | Tipo no Roblox | Como se usa no Studio |
|---|---|---|
| png, jpg, bmp, tga | `Image` (`-AsDecal` para Decal) | `TextureID`, `Image`, `Texture` = `rbxassetid://<id>` |
| fbx, glb, gltf, rbxm, rbxmx | `Model` | MCP `insert_asset(assetId, assetName, parentPath)` |
| mp3, ogg, wav, flac | `Audio` | `SoundId` = `rbxassetid://<id>` |

- Máximo de 20 MB por ficheiro.
- Cada upload fica em `build/opencloud-uploads.json` (ignorado). Um ficheiro igual (mesmo SHA-256 e tipo) não volta a subir sem `-Force`.
- O script espera pela operação e mostra o `assetId` e o estado de moderação. Sai com código 1 se algum ficheiro falhar.

## Regras
- Os assets do LihFolk sobem só como privados: não se ativa a distribuição no Creator Store. Os ficheiros do pack nunca entram no repositório.
- Mexer no Studio continua a precisar do bloqueio. O upload, por si, não mexe no place.
- Verificado a 2026-11-08: uma imagem (Image `73811793379609`) e um modelo de teste (`119344623547657`) subiram aprovados e carregaram no Studio.
