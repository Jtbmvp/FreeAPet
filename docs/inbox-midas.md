# Inbox MIDAS → Atlas

## 2026-11-09 — NewMap_V6, passagem da Gaia (pedido do JB)

**Alterado**
- Backups em `ServerStorage.GaiaV6Backup_20261109` (o mapa inteiro e a luz). Tudo o que foi removido está em `ServerStorage.GaiaV6Removed_20261109`, com o caminho original. Nada foi apagado.
- Correções apontadas:
  - as costelas formam agora 4 arcos assentes no chão;
  - o fosso ficou tapado;
  - os `Bush_Big` têm 3 tons e alguns têm bagas;
  - 4 paredes invisíveis no anel (até y160) e a crista leste subida;
  - saíram 234 ladrilhos enterrados, 1654 peças escondidas e 162 placas duplicadas do Relief.
- Cascata e lago (sugestão 5): água em 3 camadas, espuma, salpicos, névoa, ondulação, um caminho de pedras até uma rocha junto à queda, e juncos, rãs, libélulas e borboletas.
- Floresta: 56 árvores, decorações e montes de terreno saíram dos caminhos e das áreas dos pets. Há 3 caminhos novos para a Dark Forest (norte, oeste e leste).
- Dark Forest refeita de raiz: anel de pedras, 20 árvores retorcidas, 7 cogumelos gigantes com luz, cogumelos luminosos, um santuário com runas e 3 arcos de entrada.
- Deserto:
  - pirâmide nova `Desert.PyramidTemple` (base 72, altura 48) com topo dourado, escadaria e portal com hieróglifos;
  - avenida de colunas, obeliscos, 2 esfinges e braseiros;
  - mais 20 adereços egípcios.
- Nevoeiro e luz por zona (Dark Forest e deserto): a luz muda ao entrar e o nevoeiro aumenta à medida que se avança. Está em `src/client/MapV6Mood.client.luau`. O script antigo procurava `Workspace.NewMap_V6` e nunca funcionou; a versão original ficou em `GaiaV6Backup_20261109.MapV6Mood_orig`.
- Fonte do spawn: água a correr nos 8 jorros e no jato, e ondulação nas bacias. O nome e o pivô de `spawn_fountain` não mudaram.
- `Gate_Forest`: o ícone passou a ser um pinheiro, dos dois lados.
- Portal: só a superfície mudou, agora com profundidade, brilho, animação, vórtice, névoa e runas. À frente tem elementos de arena: anel no chão, cantos vermelho e azul com estandartes, pilaretes e 2 tochas.
- 2 texturas de água subidas para o grupo 11782476.
- Place gravada com Save to Roblox (PlaceVersion 142 depois da gravação).
- Quarentena `cloud_*`: não foi precisa. Uma pesquisa no place inteiro não encontrou nenhuma instância `cloud_*`.

**Testado**
- PASS: o que o código usa está intacto (Map.Bases, Zones, SpawnAreas, `spawn_fountain` com o mesmo pivô, `Map.Collision.NewMap_V6`).
- PASS: em playtest, o script de mood deteta bem o lobby, a floresta, a Dark Forest e o deserto.
- PASS: há caminho a pé do spawn até todas as áreas dos pets, às 3 entradas da Dark Forest, à rocha da cascata e ao topo da pirâmide.
- PASS: as 9 tentativas de fuga pelo perímetro falham. Uma subida pela montanha norte foi corrigida e voltou a ser testada.
- PASS: as alterações estão no place depois de gravar (backups, PyramidTemple).
- PASS: capturas tiradas no Studio (pirâmide, Dark Forest, cascata, portal-arena e fonte). Seguem para o JB pelo Duart.
- NOT RUN: ver a transição de luz e nevoeiro a acontecer, o telemóvel, e a orientação das camadas de água. A Vigil faz o QA a seguir.

**Pendente**
- Aprovação visual do JB.
- A textura das estrias da água ainda estava em moderação; enquanto não for aprovada, a água a correr pode não aparecer.
- QA da Vigil (Play sem erros novos, transição de mood, largura dos caminhos).
- Revisão e merge do PR #5 e do PR #4.

**Ficheiros**
- PR #5 (`dc/gaia-mapa-v6`): `src/client/MapV6Mood.client.luau`, `tools/vfx/make-water-textures.ps1`, `docs/map/v6/GAIA-V6-PASS.md` (lista completa).
