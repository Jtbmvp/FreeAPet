# Travel portal (Blender model)

The portal the Travel cinematic uses (`StarterPlayerScripts.TravelPortalClient`). Modelled in Blender 5.3
from a script: a chunky stone ring on a studded plinth, rune inlays, a crystal keystone, two rings and a
spiral vortex with a twisted depth funnel.

- `make_portal.py`: `blender -b --factory-startup --python make_portal.py -- <out_dir>`. Writes
  `portal.fbx/.obj/.blend`, renders and `portal_stats.txt` (about 13 k triangles in total).
- `portal.fbx`: uploaded with `scripts/opencloud-upload.ps1` (in the FreeAPet clone) as Model asset
  **75409915021012** (group-owned).

## In the place: `ReplicatedStorage.TravelPortal` (Model, template, not in the world)

Scaled to studs (×0.01 after import), pivot on the ground at the origin, the mouth facing **-Z**, ring centre
at y = 9.6 (attribute `PortalCenterY`). Every part is anchored, CanCollide/CanQuery/CanTouch off.

| Part | Look | Notes |
|---|---|---|
| `Base` | cream Plastic | holds the attachments `BeamL`, `BeamR`, `BeamT` and two Beams (side crystals to the keystone) |
| `Arch` | lilac Plastic | |
| `Runes` | Neon | recoloured per destination |
| `Crystals` | Neon, 0.1 transparent | recoloured per destination |
| `RingOuter` / `RingInner` | gold SmoothPlastic / Neon | spin in opposite directions |
| `Swirl` | Neon, 0.25 transparent | spins fast |
| `Vortex` | ForceField | depth funnel, spins slowly |
| `VortexBack` | Neon cylinder | dark disc behind the vortex |
| `Fx` | invisible disc part | `Inward` (sparkles pulled into the centre), `Burst` (Rate 0, emitted on open/dive), `Glow` PointLight |

The client clones it, recolours it (green Forest, gold Desert, ice blue Ice, lilac Kingdom, pink Lobby,
turquoise My Base), scales it and spins the parts every frame (BulkMoveTo); clones are destroyed after use.
