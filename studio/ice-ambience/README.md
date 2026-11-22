# Ice ambience (2026-11-22)

- `IceAmbience.client.luau` -> LocalScript `StarterPlayer.StarterPlayerScripts.IceAmbience` (outside `Client`).
- Studio data it uses (not in this file):
  - `Workspace.Map.Collision.NewMap_V6.Ice.Ambience`: 4 `SnowFall` sources (Rate 22, y=115) and 5 `DriftWind` blown-snow sources near the ground; emitters tagged `IceAmbienceFx`, disabled by default.
  - One `PointLight` named `IceGlow` (tag `IceGlow`, attribute `BaseBrightness` 0.9, Range 12) per crystal cluster in `Ice.Crystals`.
  - `Map.Zones.Zone_Ice` resized to 305x170x450 at (616.6, 90, 4486) to cover the whole island.
- No sound: game sound is off (`Shared.Sfx ENABLED = false`).
