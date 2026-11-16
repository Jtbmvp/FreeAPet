# Moon Kitsune · Mítico · Floresta

Modelo Meshy com rig (43 ossos, 8 caudas) animado por código. Rig, nomes, pose de repouso e pesos não foram alterados.

| Clip | Duração | Marcadores | VFX |
|---|---|---|---|
| `Idle` | 4.0 s, loop | | |
| `Walk` | 0.9 s, loop | `step_*` | |
| `Attack_FoxfireVolley` | 1.8 s | `release` 0.74, `impact` 0.95 | projétil: chama na ponta de cada cauda, disparadas no release |
| `Attack_LunarCrescent` | 1.6 s | `release` 0.38, `impact` 0.82 | corte: volta completa no ar, arco de lua crescente a seguir as caudas |
| `Attack_EclipseNova` | 2.2 s | `release` 0.85, `impact` 0.98 | radial: disco lunar nas caudas, nova ao esmagar o chão |
| `Fainted` | 2.5 s | `ground` 1.46 | fica na pose final |

Ficheiros: `export/MoonKitsune.glb` (site), `export/MoonKitsune.fbx` (Roblox Studio), `export/MoonKitsune_clips.json`.
Scripts: `scripts/kitsune_rig.py` (mapa do rig), `scripts/kitsune_clips.py` (animações), `scripts/build.py` (usa `../_shared/petrig.py`).

```bash
python design/pets/moon-kitsune/scripts/build.py          # bake + validação + exportação + registo no site
python design/pets/moon-kitsune/scripts/build.py check    # só validação
```

Notas do rig: patas dianteiras com 3 ossos, traseiras com 2 (a pata traseira não tem osso próprio); o eixo das caudas está preso à coluna da frente e as animações fazem-no seguir a bacia. Nenhum clip desce mais de 2 cm abaixo do chão.
