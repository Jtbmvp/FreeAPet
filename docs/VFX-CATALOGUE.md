# Battle animation & VFX catalogue

Based on the real battle events (`BattleService` → client: `super`, `weak`, `capture`, `escape`, `faint`, `levelup`, `switch`, damage with `actor`/`target`/`moveType`), the 4 actions (Attack, Bag, Switch, Run), the real move list in `Config/Battle.luau` and the v3 creature sheets in Claude Design. Visuals only: no sound.

Priority: **P1** = needed for the battle to feel finished. **P2** = polish.
Status (28 Oct 2026): **done** U01–U04 (intro), U05 default attack, U06 impact, U07 hit flash + hitstop, U08 damage number, U09 shake/punch, U12 projectile, U13 slash, U14 shockwave, U15 charge-up, and C01–C18 (all 6 current creatures, procedural until their Attack_ clips exist). Everything else is still to do. The system lives in `src/client/Battle/Fx`.

## 0. Conventions (every prompt refers to this)

- **Files**
  - Universal effects: `src/client/Battle/Fx/Common.luau`.
  - Creature moves: `src/client/Battle/Fx/Moves/<SpeciesId>.luau`, returning `{ [moveName]: (ctx) -> () }`.
  - Entry point: `Fx.Play(moveName, ctx)`. It falls back to `Common.DefaultAttack` when there is no entry.
- **`ctx`** holds:
  - `attacker`, `target`: Models;
  - `moveType`: "Neutral" | "Forest" | "Desert";
  - `effect`: "super" | "weak" | nil;
  - `camera`: the BattleCamera API, with `Shake(tier)`, `Punch(fovDelta, time)` and `Follow(model, time)`;
  - `playClip(name)`: returns the track or nil, plus a `marker(name)` wait;
  - `impact()`: call it exactly once, at the hit frame. It drains the HP bar and shows the damage number.
- **Type colours**
  - Forest: `(110,220,90)` / `(40,150,60)`
  - Desert: `(255,180,80)` / `(220,110,30)`
  - Neutral: `(170,185,215)` / `(105,120,160)`
- **Rules**
  - Client only, and every instance is parented under one per-effect Folder that is destroyed when the effect ends (Debris as a backup).
  - Burst emitters use `Rate = 0` + `:Emit(n)`.
  - Max ~120 live particles per effect, and the effect is done in 1.6 s.
  - Never move server-owned parts for longer than the effect, and always restore their CFrame.
- **Attack clips** (the ones you create in Claude Design): a clip named `Attack_<MoveName>` (no spaces) in the creature's `PetAnimations`, with a marker `impact`. Recommended shape: anticipation 0.25–0.4 s, strike, impact, recovery 0.3–0.5 s back to the Idle pose.
- **Test:** the Studio-only bench, from the client command bar in a playtest: `require(game.Players.LocalPlayer.PlayerScripts.Client.Battle.FxPreview).Play("<SpeciesId>", "<Move>", "<TargetSpeciesId>", "super")`. It copies two live pets, stands them like in a battle in front of you and films the move with the battle camera. Billboards set to `AlwaysOnTop` don't show in Studio screenshots: avoid them.

---

## 1. Universal VFX

### Battle cinematics

**U01 · Battle Entry (P1)**
- **Target:** battle start.
- **Purpose:** "a battle has started", and a clean break from walking.
- **Looks:** black letterbox bars slide in (8% height). The world desaturates 40% for 0.3 s. The arena ring draws itself segment by segment around the circle.
- **Sequence:** 0–0.6 s. The bars stay until the FIGHT slam, then slide out.
- **Needs:** the 28 ring segments from `BattleService` (found by name under the arena model).
```
FreeAPet battle VFX U01 "Battle Entry". Follow docs/VFX-CATALOGUE.md §0. In Common.luau add BattleEntry(arena): letterbox bars (two black Frames, 8% screen height each, tween in 0.25 s Quad), a ColorCorrectionEffect saturation -0.4 that eases back to 0 over 0.6 s, and the arena's ring segments revealed in order (LocalTransparencyModifier 1→0, 20 ms apart, each with a 0.15 s Neon pulse). Return a handle with :Close() that slides the bars out. Clean up everything on battle end. Test with FxPreview.
```

**U02 · Creature Reveal (P1)**
- **Target:** our creature, then the foe, during the intro.
- **Purpose:** each creature gets its own hero moment.
- **Looks:**
  - A light ring bursts from its feet (type colour).
  - A white rim glow (Highlight, outline only, fades out).
  - Dust puffs from under its feet.
  - A slanted stud name banner slides in from the side: name, level, and a rarity colour stripe.
- **Sequence:** 1.2 s: ring 0.4 s, highlight 0.6 s, banner in 0.25 s / hold / out 0.2 s.
- **Needs:** the rarity colours from `Config/Rarities`.
```
FreeAPet battle VFX U02 "Creature Reveal". Follow docs/VFX-CATALOGUE.md §0. Add Common.Reveal(model, info) where info = {name, level, rarity, moveType, side="mine"|"foe"}. At the model's feet: a flat expanding ring (cylinder Part, Neon, type colour, 0→2.2x footprint over 0.4 s, transparency 0→1) plus 12 dust particles. A Highlight (FillTransparency 1, OutlineColor white) fading over 0.6 s. A UITheme stud banner (rarity colour stripe) sliding in from the left for mine and from the right for the foe, holding 0.6 s, then sliding out. Size everything from model:GetExtentsSize(). Test both sides with Glimmouse (small) and Sun Camel (large).
```

