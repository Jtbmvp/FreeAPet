# Biome teleport (Studio)

Source for the "Biomes" HUD button that teleports a player to one of the five biomes.
Kept here because these instances live in the place file, outside the synced `Server` folder.

| File | Studio location |
|---|---|
| `BiomeTeleportServer.server.luau` | `ServerScriptService.BiomeTeleportServer` (Script) |
| `BiomeTeleportClient.client.luau` | `StarterGui.BiomeTeleportGui.BiomeTeleportClient` (LocalScript, ScreenGui ResetOnSpawn = false) |

Other instances it uses:

- `ReplicatedStorage.BiomeTeleportRemotes.Teleport` (RemoteEvent). The server makes it if it is missing.
- `Workspace.Map.TeleportPoints.TP_Lobby / TP_Forest / TP_Desert / TP_Ice / TP_Kingdom`: invisible, anchored
  parts with no collision, 0.5 studs above the ground and facing into the biome.

Server rules: only these 5 biome names; about 3 s cooldown per player; no teleport while `InBattle` is true,
during a PvP match (`PvpBattle.IsBattling`) or on the arena server (`MM_ArenaServer`, as a workspace attribute
or child); the character must be alive. The player goes to the point + 3 studs up, with velocity set to zero.

Client: the button sits under the 1v1 button (same style: Montserrat/FredokaOne, gradient, dark outline,
UIScale press). It opens a panel with 5 cards (🏠 Lobby, 🌲 Forest, 🏜️ Desert, ❄️ Ice, 🏰 Forgotten Kingdom),
marks "YOU ARE HERE" and hides on the arena server.
