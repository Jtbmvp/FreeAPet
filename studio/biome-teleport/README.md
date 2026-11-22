# Biome teleport (Studio)

Source for the "Travel" HUD button that teleports a player to one of the five biomes or to their own base.
Kept here because these instances live in the place file, outside the synced `Server` folder.

| File | Studio location |
|---|---|
| `BiomeTeleportServer.server.luau` | `ServerScriptService.BiomeTeleportServer` (Script) |
| `BiomeTeleportClient.client.luau` | `StarterGui.BiomeTeleportGui.BiomeTeleportClient` (LocalScript, ScreenGui ResetOnSpawn = false) |
| `TravelPortalClient.client.luau` | `StarterPlayer.StarterPlayerScripts.TravelPortalClient` (LocalScript) |

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

## Travel portal animation (2026-11-22)

`StarterPlayerScripts.TravelPortalClient` (`TravelPortalClient.client.luau`, LocalScript) plays a cinematic for
every accepted trip (about 4 s); the portal model is described in `studio/portal/README.md`.

1. Server accepts `("go", biome)` (same checks as before; repeated clicks while a trip is pending are ignored)
   and sends `("start", biome)` to the player and `("fx", "depart", player, cframe, biome)` to everyone.
2. Client: a tinted flash, the HUD ScreenGuis are hidden, the character is moved to a private stage under
   the map (`6000 + (UserId % 16) * 400, -440, 0`; night void, stars, a nebula, the haze thinned locally)
   where the portal opens in the destination colour. Scripted camera; the character (root anchored, its
   own run/jump animations) runs and leaps into the vortex, which speeds up, white flash, `("enter")`.
3. Tunnel screen: rings and speed lines in the biome colour, "TRAVELLING TO", the emoji and the name
   (Montserrat Heavy, dark outline).
4. Server does the real move to `TP_*` / the base spawn when `enter` arrives (or after 5 s anyway) and sends
   `("fx", "arrive", ...)`. Client: a small portal opens behind the character, it walks out, the camera
   eases back, controls and HUD return, the portal closes. Others only see the small portals on the spot.

Safety: controls are frozen with a high-priority ContextActionService sink (the place has no PlayerModule);
everything is undone after 8 s, on death or respawn; a character left on the stage is moved back.
QA only: the player attribute `TravelPortalHold` = `stage` / `tunnel` / `arrive` pauses the trip at that
moment for screenshots.