**U03 · Countdown 3-2-1 (P1)**
- **Target:** the intro, after the reveals.
- **Purpose:** build tension before control is given.
- **Looks:** a huge stud-style digit pops in the centre (3 = blue, 2 = yellow, 1 = red) with radial speed lines behind it. Each digit is a camera punch-in.
- **Sequence:** 3 × 0.5 s. Each digit scales 1.6→1 (Back easing), holds, then fades to 0.8 scale.
- **Needs:** —
```
FreeAPet battle VFX U03 "Countdown". Follow docs/VFX-CATALOGUE.md §0. Add Common.Countdown(onDone): for 3, 2, 1 show a UITheme.Label digit (TextSize 160, colours blue/yellow/red, thick black stroke) centred, scale 1.6→1 Back 0.2 s, hold 0.2 s, fade+shrink 0.1 s. Behind it, 16 white radial lines (rotated Frames) that flash on each number. Call ctx camera Punch(-4 FOV, 0.15 s) on every digit. Must respect a "skip" flag that jumps straight to onDone. Test with FxPreview.Countdown().
```

**U04 · FIGHT! Slam (P1)**
- **Target:** the end of the countdown.
- **Purpose:** the battle begins and the player has control.
- **Looks:**
  - "FIGHT!" slams in big, tilted −6°, red/orange stud gradient.
  - White screen flash 0.08 s.
  - A shockwave ring races across the arena floor.
  - Medium camera shake.
- **Sequence:** 0.5 s, then it hands over to the gameplay camera and the battle UI slides up.
- **Needs:** U01 (bars close here).
```
FreeAPet battle VFX U04 "FIGHT Slam". Follow docs/VFX-CATALOGUE.md §0. Add Common.FightSlam(arena): "FIGHT!" label scale 3→1 in 0.12 s (Quad Out), rotation -6, red→orange UIGradient, stroke 6; full-screen white Frame flash (transparency 0→1 over 0.08 s); Common.Shockwave at the arena centre with radius = arena radius; camera Shake("medium"); then close the U01 letterbox. Total 0.5 s.
```

### Attack, impact and feedback

**U05 · Default Attack (P1)**
- **Target:** any move without its own entry (also **Tackle**).
- **Purpose:** a readable attack while the clips don't exist.
- **Looks:**
  - Anticipation: the attacker crouches back 1 stud.
  - Dash to 60% of the gap, with a short white trail.
  - Impact.
  - It hops back.
- **Sequence:** 0.3 s / 0.15 s / impact / 0.35 s.
- **Needs:** U06, U07, U08, U09.
```
FreeAPet battle VFX U05 "Default Attack". Follow docs/VFX-CATALOGUE.md §0. Implement Common.DefaultAttack(ctx): procedural (no clip), tween the attacker's PrimaryPart: back 1 stud + down 0.3 (0.3 s Sine), forward to 60% of the distance to the target (0.15 s Quad In) with a Trail between two attachments (white, 0.15 s lifetime), call ctx.impact() + Common.Impact(ctx) at the contact moment, then return to the exact start CFrame (0.35 s Back Out). Replaces the old lunge() in BattleScreen.
```

**U06 · Impact Burst (P1)**
- **Target:** every hit.
- **Purpose:** contact, and how strong it was.
- **Looks:**
  - A star-shaped flash sprite at the hit point.
  - Type-coloured sparks.
  - Small stud debris cubes that drop and bounce.
  - Three tiers: weak (small, greyish), normal, super (2× size, extra ring, more debris).
- **Sequence:** 0.5 s.
- **Needs:** a star flash texture (built-in sparkles as a placeholder).
```
FreeAPet battle VFX U06 "Impact Burst". Follow docs/VFX-CATALOGUE.md §0. Add Common.Impact(ctx) at the target's surface point facing the attacker (raycast from attacker to target or use the bounding box). Tiers from ctx.effect: weak = 8 grey sparks, no debris; normal = 16 type-colour sparks + 4 debris; super = 30 sparks + 8 debris + a flat ring. Debris = 0.4-stud cubes, unanchored, CanCollide on, CanQuery off, local only, removed after 0.8 s. Plus a 0.12 s BillboardGui star flash.
```

**U07 · Hit Flash + Hitstop (P1)**
- **Target:** the target at impact.
- **Purpose:** makes hits feel heavy.
- **Looks:**
  - The target turns white for 0.08 s (Highlight fill).
  - The whole scene "freezes" for 0.06 s (normal) or 0.1 s (super): both creatures' animations pause.
- **Sequence:** instant at the impact.
- **Needs:** the `PetAnimator` pause API.
```
FreeAPet battle VFX U07 "Hit Flash + Hitstop". Follow docs/VFX-CATALOGUE.md §0. Add Common.HitFlash(model, effect): Highlight FillColor white, FillTransparency 0 → 1 over 0.08 s, DepthMode Occluded. Add a hitstop: PetAnimator.Freeze(models, seconds) holds the current Transform pose (0.06 s normal, 0.1 s super, 0 weak). Expose both via ctx.impact() so every move gets them for free.
```

**U08 · Damage Number (P1)**
- **Target:** the target after impact.
- **Purpose:** exact feedback in numbers.
- **Looks:**
  - "-23" in white with a black stroke pops above the target's head, rises 2 studs and fades.
  - Super: bigger, yellow, with "!".
  - Weak: smaller and grey.
