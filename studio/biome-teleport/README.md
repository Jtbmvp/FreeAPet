# Biome teleport (Studio)

Source for the "Travel" HUD button that teleports a player to one of the five biomes or to their own base.
Kept here because these instances live in the place file, outside the synced `Server` folder.

| File | Studio location |
|---|---|
| `BiomeTeleportServer.server.luau` | `ServerScriptService.BiomeTeleportServer` (Script) |
| `BiomeTeleportClient.client.luau` | `StarterGui.BiomeTeleportGui.BiomeTeleportClient` (LocalScript, ScreenGui ResetOnSpawn = false) |

Other instances it uses:

- `ReplicatedStorage.BiomeTeleportRemotes.Teleport` (RemoteEvent). The server makes it if it is missing.
- `Workspace.Map.TeleportPoints.TP_Lobby / TP_Forest / TP_Desert / TP_Ice / TP_Kingdom`: invisible, anchored
  parts with no collision, 0.5 studs above the ground and facing into the biome.
- `Workspace.Map.Bases.Base_<N>` (read only): the player's base is the plot whose `PlotIndex`/`BaseIndex`
  matches the player's `PlotIndex` attribute (set by BaseService). The player goes to its `Spawn` marker
  + 4 studs, like BaseService's own spawn (fallback: the floor of its `SafeZone`). A plot owned by someone
  else (`OwnerUserId`) is refused.

Server rules: only these 5 biome names plus `"Base"`; about 3 s cooldown per player; no teleport while
`InBattle` is true, during a PvP match (`PvpBattle.IsBattling`) or on the arena server (`MM_ArenaServer`, as a
workspace attribute or child); the character must be alive. Velocity is set to zero after the move.

Client: the Travel button replaces the HUD's green "Base" button (top centre). The HUD scripts are not
edited: at runtime the client finds `PlayerGui.FreeAPet...HUD.Base`, hides it (and hides it again if the HUD
shows it), and puts a copy of that plate labelled "Travel" in the HUD, following the Base plate's position and
size (the HUD pins its buttons on wide screens). If no Base plate shows up within 20 s, a fallback green
Travel button appears at the top centre. The panel has 6 cards (🏠 My Base, ⛲ Lobby, 🌲 Forest, 🏜️ Desert,
❄️ Ice, 🏰 Forgotten Kingdom), marks "YOU ARE HERE" from the player's `Zone` attribute and hides on the arena
server.
