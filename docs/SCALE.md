# Scale reference

One Roblox stud is the unit for everything. Use this table when making or
importing new models so the world stays consistent.

## Player and world

| Thing | Size (studs) | Notes |
|---|---|---|
| Player (R15, default body) | ~5 tall, ~2 wide | Avatars with big hair/hats reach ~6.5 |
| Player WalkSpeed | 22 studs/s | `Config.Gameplay.player.walkSpeed` (Roblox default 16) |
| Whole map | ~1250 x 485 | ~57 s end to end at 22 studs/s |
| Safe zone | 400 x 400 | Fountain in the middle, 5 bases around it |
| Base plot | 100 x 100 | Pets wander in its PetArea (76 x 56) |
| Base sign board | 8 x 2.8 | Shows `<DisplayName>'s Base` |
| Fence | ~3.5 tall | Waist to chest height of the player |
| Forest / desert trees and cacti | 15-35 tall | Landmarks; must read from far away |

## Pets

Pet art can be exported at any size: `AnimalFactory` measures the model and
scales it so the **adult** pet at size 1.0 is `heightStuds` tall
(`Config/Species.luau`). On top of that, two multipliers apply:

- **Growth stage**: Baby 0.75, Juvenile 0.88, Adult 1.0 (`Config/Economy.luau`).
  Wild pets are babies.
- **Individual size roll**: 0.8 to 1.4, skewed towards small.

| Species | Rarity | Adult height | Wild baby (typical) | Feel |
|---|---|---|---|---|
| Acorn Squirrel | Common | 4 | ~3 | Small, knee-to-hip |
| Hopping Mushroom | Uncommon | 4.5 | ~3.4 | Small |
| Running Cactus | Common | 5.5 | ~4 | Player-sized when grown |
| Ball Scorpion | Uncommon | 3 (long body) | ~2.3 | Low and wide |
| Branch Deer | Rare | 8 | ~6 | Taller than the player |
| Sun Camel | Rare | 9 | ~6.8 | Biggest, clear presence |

Rules for new species:

- Commons 3-5.5, uncommons 3-6, rares 7-10. Never under 2.5 as a wild baby
  (hard to see) or over ~13 at max size (blocks the camera and paths).
- Low, wide animals (scorpion-like) get a smaller height; the factory uses
  height, so check the length stays under ~8.
- Prompts and catch range start at the pet's edge (`AnimalService.Radius`),
  so big pets are as easy to reach as small ones.
