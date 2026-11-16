# Biblioteca de pets (site local)

Site estático, sem instalação: three.js vem incluído em `vendor/`.

```bash
python3 -m http.server 8765 --directory design/pets
```

Abrir <http://localhost:8765/viewer/>.

## Adicionar um pet (automático)

Cada pet tem uma pasta `design/pets/<pasta>/` com um `pet.json`:

```json
{ "id": "moon-kitsune", "name": "Moon Kitsune", "file": "MoonKitsune",
  "source": "MoonKitsune_meshy_rigged.glb", "rarity": "Mythic", "biome": "Forest", "tags": ["Lua", "Raposa"] }
```

Quando o pet é exportado (`scripts/build.py`), o build gera a miniatura e reescreve `viewer/pets.json` com todos os pets que têm GLB exportado (`_shared/register.py`). A página verifica o `pets.json` a cada 4 s: pets novos aparecem sozinhos e um pet reexportado recarrega sem precisares de atualizar a página.

Raridades: Common, Uncommon, Rare, Epic, Legendary, Mythic. Biomas: qualquer nome (Forest aparece como "Floresta"). A biblioteca ordena por raridade e tem filtros por raridade e bioma.

Para ver um ficheiro sem o registar: `viewer/?model=../<pasta>/export/<Pet>.glb`.

## Atalhos

Espaço pausa · ← → frame a frame · 1–9 clips · Enter recomeça · R rodar · S esqueleto · G chão · W arame · C repor câmara.

Os marcadores `release`, `impact` e `ground` aparecem na linha do tempo e disparam um anel no chão quando a animação passa por eles.