- **Sequence:** 0.8 s.
- **Needs:** `event.damage`.
```
FreeAPet battle VFX U08 "Damage Number". Follow docs/VFX-CATALOGUE.md §0. Add Common.DamageNumber(model, amount, effect): BillboardGui (AlwaysOnTop, size scales with camera distance) above the head, UITheme.Label "-<amount>", pop scale 0.5→1.2→1 (Back), random x jitter ±1 stud, rise 2 studs over 0.8 s with fade. Colours: normal white, super gold (TextSize +40%), weak grey (-25%).
```

**U09 · Camera Shake & Punch (P1)**
- **Target:** BattleCamera.
- **Purpose:** weight on big moments.
- **Looks:** light, medium and heavy tiers, decaying noise on the position and roll. Punch = a quick FOV dip and return.
- **Sequence:** 0.15 / 0.25 / 0.4 s.
- **Needs:** BattleCamera (`PreRender`).
```
FreeAPet battle VFX U09 "Camera Shake". Follow docs/VFX-CATALOGUE.md §0. In BattleCamera add Shake(tier) and Punch(fovDelta, time): offsets added on top of the shot CFrame in the PreRender loop (never written to the base), Perlin noise (math.noise) decaying with (1-t)^2; tiers light 0.15 s/0.15 studs, medium 0.25 s/0.35, heavy 0.4 s/0.7 plus 2° roll. Add a "Camera shake" toggle in SettingsTab (on by default) that scales it to 0.
```

**U10 · Knockback (P2)**
- **Target:** the target on normal/super hits.
- **Purpose:** the force direction.
- **Looks:** the target slides back 1 stud (2 on super), tilts slightly away, then settles back. A dust puff at its feet.
- **Sequence:** 0.12 s out, 0.3 s back.
- **Needs:** —
```
FreeAPet battle VFX U10 "Knockback". Follow docs/VFX-CATALOGUE.md §0. Add Common.Knockback(model, fromPosition, effect): tween PrimaryPart along the flat direction away from the attacker 1 stud (2 on super) with a 6° tilt away, 0.12 s Quad Out, then back to the exact original CFrame in 0.3 s Sine; a dust puff at the feet. Skip on weak. Must restore the CFrame even if the battle ends mid-tween.
```

**U11 · HP Bar Chip (P1)**
- **Target:** the HP cards.
- **Purpose:** shows how much was lost.
- **Looks:** the bar drops at once and a light "ghost" segment drains after a 0.3 s delay. The card shakes 3 px. Below 20% the bar pulses red.
- **Sequence:** 0.3 + 0.5 s.
- **Needs:** the new HP cards (UI step).
```
FreeAPet battle VFX U11 "HP Chip". Follow docs/VFX-CATALOGUE.md §0. In the battle HP card add a ghost bar behind the fill: on damage, the fill jumps to the new size, the ghost (white 50%) waits 0.3 s then tweens to the same size in 0.5 s; the card frame shakes ±3 px for 0.15 s; below 20% the fill pulses red (sine, 1.5 Hz) until healed or switched.
```

### Generic building blocks (used by the creature moves)

**U12 · Projectile + Trail (P1)**
- **Target:** ranged moves (Acorn Toss, Needle Shot, Sun Beam…).
- **Looks:** a small mesh or part flies from a bone to the target on an arc or a straight line, leaving a type-coloured trail. It calls `impact()` on arrival.
- **Sequence:** 0.25–0.45 s of flight.
```
FreeAPet battle VFX U12 "Projectile". Follow docs/VFX-CATALOGUE.md §0. Add Common.Projectile({from=Vector3|Bone, to=Model, arc=studs, time=s, part=BasePart template, trailColor=Color3, spin=bool, onHit=fn}): anchored, CanCollide/CanQuery off, quadratic Bezier path updated in PreRender, Trail from two attachments, onHit at arrival then destroy. Must support firing N projectiles with a stagger (for barrage moves).
```

**U13 · Slash Arc (P1)**
- **Target:** melee swipes (Leaf Blade, Pinch, Tail Smack).
- **Looks:** a crescent ribbon (Beam with curve) sweeps across the target in 0.12 s and fades. Type colour with a white core.
- **Sequence:** 0.25 s.
```
FreeAPet battle VFX U13 "Slash Arc". Follow docs/VFX-CATALOGUE.md §0. Add Common.Slash(target, {angle=deg, color=Color3, width=studs}): a Beam between two attachments with CurveSize0/1 forming a crescent across the target's centre, Width 0→width→0 over 0.25 s, Texture none, LightEmission 1, white core = a second thinner Beam. Rotate by angle so different moves can slash at different tilts.
```

**U14 · Ground Shockwave (P1)**
- **Target:** stomps, slams, landings (Stomp, Cap Slam, FIGHT!).
- **Looks:** a flat ring expands on the ground, plus dust kicked outward and a small crack decal that fades.
- **Sequence:** 0.5 s.
```
FreeAPet battle VFX U14 "Shockwave". Follow docs/VFX-CATALOGUE.md §0. Add Common.Shockwave(position, radius, color): flat cylinder ring (two cylinders: outer Neon, inner transparent hole via a second thinner ring is fine) scaling 0→radius in 0.35 s with transparency 0.2→1; 20 dust particles emitted outward along the ground; snap the Y to the ground with a raycast against Map.Collision.
```

