# Mapa V4: plano de construção (Gaia / MIDAS)

Responsável: Gaia (mapa e VFX do mapa). A MIDAS é a única responsável por `Workspace.Map*` e `docs/map/`.
Contrato de código: `CONTRACT.md` (Forge). Direção de arte: `ART.md` (Iris). **Quando um destes ficheiros e
este plano não coincidirem, ganham eles.** Até lá, este é um rascunho baseado nas medições do V3 e no
código atual de `src/`.

## Ficheiros
| Ficheiro | Para que serve |
|---|---|
| `layout.json` | Fonte da verdade do layout: zonas, retângulos em studs, alturas, cores e quantidades. |
| `build/BuildMapV4.luau` | Script de construção (corre no Studio pela MCP, `execute_luau`). Lê a tabela gerada a partir do `layout.json` e constrói em `Workspace.MapV4_Staging`. É idempotente por bloco: cada bloco apaga e reconstrói só a sua própria pasta dentro do staging. |
| `build/Audit.luau` | Verificações: superfícies coplanares (≥ 0,1 stud, com `CanQuery` ligado temporariamente), peças a flutuar ou enterradas, contratos e orçamento. |

## Regras de construção (resumo de studify + LihFolk worldbuilding + regras da equipa)
- **Chão = Terrain** (ordem da Astra). Nada fica coplanar com o Terrain nem entre peças: mínimo de 0,1 stud
  (o studify pede pelo menos 0,0001; a regra da equipa é mais forte e prevalece).
- Peças: `Plastic`, com o MaterialVariant escolhido pela função (o `MaterialService` do place tem `Studs`,
  `Universal` e `Inlet`, medido a 2026-11-07). Estrutura → `Studs`; grandes superfícies e massas → `Universal`.
  Neon só como acento.
- Grelha de 0,1 stud; rotações em passos de 15°; massas em studs inteiros.
- Mapa com altitude: ilhas flutuantes, anel de planaltos sem buracos (≥ 16 studs), nada no mesmo plano.
- Decoração: `Anchored`, com `CanCollide`, `CanTouch` e `CanQuery` desligados. Gameplay (zonas, bases, HealPoint)
  simples e legível.
- Assets do LihFolk: só carregados no Roblox como **privados**; nenhum ficheiro do pack entra no Git; o
  Dataset é só para estudo.

## Decisões em aberto (para o PR / `DECISIONS.md`)
1. **Studs no Terrain.** O studify quer studs em todas as superfícies, mas o Terrain não tem studs. A opção
   é usar `MaterialService` overrides com variantes de studs nos materiais do Terrain (Grass, Sand...).
   **Atenção: os overrides são globais**, por isso mudariam também o Terrain do V3 enquanto o V3 estiver
   ativo. Proposta: só se aplicam no corte.
2. **Terrain do staging.** O Terrain é um só para todo o place. O V4 constrói-se desfasado (`STAGING_OFFSET`
   = Z +3000) para não tocar no V3. No corte: o Terrain do V3 vai para um `TerrainRegion` em
   `ServerStorage.MapV3_Backup_<data>` (`CopyRegion`), a região do V4 é colada na origem
   (`PasteRegion`) e o staging é movido −offset.
3. **Layout:** manter as três ilhas do V3 (Safe Zone, Forest, Desert, ao longo de X) para não partir
   distâncias e streaming, ou refazê-lo. O rascunho mantém a disposição e as escalas.

## Blocos (4 h cada, bloqueio do Atlas através da Astra)
1. Terrain, layout e Safe Zone (fonte, HealPoint, 5 bases e portões).
2. Forest.
3. Desert e FX.
4. Iluminação, polimento e verificação dos contratos. Corte com backup completo do V3, sem apagar nada.
