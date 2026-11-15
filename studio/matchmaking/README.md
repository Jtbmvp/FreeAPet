# Matchmaking global 1v1 (2026-11-14)

Pedido do Duart: o matchmaking deixa de estar no portal e passa para um botão do HUD, com uma fila global entre servidores e teleporte para um servidor reservado que usa o coliseu atual (`Workspace.MIDAS_PvPArena_Staging`, que não foi alterado).

Estes ficheiros são a fonte dos scripts que vivem no Studio **fora** das pastas sincronizadas (`Server`, `Client` e `Shared`). O `build-sync.sh` e o `import_rbxm` não lhes tocam.

| Ficheiro | Instância no Studio |
|---|---|
| `MatchmakingServer.server.luau` | `ServerScriptService.MatchmakingServer` (Script) |
| `MatchmakingShared.luau` | `ReplicatedStorage.MatchmakingShared` (ModuleScript) |
| `PvpBattle.luau` | `ServerScriptService.PvpBattle` (ModuleScript): a batalha PvP |
| `MatchmakingClient.client.luau` | `StarterGui.MatchmakingGui.MatchmakingClient` (LocalScript dentro de um ScreenGui) |
| (criado no Studio) | `ReplicatedStorage.MatchmakingRemotes.Action` e `.State` (RemoteEvent) |
| (criado em runtime) | `ServerStorage.MatchmakingBindings.ReturnToLobby` (BindableEvent) |

## Como funciona

- **Salas** (`MemoryStoreService`, sorted map `MM_Rooms_v1`): cada jogador que carrega em FIND MATCH abre uma sala com 2 lugares. A lista mostra as salas abertas de todos os servidores, com o nome e o avatar de cada jogador, e o botão JOIN.
- **Cadeado por jogador** (`MM_Players_v1`): um jogador só pode estar numa sala, em qualquer servidor, e o servidor dele renova o cadeado de 4 em 4 s. Se o servidor morrer, o cadeado expira.
- **Entrar numa sala**: `UpdateAsync` atómico. Se dois jogadores carregarem em JOIN ao mesmo tempo, só um entra.
- **Comunicação** (`MessagingService`, tópico `FreeAPet_MM_v1`): avisa os outros servidores das mudanças. Cada servidor também lê o estado de 2 em 2 s, por isso uma mensagem perdida não deixa ninguém preso.
- **Match Found**: os dois servidores mostram os dois jogadores e uma contagem de 5 s. No fim, o servidor do anfitrião confirma que o convidado continua vivo (cadeado fresco), chama `TeleportService:ReserveServer`, grava a partida em `MM_Matches_v1` (pelo id do servidor privado e pelo id da sala) e muda a sala para `teleporting`, uma única vez, com um `UpdateAsync` condicional. Cada servidor teleporta o seu jogador com `TeleportAsync` e `TeleportOptions.ReservedServerAccessCode`. Se o teleporte falhar, faz até 3 tentativas (incluindo `TeleportInitFailed`); se continuar a falhar, liberta o jogador e avisa-o.
- **Servidor da arena** (servidor reservado): só deixa entrar os 2 jogadores da partida, que ficam presos no `Markers.Spawn_Red` e no `Markers.Spawn_Blue` do coliseu. Espera até 45 s que os dois carreguem e depois mais 3 s. Espera também que os pets da equipa de cada um apareçam (até 25 s). Segue-se a contagem 3, 2, 1, "FIGHT!" e começa a **batalha PvP** (ver abaixo). No fim, os dois voltam a um servidor público. Se um não chegar ou sair antes do início, a partida é cancelada e o outro volta a um servidor público. O portal de regresso do coliseu (ArenaLinkServer) também manda o jogador para um servidor público.
- **Abandonos**: se o anfitrião sair, a sala é cancelada e o convidado é avisado e pode procurar outra vez. Se o convidado sair, a sala volta a ficar aberta. Se o servidor do convidado morrer, o cadeado envelhece e o anfitrião reabre a sala antes do teleporte. Se o servidor do anfitrião morrer, o convidado cancela a sala ao fim de 25 s.
- **Studio**: os mapas MemoryStore têm o prefixo `studio_`, para não se misturarem com o jogo publicado. Como o Studio não teleporta entre servidores reais, a arena corre no próprio servidor de teste. O atributo `workspace.MM_StudioRealTeleport = true` obriga a chamar `TeleportAsync` no Studio.

## Batalha PvP (`PvpBattle`)