**U15 · Charge-up (P2)**
- **Target:** strong moves (the 3rd move of each creature, the one with 5 uses).
- **Purpose:** telegraphs a big hit.
- **Looks:** type-coloured particles get sucked into the creature, a growing glow (PointLight) and the camera slowly pushes in.
- **Sequence:** 0.5–0.7 s before the strike.
```
FreeAPet battle VFX U15 "Charge-up". Follow docs/VFX-CATALOGUE.md §0. Add Common.Charge(model, color, seconds): an Attachment emitter with negative Speed so 30 particles converge to the centre, a PointLight (Range 0→12, Brightness 0→3), and camera Follow(model) with a slow -6 FOV push over the charge time. Returns when finished; everything is removed at the strike.
```

**U16 · Effectiveness Callout (P2)**
- **Target:** `super` / `weak` hits.
- **Looks:** a small slanted banner by the message box: "Super effective!" (gold, bounces in) or "Not very effective…" (grey, slides in).
- **Sequence:** 0.9 s.
```
FreeAPet battle VFX U16 "Effectiveness Callout". Follow docs/VFX-CATALOGUE.md §0. Add Common.Callout(effect): UITheme stud panel above the battle message box, gold "Super effective!" (scale 0.6→1.1→1 Back, 4° tilt) or grey "Not very effective..." (slide in 20 px, fade). Auto-hide after 0.9 s; never stack two.
```

### Battle transitions

**U17 · Faint (P1)**
- **Target:** the `faint` event.
- **Looks:**
  - The creature desaturates (Highlight grey fill fades in).
  - It topples sideways in 0.5 s and sinks 0.5 studs.
  - 5 small white stars spin above its head, then everything fades to transparent.
- **Sequence:** 1.2 s. The model is restored when the server moves or heals it.
```
FreeAPet battle VFX U17 "Faint". Follow docs/VFX-CATALOGUE.md §0. Replace faint() in BattleScreen with Common.Faint(model): Highlight FillColor grey FillTransparency 1→0.4, topple 80° around the forward axis + sink 0.5 studs (0.5 s Quad In), a ring of 5 star sprites (BillboardGui) orbiting the head for 0.7 s, then LocalTransparencyModifier 0→1 over 0.4 s. Store and restore every changed property when the model is reused (switch, heal, battle end).
```

**U18 · Switch Out / In (P1)**
- **Target:** the `switch` event and the first send-out.
- **Looks:**
  - **Out:** the creature turns into light (white Highlight), shrinks to 0 and a beam of light flies to the player's hand.
  - **In:** the light lands on its spot, grows into the creature with a dust ring (U14, small) and a short reveal banner (U02 lite).
- **Sequence:** 0.5 s out, 0.6 s in.
```
FreeAPet battle VFX U18 "Switch". Follow docs/VFX-CATALOGUE.md §0. Add Common.SwitchOut(model, playerHand) and Common.SwitchIn(model): out = Highlight white fill 1→0, scale the model via a local copy (or PivotTo per frame) to 0.05 while a Beam/orb travels to the player's right hand; in = orb lands, the model scales 0.05→1.08→1 (Back), small Shockwave, U02 banner without the ring. Works with the real server switch: the out plays on the old model, the in on the new model from the event.
```

**U19 · Bag: Capsule Throw & Catch (P1)**
- **Target:** the `capture` / `escape` events.
- **Looks:**
  - The capsule arcs from the player's hand, spinning, with a blue trail.
  - On contact the creature dissolves into blue light streams sucked into the capsule.
  - The capsule wobbles N times (`event.damage` = shakes) with sparks each time.
  - **Caught:** a gold lock flash, a star burst, then it shrinks away.
  - **Escape:** it bursts open with a white flash and the creature reappears with a stagger.
- **Sequence:** about 0.6 s + 0.5 s × shakes + 0.8 s.
- **Needs:** the capsule model (decision C; sphere until then).
```
FreeAPet battle VFX U19 "Capsule Throw". Follow docs/VFX-CATALOGUE.md §0. Rebuild throwCapsule() as Common.Capsule(ctx, shakes, caught) using Common.Projectile (arc 6 studs, spin, blue trail). On arrival: the wild model gets a white Highlight then LocalTransparencyModifier→1 while 12 blue particles stream into the capsule; the capsule drops to the ground, wobbles ±25° per shake with 6 sparks; caught = gold Neon flash, 24 gold stars, shrink and remove after 1 s; escape = white flash, restore the model's transparency, small hop. Keep the sphere unless docs/BATTLE-POLISH-PLAN.md decision C says otherwise.
```

**U20 · Run Away (P2)**
- **Target:** `ran`.
- **Looks:** our creature turns and dashes off behind the player in a dust trail, white speed lines flash at the screen edges, and the camera blends back.
- **Sequence:** 0.8 s.
```
FreeAPet battle VFX U20 "Run Away". Follow docs/VFX-CATALOGUE.md §0. Add Common.RunAway(mine, player): turn the creature 180° (0.15 s), move it 4 studs past the player with a dust Trail (0.3 s), 10 white speed-line Frames at the screen edges flashing for 0.4 s, then call BattleCamera.Release(0.6 s blend back to the default camera).
```

**U21 · Level Up (P2)**
- **Target:** `levelup`.
- **Looks:** two golden rings rise from the feet to above the head, gold sparkles, a "LEVEL UP!" stud label pops, and the EXP bar fills and flashes.
- **Sequence:** 1.0 s.
```
FreeAPet battle VFX U21 "Level Up". Follow docs/VFX-CATALOGUE.md §0. Add Common.LevelUp(model): two gold Neon rings (thin cylinders) rising from feet to head height over 0.8 s with fade, 20 gold sparkles, BillboardGui "LEVEL UP!" (UITheme.Label gold, pop Back), and an EXP bar flash in the HP card (white overlay 0.2 s).
```

