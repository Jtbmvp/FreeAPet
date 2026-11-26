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

Since 2026-11-26 the cards are photos of each island (3 x 2 grid): Studio captures cropped to 512x288 by
`tools/travel-ui/crop_biomes.ps1` and uploaded as Images to the group (ids in `BIOMES[].image`: Base
74579908738802, Lobby 77141567044546, Forest 118986846511929, Desert 130846288095244, Ice 126009387604003,
Kingdom 96027797689391). Each card: photo in a rounded CanvasGroup, dark fade at the bottom, big name with
outline, biome-coloured border and top strip, "Travel" / "Go home" button; the whole card is clickable and
hover zooms the photo with a light glow. The panel is 860x560 (900x430 on phones) and is scaled to fit.

## Travel portal animation (2026-11-22)

`StarterPlayerScripts.TravelPortalClient` (`TravelPortalClient.client.luau`, LocalScript) plays a cinematic for
every accepted trip (about 6 s); the portal model is described in `studio/portal/README.md`.

1. Server accepts `("go", biome)` (same checks as before; repeated clicks while a trip is pending are ignored)
   and sends `("start", biome)` to the player and `("fx", "depart", player, cframe, biome)` to everyone.
2. Client: a tinted flash, the HUD ScreenGuis are hidden, the character is moved to a private stage under
   the map (`6000 + (UserId % 16) * 400, -440, 0`; night void, stars, a nebula, the haze thinned locally)
   where the portal opens in the destination colour. Scripted camera; the character (root anchored, its
   own run/jump animations) runs and leaps into the vortex, which speeds up, white flash, `("enter")`.
3. Server does the real move to `TP_*` / the base spawn when `enter` arrives (or after 5 s anyway) and sends
   `("fx", "arrive", ...)`. Behind the white flash the client waits for it (up to 3 s), then removes the stage.
4. Sky drop (2026-11-26, replaces the spiral tunnel and the small arrival portal): a client-only copy of the
   character starts 190 studs above and 44 behind the arrival point and skydives onto the island, camera above
   and behind looking down (Fortnite style). Free fall 1.3 s, belly-down, arms spread, wobbling, wind lines and
   a few clouds; then a stud-style parachute (7 coloured Plastic blocks with studs + 4 lines) pops open, the fall
   slows, it sways a little and lands softly on the point (2 s); a dust ring + puff, the canopy folds. The real
   character waits at the point, root anchored and hidden locally (`LocalTransparencyModifier`), then takes the
   copy's place; camera, controls and HUD return. Whole trip about 6 s. Others see the departure portal and a
   dust ring at the arrival point.

Safety: controls are frozen with a high-priority ContextActionService sink (the place has no PlayerModule);
everything is undone after 10 s, on death or respawn; a character left on the stage is moved back.
QA only: the player attribute `TravelPortalHold` = `stage` / `fall` / `glide` pauses the trip at that
moment for screenshots.