- Usa o ecrã de batalha do jogo, os mesmos ataques e as mesmas animações das batalhas contra selvagens: os remotes `Battle` e `BattleAction`, com `kind = "pvp"`. O cartão mostra "FOE" em vez de "WILD" e as cápsulas ficam desligadas. O `BattleService` ignora a `BattleAction` de quem não está numa batalha dele: os dois sistemas convivem sem mexer um no outro. Não se alterou nenhum ficheiro de `Server`, `Client` nem `Shared`; esses módulos só são lidos (`BattleMath`, `Config`, `Remotes`, `TeamService`, `AnimalService`).
- Regras: os dois escolhem ao mesmo tempo (ataque, troca ou desistência). As trocas acontecem primeiro e ataca primeiro o pet mais rápido (empate: moeda ao ar). Um pet KO é substituído pelo seguinte; sem pets vivos, perde. Sem escolha em 30 s, faz um ataque aleatório; dois tempos esgotados seguidos contam como desistência. Sair do jogo também conta como desistência.
- Cada pet começa com o HP cheio e nada é gravado: não se perde HP nem se ganha XP ou itens.
- Para procurar ou entrar numa sala é preciso ter pelo menos um pet na equipa.
- Posições: o vermelho é o lado 1 e o azul o lado 2, frente a frente à volta do `Markers.Center` do coliseu, com o mesmo layout (`Config.Battle.layout`) das batalhas contra selvagens.
- Teste no Studio: com `workspace.MM_StudioBotBattle = true`, o único jogador do teste luta contra um bot que copia a equipa dele.

## O que mudou nos scripts que já existiam (só no Studio)

O backup das versões originais está em `ServerStorage.MIDAS_MatchmakingBackup_20261114`.

- `ServerScriptService.ArenaLinkServer`:
  - `PORTAL_MATCHMAKING = false`: a escolha "queue" do portal é recusada e aparece um aviso para usar o botão 1v1;
  - o portal de regresso do coliseu, num servidor de arena, dispara `MatchmakingBindings.ReturnToLobby`.
- `StarterPlayer.StarterPlayerScripts.ArenaLinkClient`:
  - `PORTAL_MATCHMAKING = false`: o botão "Matchmaking 1v1" do menu do portal fica escondido e o painel encolhe;
  - a visita a solo e o portal continuam iguais.

Para repor o comportamento antigo, basta pôr os dois `PORTAL_MATCHMAKING` a `true`.

## Testes (Studio, place 109653985388163, PlaceVersion 231, 2026-11-14)

| Caso | Resultado |
|---|---|
| Os serviços MemoryStore e MessagingService respondem no Studio | PASS |
| Botão 1v1 no HUD, abre a sala de espera | PASS (captura) |
| A lista mostra jogadores de "outros servidores" (salas simuladas no MemoryStore) com nome e avatar | PASS (captura) |
| JOIN numa sala de outro servidor → `found` com contagem 5→0 | PASS |
| Entrar numa 2.ª sala ou abrir uma sala estando já numa → ignorado | PASS |
| Dois JOIN em simultâneo de servidores diferentes → só 1 entra | PASS (`{"Roblox":true,"builderman":false}`) |
| O anfitrião sai da fila → a sala é cancelada e o jogador pode voltar a procurar | PASS |
| O convidado desaparece depois do Match Found (servidor morto, cadeado envelhecido) → o anfitrião reabre a sala antes do teleporte | PASS (log `guest gone before teleport, reopening`) |
| Sala cheia → `match ready` → o jogador fica preso no Spawn_Red do coliseu, o botão 1v1 fica escondido | PASS (pos 942,4,1900, `Anchored=true`) |
| O adversário não chega → cancelado ao fim de 45 s → regresso ao lobby | PASS (`arena_end cancelled_noshow` → `returning` → `idle`) |
| `ReserveServer` no Studio | PASS (devolve o código; o `PrivateServerId` vem vazio no Studio, daí a cópia da partida pelo id da sala) |
| Batalha PvP no coliseu (contra o bot de teste): intro, turnos, tempo esgotado → ataque aleatório, KO → `won` → `arena_end battle_knockout` → regresso ao lobby, WalkSpeed reposto | PASS (captura) |
| Desistência (Run) a meio → `ran` → `arena_end battle_forfeit` → lobby | PASS |
| `TeleportAsync` no Studio | O Studio reinicia a sessão como servidor público: não dá para testar a arena reservada |
| Portal: a escolha "queue" não abre fila; o botão da fila está escondido | PASS |
| Teleporte real entre servidores públicos, chegada dos 2 ao servidor reservado, falha de teleporte real | **NOT RUN**: só no jogo publicado |
| Dois jogadores reais no mesmo servidor ou em servidores diferentes | **NOT RUN**: só no jogo publicado (ou num teste local com 2 jogadores no Studio) |

## Limites conhecidos

- A batalha entre dois jogadores reais (dois clientes) só foi testada contra o bot; falta testar com 2 contas no jogo publicado.
- As trocas voluntárias de pet ainda não foram testadas no Studio (só as trocas por KO, pelo código).
- Nada é recompensado (XP, dinheiro): se quiserem recompensas, é uma decisão de jogo nova, a registar no DECISIONS.md.