**U22 · Victory / Defeat (P1)**
- **Target:** the `result` field.
- **Looks:**
  - **Won/captured:** our creature hops twice, stud confetti (small coloured cubes) falls in front of the camera, and a "You won!" / "Caught!" stud banner appears.
  - **Lost:** a dark vignette closes in and a grey "Your team fainted…" banner appears.
- **Sequence:** 1.6 s, then BattleCamera.Release.
```
FreeAPet battle VFX U22 "Victory/Defeat". Follow docs/VFX-CATALOGUE.md §0. Add Common.Result(result, mine): won/captured = 2 procedural hops (0.25 s each) + 40 confetti cubes spawned in front of the camera (local, unanchored, CanCollide off, gravity, random UITheme kind colours) + a big green/gold stud banner; lost = black ImageLabel vignette (radial) tween in 0.5 s + grey banner; ran = nothing (U20). Then BattleCamera.Release(0.6).
```

**U23 · Fountain Heal (P2)**
- **Target:** "Heal team" at the Spawn Fountain (exists, outside battle).
- **Looks:** green-white sparkles spiral up each team creature, a soft green Highlight pulse, and "+HP" pops.
- **Sequence:** 1.0 s.
```
FreeAPet battle VFX U23 "Fountain Heal". Follow docs/VFX-CATALOGUE.md §0. When the heal prompt succeeds (server already heals), the client plays Common.Heal(model) on each team pet: 16 green/white particles with a spiral (two attachments orbiting via PreRender), Highlight green FillTransparency 0.6→1 over 0.5 s, BillboardGui "+HP" pop. Visual only; needs a small client event from the existing heal code.
```

Not catalogued on purpose: burn, freeze, stun, buffs and debuffs, because **they don't exist in the battle rules**. They can be added if you design them.

---

## 2. Creature-specific moves (animation + VFX)

Each move needs an **attack clip you create** (`Attack_<MoveName>`). Until it exists, the entry runs its VFX on top of U05's procedural motion. Every move calls U06–U08 through `ctx.impact()`.

### Acorn Squirrel (Forest · 1.3 m · biped, `jnt_acorn`, S-curled banded tail with amber rings)

**C01 · Tail Smack (Neutral, 55) (P1)**
- **Animation:** turn 120° away (0.3 s); the tail coils down (`jnt_tail_*` bend −); a whip-around spin; the tail tip hits; recover with a hop.
- **VFX:** an amber ring trail on the tail tip; U13 slash at 30° in the tail's amber colour.
- **Needs:** `Attack_TailSmack`.
```
FreeAPet move C01 "Tail Smack" (AcornSquirrel). Follow docs/VFX-CATALOGUE.md §0. In Fx/Moves/AcornSquirrel.luau add ["Tail Smack"]: play clip Attack_TailSmack if present (impact marker), else procedural: spin the model 360° in 0.35 s near the target (U05 dash). Attach a Trail (amber 255,190,80) to the last tail bone (or a point 1 stud behind the body), call ctx.impact() + Common.Slash(target,{angle=30,color=amber}) on impact.
```

**C02 · Acorn Toss (Forest, 50) (P1)**
- **Animation:** wind-up holding the acorn over its head (arms and `jnt_acorn` up, 0.35 s); throw; the acorn regrows in its paws during recovery.
- **VFX:** an acorn projectile (U12, arc 4, spin) with a green trail; on impact it splits into 2 shell halves + leaves.
- **Needs:** `Attack_AcornToss`; the acorn mesh (copy of the `jnt_acorn` part).
```
FreeAPet move C02 "Acorn Toss" (AcornSquirrel). Follow docs/VFX-CATALOGUE.md §0. ["Acorn Toss"]: clip Attack_AcornToss (marker "release" then "impact"), fallback = crouch+throw tween. At release hide the held acorn locally (LocalTransparencyModifier) and fire Common.Projectile with a clone of it (arc 4, spin, Forest trail). On hit: ctx.impact(), 2 half-shell debris pieces + 8 green leaf particles; show the held acorn again after 0.4 s.
```

**C03 · Nut Barrage (Forest, 85, 5 uses) (P1)**
- **Animation:** U15 charge (the tail rings glow); 6 rapid throws alternating paws; a big final throw.
- **VFX:** 6 small acorns (U12, stagger 0.08 s) + 1 big one; the impact happens on the last one; a light shake on every hit, heavy on the last.
- **Needs:** `Attack_NutBarrage`.
```
FreeAPet move C03 "Nut Barrage" (AcornSquirrel). Follow docs/VFX-CATALOGUE.md §0. ["Nut Barrage"]: Common.Charge(model, Forest, 0.5) with the tail's amber rings getting a PointLight; then 6 small acorn projectiles staggered 0.08 s (each: small spark, camera Shake light) and a 2x acorn last that calls ctx.impact() + Shake heavy. Clip Attack_NutBarrage if present, marker "impact" = the big acorn.
```

### Hopping Mushroom (Forest · 2.1 m · `jnt_cap`, `jnt_baby`, boots)

