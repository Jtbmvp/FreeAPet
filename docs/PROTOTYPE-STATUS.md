# Free a Pet! — estado do protótipo (27 out 2026)

Todos os passos da ordem aprovada estão programados. Abaixo está o que existe, o que foi testado e o que falta testar.

## O que existe

| Sistema | Onde | Estado |
|---|---|---|
| Base com Cash/s, pets a passear na base | `HomeService`, `BaseService` | Testado |
| Apanhar e levar ao colo | `CarryService` | Testado |
| Soltar à mão (Pick up → Release here) e crescer por bioma | `HomeService`, `CarryService`, `GrowthService` | Testado |
| Equipa de batalha (até 3, seguem-te, não dão Cash, não podem ser roubados) | `TeamService` | Testado |
| Medidor de exposição (calor, nevoeiro) | `ExposureService`, `ForestFog` | Testado |
| Árvore de pesquisa em hexágonos (10 nós) | `ResearchService`, `ResearchTab` | Testado |
| Tablet: Inventory, Index, Research, Trade | `Tablet`, `UI/*` | Testado |
| Batalhas selvagens, Pet Capsule, XP, cura na fonte | `BattleService`, `BattleScreen` | Testado em solo |
| Roubo por batalha (o pet defende-se; o dono pode defender) | `BattleService` | Testado em solo com dono offline; **"Defend!" por testar** |
| Trocas | `TradeService`, `TradeTab` | Ecrãs testados; **troca real por testar** |
| Tabela por servidor (Cash/s) e tabela global na praça | `PlayerStateService`, `LeaderboardService` | Testado |
| Gravação (ProfileStore), rendimento offline | `PlayerDataService` | Testado |
| Animações Idle/Walk dos pets | `PetAnimator`, `PetAnimations` | Testado |

## Interruptores importantes (Config)

- `Battle.enabled = false`: **as batalhas estão desligadas no jogo publicado** até chegar a arte dos 3 iniciais (decisão 3). No Studio estão ligadas porque o Debug está ligado.
  - Com as batalhas desligadas, os selvagens apanham-se com E e os pets soltos roubam-se com E. Não há stun.
- `Debug.enabled` só está ligado no Studio. No jogo publicado não aparece o painel DEBUG nem o "Bring home" grátis.

## Por testar (precisa de 2+ pessoas)

O Studio neste computador (15 GB de RAM) não aguenta um teste local com 2 jogadores: o sistema fecha o Vinegar. Por isso estes testes ficam para um teste com pessoas reais (Publish → jogar com amigos), que o brief já pedia:

1. **Troca:**
   - O jogador A abre Tablet > Trade > "Trade" no B, e o B carrega em "Accept" na notificação.
   - Cada um junta pets.
   - Ambos carregam em Ready e depois em Confirm.
   - Depois de 3 s, os pets mudam de base. Confirmar nos dois tablets.
2. **Cancelar uma troca:** mudar a oferta depois de Ready tem de limpar as marcas, e Cancel tem de fechar a troca nos dois.
3. **Defender:**
   - O A solta um pet e o B desafia-o.
   - O A carrega em "Defend!" a menos de 120 studs, escolhe um ataque e confirma que é esse o usado.
   - Se o A não escolher, o pet decide passados 10 s.
4. **Roubo completo com o dono no servidor:** o B ganha, leva o pet, entra na base e o A recebe o aviso.
5. **DisplayName ≠ username** nas placas das bases e na tabela global.
6. **Telemóvel:** tablet, ecrã de batalha (o thumbstick esconde-se durante a batalha) e botão "Release here".

## O que tens de fazer no Studio

- **Game Settings → Places → Max Players = 5**, uma por base.
- **Bulk Import** de `assets/ui-upload/hex_fill.png` e `hex_frame.png`, e colar os IDs em `Config/UI.luau`.

## Assets que mais melhoram o jogo (ver `docs/ASSET-REQUESTS.md` e o relatório)

1. A arte dos 3 iniciais. É o que **liga as batalhas** no jogo publicado.
2. As animações `Hit`, `Faint`, `Attack` e `BattleIdle`. Entram pelo mesmo script que o Idle/Walk.
3. O modelo da Pet Capsule e os efeitos de batalha.
4. Os ícones `trade`, `index`, `inventory` e `loose_pets`. Hoje usam ícones provisórios do pack.

## A seguir

Modificações, correções e melhorias, conforme combinado com o developer.