**C04 · Bounce (Neutral, 55) (P1)**
- **Animation:** squash low (0.25 s); a high arc jump onto the target; stretch in the air; the cap lags and flops on landing; bounce back.
- **VFX:** a small dust ring on take-off; a U14 shockwave (white) on the landing on the target.
- **Needs:** `Attack_Bounce`.
```
FreeAPet move C04 "Bounce" (HoppingMushroom). Follow docs/VFX-CATALOGUE.md §0. ["Bounce"]: clip Attack_Bounce or procedural: squash (scale Y by moving down 0.4) 0.25 s, Bezier jump arc (height 5) landing 1 stud in front of the target in 0.35 s, ctx.impact() + Common.Shockwave(small, white) on landing, hop back in 0.4 s. Dust ring on take-off.
```

**C05 · Spore Puff (Forest, 50) (P1)**
- **Animation:** the cap inflates (`jnt_cap` scale feel by lifting), the baby mushrooms shake (`jnt_baby`), then a puff.
- **VFX:** a cone of green-yellow spore particles drifts to the target (slow, swirly), and the target is enveloped in sparkling spores on impact.
- **Needs:** `Attack_SporePuff`.
```
FreeAPet move C05 "Spore Puff" (HoppingMushroom). Follow docs/VFX-CATALOGUE.md §0. ["Spore Puff"]: clip Attack_SporePuff or procedural cap wobble. Emitter at the top of the cap: 40 spore particles (green 170,230,90 → yellow), Speed 6-10 towards the target, SpreadAngle 20, Drag 1, RotSpeed random; after 0.45 s ctx.impact() and a spore cloud (30 particles, 1 s lifetime) around the target.
```

**C06 · Cap Slam (Forest, 85, 5 uses) (P1)**
- **Animation:** U15 charge (the cap spots glow white); a big jump high above the target; dive cap-first; slam; the cap flops; it wobbles back.
- **VFX:** U14 big shockwave (green) + ground debris + white spot particles flying off; heavy shake.
- **Needs:** `Attack_CapSlam`.
```
FreeAPet move C06 "Cap Slam" (HoppingMushroom). Follow docs/VFX-CATALOGUE.md §0. ["Cap Slam"]: Common.Charge(green, 0.5) with the white cap spots pulsing; jump arc height 9 over the target, rotate 160° to fall cap-first (0.3 s), ctx.impact() + Common.Shockwave(radius 8, Forest) + 12 white dot particles + camera Shake heavy; then flip upright and hop back (0.5 s).
```

### Branch Deer (Forest · 3.8 m · `jnt_antler`, lyre antlers with ivy and autumn leaves)

**C07 · Antler Charge (Neutral, 55) (P1)**
- **Animation:** head lowers with the antlers forward (`jnt_neck`/`jnt_head` down, 0.35 s); a pawing hoof; a galloping charge; antlers hit; it rears back slightly.
- **VFX:** speed lines + dust trail from the hooves during the charge; impact with U13 slashes at ±25° (two crossing arcs).
- **Needs:** `Attack_AntlerCharge`.
```
FreeAPet move C07 "Antler Charge" (BranchDeer). Follow docs/VFX-CATALOGUE.md §0. ["Antler Charge"]: clip Attack_AntlerCharge or procedural: tilt forward 15° + back 1 stud (0.35 s), charge to 70% of the gap (0.2 s) with dust Trails at the hooves, ctx.impact() + two Common.Slash (angles 25 and -25, ivory white), camera Follow(attacker) during the charge, return 0.45 s.
```

**C08 · Leaf Blade (Forest, 50) (P1)**
- **Animation:** an antler toss upward; the leaves on the ivy "come loose"; a head sweep sends them.
- **VFX:** 12 autumn leaves (green/gold/red, the sheet's colours) whirl into a blade-shaped stream and slice through the target (U13 green-gold); the leaves scatter.
- **Needs:** `Attack_LeafBlade`.
```
FreeAPet move C08 "Leaf Blade" (BranchDeer). Follow docs/VFX-CATALOGUE.md §0. ["Leaf Blade"]: clip Attack_LeafBlade (marker "release"); from the antler tips emit 12 leaf particles (flat, colours green/gold/red, RotSpeed high) that travel as a tight stream (Common.Projectile with a leaf-cluster part or particles following an attachment) to the target; on arrival ctx.impact() + Common.Slash(angle 10, green-gold) + leaves scattering outward.
```

**C09 · Forest Rush (Forest, 85, 5 uses) (P1)**
- **Animation:** rears up on its hind legs (U15 charge, the ivy glows); a stomp; a full charge wrapped in a leaf storm; a crashing impact; it skids to a stop.
- **VFX:** a leaf vortex around the deer during the charge; a green shockwave + leaf explosion on impact; heavy shake; the camera follows the charge.
- **Needs:** `Attack_ForestRush`.
```
FreeAPet move C09 "Forest Rush" (BranchDeer). Follow docs/VFX-CATALOGUE.md §0. ["Forest Rush"]: Charge(green, 0.6) while rearing (clip or tilt back 25°); then a charge to 80% with a leaf vortex (40 leaves orbiting the body via two rotating attachments), camera Follow(attacker); ctx.impact() + Shockwave(radius 9, Forest) + 30 leaves bursting + Shake heavy; skid back with a dust trail.
```

### Running Cactus (Desert · 2.0 m · branch arms, `jnt_flower` glowing pink bloom, pot shorts)

**C10 · Spin Dash (Neutral, 55) (P1)**
- **Animation:** a sprint pose with arms pumping on the spot (0.3 s), then a spin around itself (`jnt_hips`) while dashing.
- **VFX:** a cream spine-tipped spiral trail; sparks on contact.
- **Needs:** `Attack_SpinDash`.
```
FreeAPet move C10 "Spin Dash" (RunningCactus). Follow docs/VFX-CATALOGUE.md §0. ["Spin Dash"]: clip Attack_SpinDash or procedural: 0.3 s arm-pump wiggle, then dash to 60% while rotating 720° around Y (0.3 s) with two cream Trails on the arm tips forming a spiral; ctx.impact() + 10 cream needle sparks; return 0.35 s.
```

**C11 · Needle Shot (Desert, 50) (P1)**
- **Animation:** arms point forward (`jnt_arm`), recoil per shot.
- **VFX:** a volley of 5 thin cream needles (U12, straight, fast 0.2 s, stagger 0.06 s) with orange trails; they stick briefly into the target, then vanish.
- **Needs:** `Attack_NeedleShot`.
```
FreeAPet move C11 "Needle Shot" (RunningCactus). Follow docs/VFX-CATALOGUE.md §0. ["Needle Shot"]: clip Attack_NeedleShot (markers "shot" x5 optional). Fire 5 needle Parts (0.1x0.1x0.9, cream 240,230,200) from the arm tips with Common.Projectile (arc 0, 0.2 s, stagger 0.06 s, orange trail); the last calls ctx.impact(); needles stay stuck in the target for 0.5 s then fade.
```

**C12 · Thorn Storm (Desert, 85, 5 uses) (P1)**
- **Animation:** U15 charge (the pink flower glows bright and opens); it curls in, then bursts outward, arms flung wide.
- **VFX:** a radial burst of 24 needles that curve and converge on the target; a pink flash from the bloom; desert dust swirl; heavy shake.
- **Needs:** `Attack_ThornStorm`.
```
FreeAPet move C12 "Thorn Storm" (RunningCactus). Follow docs/VFX-CATALOGUE.md §0. ["Thorn Storm"]: Charge(pink 255,120,190, 0.6) centred on the flower bone; burst: 24 needle projectiles spawned in a ring around the cactus, each a Bezier curving to the target (0.35-0.5 s, random), orange trails; on the last ctx.impact() + Shake heavy + 20 sand dust particles swirling; pink PointLight flash from the flower.
```

### Ball Scorpion (Desert · 3.0 m · serrated pincers on `jnt_pinch`, tail arcing to a stinger, glowing amber seams)

**C13 · Pinch (Neutral, 55) (P1)**
- **Animation:** pincers raise and open wide (`jnt_pinch` open); a scuttle forward; a double snap; it scuttles back.
- **VFX:** two U13 slashes crossing (X shape) in amber; a white "snap" flash.
- **Needs:** `Attack_Pinch`.
```
FreeAPet move C13 "Pinch" (BallScorpion). Follow docs/VFX-CATALOGUE.md §0. ["Pinch"]: clip Attack_Pinch or procedural (raise 0.3 s, scuttle to 60% 0.2 s with small left-right wiggle); on impact ctx.impact() + Common.Slash(45, amber) and Common.Slash(-45, amber) 0.05 s apart + a white star flash; scuttle back 0.35 s.
```

**C14 · Sand Sting (Desert, 50) (P1)**
- **Animation:** the tail coils back over the body (`jnt_tail_*`); a lightning-fast strike down; the tail retracts.
- **VFX:** an amber streak along the strike; a sand geyser bursting up at the target's feet.
- **Needs:** `Attack_SandSting`.
```
FreeAPet move C14 "Sand Sting" (BallScorpion). Follow docs/VFX-CATALOGUE.md §0. ["Sand Sting"]: clip Attack_SandSting (impact marker) or procedural lean; a Trail on the stinger tip (amber); at impact ctx.impact() + a sand geyser at the target's feet: 30 sand particles (220,180,110) with upward speed 18-26 and gravity, plus Shockwave(small, Desert).
```

**C15 · Venom Tail (Desert, 85, 5 uses) (P1)**
- **Animation:** U15 charge (the amber seams and the stinger glow bright); the tail rises high, vibrating; a big overhead strike.
- **VFX:** the stinger drips glowing amber droplets during the charge; a huge amber splash + shockwave on impact; heavy shake. Purely visual: there is no poison status.
- **Needs:** `Attack_VenomTail`.
```
FreeAPet move C15 "Venom Tail" (BallScorpion). Follow docs/VFX-CATALOGUE.md §0. ["Venom Tail"]: Charge(amber 255,170,40, 0.6) with all amber-seam parts brightening (local Color lerp, restore after), droplet particles falling from the stinger; strike: clip Attack_VenomTail or procedural; ctx.impact() + amber splash (40 particles, gravity) + Shockwave(radius 7, Desert) + Shake heavy. No status effect (none exists).
```

### Sun Camel (Desert · 4.0 m · gold sunburst crown with a glowing sun disc, S-neck)

**C16 · Stomp (Neutral, 55) (P1)**
- **Animation:** rears up on its hind legs (front legs `jnt_arm` lifted, 0.4 s); slams down.
- **VFX:** U14 shockwave travelling along the ground to the target, with cracks; dust; medium shake.
- **Needs:** `Attack_Stomp`.
```
FreeAPet move C16 "Stomp" (SunCamel). Follow docs/VFX-CATALOGUE.md §0. ["Stomp"]: clip Attack_Stomp or procedural rear (tilt back 20°, 0.4 s) and slam (0.12 s); a ground shockwave that travels from the camel to the target (3 rings spawned along the line, 0.08 s apart), ctx.impact() when the last reaches the target + dust + Shake medium.
```

**C17 · Sun Beam (Desert, 50) (P1)**
- **Animation:** the head lifts, the crown faces the target (`jnt_head`/`jnt_neck2`); the beam fires; the neck sways back.
- **VFX:** the sun disc glows, then a warm golden Beam (with a white core) from the crown to the target for 0.35 s, and a hot flare on the target.
- **Needs:** `Attack_SunBeam`.
```
FreeAPet move C17 "Sun Beam" (SunCamel). Follow docs/VFX-CATALOGUE.md §0. ["Sun Beam"]: clip Attack_SunBeam (marker "fire"); crown disc PointLight 0→4 over 0.3 s; Beam from an attachment at the crown to the target centre: Width 0→1.6, gold 255,200,80 + white core Beam 0.5, LightEmission 1, TextureSpeed for flow, 0.35 s; ctx.impact() at mid-beam + a flare sprite on the target.
```

**C18 · Solar Flare (Desert, 85, 5 uses) (P1)**
- **Animation:** U15 long charge (the sun disc grows brighter, the rays rotate); the neck rears back; an eruption forward.
- **VFX:** a mini sun orb forms above the crown and fires as a big projectile (U12) to the target; it explodes with a screen-warm flash (ColorCorrection tint +warm 0.2 s), heat-shimmer ring and heavy shake.
- **Needs:** `Attack_SolarFlare`.
```
FreeAPet move C18 "Solar Flare" (SunCamel). Follow docs/VFX-CATALOGUE.md §0. ["Solar Flare"]: Charge(gold, 0.7) and grow a Neon ball (gold, 0→2.2 studs) above the crown with 16 rotating ray Parts; fire it with Common.Projectile (arc 2, 0.4 s, gold trail); on hit ctx.impact() + a big gold Shockwave + ColorCorrection TintColor warm for 0.2 s + Shake heavy + 30 ember particles.
```

### Starters (all Neutral) — moves decided 29 Oct 2026, not in `Config/Battle.luau` yet

The developer decided the attacks and their clips. Battle stats are still pending. Each clip has a `release` marker (where there is one) and an `impact` marker.

**Spoutle**
- **Jet Splash:** bows the head so the basin and its three jets (`jnt_spout`) point at the target, braces the front paws, and holds ~0.4 s "spraying" with small head pulses. Release = start of the hold, impact = middle of it.
- **Collar Star:** puffs the chest out (`jnt_chest`) to show the gold star medallion, a short shake, then a sharp chest thrust. Release = the thrust, impact 0.35 s later.
- **Fountain Geyser:** head straight up with the jets to the sky, a trembling charge (~0.6 s) with the tail drop raised, then slams both front paws down and dips the head. Impact on the slam, then a wet-dog shake back to Idle.

**Glimmouse**
- **Hop Kick:** crouches on the huge hind feet, a big hop forward, and both hind feet kick out together at the top (impact). Lands with the jerboa squash and hops back.
- **Crystal Chime:** sits up tall, the crystal ears (`jnt_ear`) spread and vibrate (~0.5 s), then snap forward. Release = the snap, impact 0.4 s later.
- **Gem Whip:** spins on its hind feet so the whip tail (`jnt_tail_1..4`) sweeps the gold crystal across the front. Impact when the crystal passes the front, then a smaller follow-through swing and back to Idle.

**Plazadillo**
- **Shell Roll:** tucks the head, legs and tail under the shell into a ball, rolls forward one full turn and bumps (impact), then uncurls and steps back.
- **Paving Slam:** rears on the hind legs, raises the gold digging claws (`jnt_arm`/`jnt_forearm`/`jnt_hand`), then slams them into the ground in front. Impact on the slam, then a heavy settle.
- **Emerald Pulse:** plants all four feet and lowers the head. The shell rises with a deep breath while the emerald (`jnt_crystal`) tilts forward (charge ~0.6 s, slight tremble), then a sharp forward body jolt. Release = the jolt, impact 0.4 s later, then a slow exhale back to Idle.

To implement each one, use this prompt:
```
FreeAPet starter moves. Follow docs/VFX-CATALOGUE.md §0. Add the 9 starter moves above to Config/Battle.luau (all Neutral; ask for the stats if they are still pending). Create Fx/Moves/Spoutle.luau, Glimmouse.luau and Plazadillo.luau. Each move plays its Attack_<Move> clip (markers release/impact) via Common.PlayClip, with a procedural fallback built from Common (Ray for water jets, Projectile for the star, Shockwave and Emit for the geyser and slabs, Charge for the strong moves). Each move calls ctx.impact() once.
```

## 3. What you still need to create (animations)

| Need | Count | Where it is used |
|---|---|---|
| `Attack_<Move>` clips for the 6 current creatures | 18 | C01–C18 (until then: procedural fallback) |
| Starter clips (moves decided, specs above) | 3 × 3 | Spoutle / Glimmouse / Plazadillo |
| Optional: `Hurt`, `Faint`, `Victory` per creature | up to 27 | U07/U17/U22 use procedural motion meanwhile |
| GLB export of the 9 v3 sheets (Idle/Walk included) | 9 | v3 models in the game |

Textures that would raise quality (optional, can be made with the scripts): a star flash, a leaf, a sand puff, a radial vignette and speed lines. Built-in Roblox particle textures are used until then.
