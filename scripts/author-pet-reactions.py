#!/usr/bin/env python3
"""Hand-authored reaction clips for the 27 original pets. Never edits an original GLB.

Clips are written as code on the real joints. All rest rotations are identity, so
axes are the pet's own: +X = its left, +Y = up, +Z = forward.
  pitch (+) leans forward / nods down, yaw (+) turns to its left, roll (+) tips to its right.
No scale channels: Bone.Transform is a CFrame, so weight comes from pose, not squash.

Output:
  <out>/luau/<SpeciesId>.luau   one module per species, all clips (5 original + 8 authored), 30 fps
  <out>/clip-index.json         what each module holds
  --glb DIR                     preview copies of the originals + authored clips, for Blender checks

Skeleton and clips are the same on all three stages, so one clip set serves Baby, Juvenile and Adult.

Usage: python3 -I scripts/author-pet-reactions.py [--glb DIR] [--species a,b] [--stages Adult,Baby] [--out DIR]
"""
import argparse, json, math, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PETS = ROOT / "Free a Pet Models-1/pets"
OUT = ROOT / "design/pets/v3-integration"
FPS = 30
STAGES = ["Baby", "Juvenile", "Adult"]
SLUGS = ["glimmouse", "plazadillo", "spoutle", "acorn_squirrel", "hopping_mushroom",
         "branch_deer", "running_cactus", "ball_scorpion", "sun_camel"]

# Metres to lift the settled pose so the lowest mesh rests on the floor, per variant and clip.
# Measured in Blender from the evaluated meshes (scripts in the reactions README).
GROUND_FILE = OUT / "ground-calibration.json"
GROUND = json.loads(GROUND_FILE.read_text()) if GROUND_FILE.exists() else {}
def ground_units(rig, clip):
    """The calibration, in the hips-height units Clip.t expects."""
    return GROUND.get(f"{rig.slug}/{rig.stage}", {}).get(clip, 0.0) / (rig.pos["jnt_hips"][1] * rig.k * STAGE_SCALE[rig.stage])

# ---------- curves ----------
def clamp01(x): return max(0.0, min(1.0, x))
EASE = {
    "lin": lambda u: u,
    "out": lambda u: 1 - (1 - u) ** 3,          # snaps then settles
    "in": lambda u: u * u,                      # falls
    "io": lambda u: u * u * (3 - 2 * u),
    "back": lambda u: 1 + 2.4 * (u - 1) ** 3 + 1.4 * (u - 1) ** 2,  # overshoots
}
def keys(*pts):
    """keys((t, value, ease_into_this_key), ...) -> f(t)"""
    pts = [p if len(p) == 3 else (p[0], p[1], "io") for p in pts]
    def f(t):
        if t <= pts[0][0]: return pts[0][1]
        for a, b in zip(pts, pts[1:]):
            if t <= b[0]:
                u = (t - a[0]) / max(b[0] - a[0], 1e-6)
                return a[1] + (b[1] - a[1]) * EASE[b[2]](clamp01(u))
        return pts[-1][1]
    return f
def wave(amp, period, phase=0.0, offset=0.0):
    """Loop-safe when the clip length is a whole number of periods."""
    return lambda t: offset + amp * math.sin(2 * math.pi * (t / period + phase))
def ring(t0, amp, freq=7.0, damp=7.0):
    """Damped overlap that starts at t0: tails, ears, antlers."""
    return lambda t: 0.0 if t < t0 else amp * math.exp(-damp * (t - t0)) * math.sin(2 * math.pi * freq * (t - t0))
def add(*fs): return lambda t: sum(f(t) for f in fs)
def scale(f, k): return lambda t: f(t) * k
def delay(f, dt): return lambda t: f(t - dt)
def const(v): return lambda t: v

# ---------- quaternions ----------
def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz)
def qaxis(axis, deg):
    h = math.radians(deg) / 2; s = math.sin(h)
    return (axis[0]*s, axis[1]*s, axis[2]*s, math.cos(h))
def qeuler(pitch, yaw, roll):
    return qmul(qmul(qaxis((0, 1, 0), yaw), qaxis((1, 0, 0), pitch)), qaxis((0, 0, 1), roll))

# ---------- GLB ----------
def read_glb(path):
    raw = path.read_bytes()
    size, _ = struct.unpack_from("<II", raw, 12)
    js = json.loads(raw[20:20 + size])
    off = 20 + size
    bsize, _ = struct.unpack_from("<II", raw, off)
    return js, bytearray(raw[off + 8:off + 8 + bsize])

def write_glb(path, js, bin_):
    while len(bin_) % 4: bin_ += b"\0"
    js["buffers"][0]["byteLength"] = len(bin_)
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    total = 12 + 8 + len(j) + 8 + len(bin_)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<II", len(j), 0x4E4F534A) + j
                     + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_))

class Rig:
    """Rest data for one variant, in metres after the rig's own scale."""
    def __init__(self, js):
        self.nodes = js["nodes"]
        joints = js["skins"][0]["joints"]
        self.index = {self.nodes[i]["name"]: i for i in joints}
        parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []): parent[c] = i
        self.parent = {self.nodes[i]["name"]: (self.nodes[parent[i]]["name"] if i in parent else None) for i in joints}
        all_parents = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []): all_parents[c] = i
        i = next(i for i, n in enumerate(self.nodes) if n.get("name") == "rig")
        self.k = 1.0
        while True:
            self.k *= self.nodes[i].get("scale", [1, 1, 1])[0]
            if i not in all_parents: break
            i = all_parents[i]
        self.pos = {}
        for name, i in self.index.items():
            n = self.nodes[i]
            assert not n.get("rotation") or abs(abs(n["rotation"][3]) - 1) < 1e-6, f"{name} has a rest rotation"
            t = n.get("translation", [0, 0, 0])
            p = self.parent[name]
            # hips sit directly under the rig; every joint here has unit scale
            base = self.pos[p] if p in self.pos else (0.0, 0.0, 0.0)
            self.pos[name] = tuple(base[a] + t[a] for a in range(3))
    def has(self, j): return j in self.index
    def height(self):
        return self.pos["jnt_hips"][1] * self.k

# ---------- clip builder ----------
class Clip:
    def __init__(self, rig, dur, loop=False):
        self.rig, self.dur, self.loop = rig, dur, loop
        self.rot, self.tr = {}, {}
    def r(self, joint, pitch=None, yaw=None, roll=None):
        if not self.rig.has(joint): return self
        s = self.rot.setdefault(joint, {})
        for k, f in (("pitch", pitch), ("yaw", yaw), ("roll", roll)):
            if f is None: continue
            f = f if callable(f) else const(f)
            s[k] = add(s[k], f) if k in s else f
        return self
    def lr(self, base, pitch=None, yaw=None, roll=None):
        """Mirror a pose onto _L and _R: yaw and roll flip sign."""
        flip = lambda f: None if f is None else (scale(f, -1) if callable(f) else -f)
        self.r(base + "_L", pitch, yaw, roll); self.r(base + "_R", pitch, flip(yaw), flip(roll))
        return self
    def t(self, joint, x=None, y=None, z=None):
        """Translation in units of hips height, so one recipe fits every stage."""
        if not self.rig.has(joint): return self
        s = self.tr.setdefault(joint, {})
        for k, f in (("x", x), ("y", y), ("z", z)):
            if f is None: continue
            f = f if callable(f) else const(f)
            s[k] = add(s[k], f) if k in s else f
        return self
    def chain(self, joints, pitch=None, yaw=None, roll=None, lag=0.05, gain=1.0):
        """Overlap down a chain: every link follows late and a little harder."""
        for i, j in enumerate(joints):
            g = gain ** i
            mk = lambda f: None if f is None else scale(delay(f, lag * i), g)
            self.r(j, mk(pitch), mk(yaw), mk(roll))
        return self
    def sample(self, joint, t):
        s = self.rot.get(joint, {})
        return tuple(s[k](t) if k in s else 0.0 for k in ("pitch", "yaw", "roll"))
    def bake(self):
        frames = int(round(self.dur * FPS)) + 1
        times = [i / FPS for i in range(frames)]
        out = {}
        h = self.rig.pos["jnt_hips"][1]  # rig units
        for j in set(self.rot) | set(self.tr):
            q = [qeuler(*self.sample(j, t)) for t in times] if j in self.rot else None
            tv = None
            if j in self.tr:
                s = self.tr[j]
                tv = [tuple((s[k](t) if k in s else 0.0) * h for k in ("x", "y", "z")) for t in times]
            out[j] = {"q": q, "t": tv}
        return times, out

def pin_feet(c, hips_y=None, hips_z=None, hips_pitch=None, chest_pitch=None):
    """Keep grounded feet still while the body dips: 2-bone IK in the side plane.
    Adds to whatever the leg joints already do, so call it after the body is posed."""
    rig = c.rig
    h = rig.pos["jnt_hips"][1]
    hy, hz = hips_y or const(0), hips_z or const(0)
    hp = hips_pitch or const(0)
    cp = chest_pitch or const(0)
    def solve(upper, lower, ankle, front):
        if not (rig.has(upper) and rig.has(lower) and rig.has(ankle)): return
        H = rig.pos[upper]; K = rig.pos[lower]; A = rig.pos[ankle]
        hips = rig.pos["jnt_hips"]
        l1 = math.hypot(K[1]-H[1], K[2]-H[2]); l2 = math.hypot(A[1]-K[1], A[2]-K[2])
        rest_u = math.atan2(K[2]-H[2], -(K[1]-H[1]))
        rest_l = math.atan2(A[2]-K[2], -(A[1]-K[1]))
        bend = 1 if (rest_l - rest_u) >= 0 else -1
        def angles(t):
            a = math.radians(hp(t) + (cp(t) if front else 0))
            # where this hip ends up after the body moves (rotation about the hips joint)
            ry, rz = H[1]-hips[1], H[2]-hips[2]
            ny = ry*math.cos(a) - rz*math.sin(a); nz = ry*math.sin(a) + rz*math.cos(a)
            hy_ = hips[1] + ny + hy(t)*h; hz_ = hips[2] + nz + hz(t)*h
            dy, dz = A[1]-hy_, A[2]-hz_
            d = min(max(math.hypot(dy, dz), abs(l1-l2)+1e-4), l1+l2-1e-4)
            base = math.atan2(dz, -dy)
            cu = clamp(((l1*l1 + d*d - l2*l2) / (2*l1*d)))
            cl = clamp(((l1*l1 + l2*l2 - d*d) / (2*l1*l2)))
            au = base - bend*math.acos(cu)
            al = au + bend*(math.pi - math.acos(cl))
            # world angle of each bone -> local delta; a +X rotation swings a hanging bone backward
            du = math.degrees(rest_u - au) - hp(t) - (cp(t) if front else 0)
            dl = math.degrees((rest_l - al) - (rest_u - au))
            return du, dl
        c.r(upper, pitch=lambda t: angles(t)[0])
        c.r(lower, pitch=lambda t: angles(t)[1])
        c.r(ankle, pitch=lambda t: -sum(angles(t)) - hp(t) - (cp(t) if front else 0))
    for side in ("L", "R"):
        solve(f"jnt_leg_{side}", f"jnt_shin_{side}", f"jnt_foot_{side}", False)
        solve(f"jnt_arm_{side}", f"jnt_forearm_{side}", f"jnt_hand_{side}", True)
def clamp(x): return max(-1.0, min(1.0, x))

# ---------- shared gestures ----------
TAILS = {"glimmouse": 4, "plazadillo": 3, "spoutle": 4, "acorn_squirrel": 4, "branch_deer": 1, "ball_scorpion": 4, "sun_camel": 2}
def tail(slug): return [f"jnt_tail_{i+1}" for i in range(TAILS.get(slug, 0))]
QUAD = {"plazadillo", "spoutle", "branch_deer", "sun_camel"}
def spine(c): return [j for j in ("jnt_chest", "jnt_neck", "jnt_neck2", "jnt_head") if c.rig.has(j)]

def grounded(c, slug, hy=None, hz=None, hp=None, cp=None):
    if slug == "ball_scorpion": return  # low splayed legs: posed by hand below
    if slug in QUAD or c.rig.has("jnt_shin_L"):
        pin_feet(c, hy, hz, hp, cp)

# ---------- BattleIdle: ready stance, weight rocking, eyes on the foe ----------
BATTLE = {  # dip (hips height), period, lean (deg), head counter, voice
    "glimmouse": dict(dip=.05, per=.8, lean=9, sway=4),          # jittery on tiptoe
    "plazadillo": dict(dip=.03, per=1.6, lean=4, sway=2),        # planted, unbothered
    "spoutle": dict(dip=.07, per=1.2, lean=10, sway=3),          # coiled guard dog
    "acorn_squirrel": dict(dip=.05, per=.8, lean=8, sway=5),     # twitchy, acorn clutched
    "hopping_mushroom": dict(dip=.09, per=.8, lean=6, sway=3),   # always about to hop
    "branch_deer": dict(dip=.025, per=1.6, lean=5, sway=2),      # poised
    "running_cactus": dict(dip=.05, per=.6, lean=6, sway=6),     # panicked jog on the spot
    "ball_scorpion": dict(dip=.015, per=1.2, lean=1, sway=.7),     # low, tail cocked
    "sun_camel": dict(dip=.02, per=1.6, lean=3, sway=2),         # aloof
}
def battle_idle(rig, slug):
    b = BATTLE[slug]; per = b["per"]; dur = per * round(1.6 / per)
    c = Clip(rig, dur, loop=True)
    hy = wave(b["dip"] * .3, per, .25, -b["dip"])
    hp = wave(1.5, per, .25, b["lean"] * .5)
    sway = wave(b["sway"], per * 2 if round(1.6 / per) % 2 == 0 else per)
    c.t("jnt_hips", y=hy); c.r("jnt_hips", pitch=hp, roll=sway)
    sp = spine(c)
    for i, j in enumerate(sp[:-1]):
        c.r(j, pitch=wave(1.2, per, .25 - .08 * (i + 1), b["lean"] * .35))
    chest = wave(1.2, per, .25 - .08, b["lean"] * .35)
    c.r("jnt_head", pitch=wave(1.5, per, .05, -b["lean"] * .6), roll=scale(sway, -.8))
    c.chain(tail(slug), pitch=wave(4, per, .1, -4), yaw=wave(7, per), lag=.04)
    c.lr("jnt_ear", pitch=wave(3, per, .15), roll=wave(2, per, .3))
    grounded(c, slug, hy=hy, hp=hp, cp=chest)
    if slug == "glimmouse":
        c.lr("jnt_arm", pitch=wave(6, per, .2, -28), roll=const(-8))   # fists up
        c.lr("jnt_ear", yaw=wave(5, per / 2))                           # ears on edge
    if slug == "plazadillo":
        c.r("jnt_crystal", roll=wave(2.5, per)); c.r("jnt_head", pitch=const(4))
    if slug == "spoutle":
        c.r("jnt_spout", pitch=wave(4, per, .4), roll=wave(5, per))
    if slug == "acorn_squirrel":
        c.lr("jnt_arm", pitch=wave(4, per, .2)); c.r("jnt_acorn", pitch=wave(6, per, .3))
    if slug == "hopping_mushroom":
        c.r("jnt_cap", pitch=wave(4, per, .35), roll=wave(3, per))
        c.lr("jnt_baby", pitch=wave(10, per, .45), roll=wave(8, per, .2))
        c.lr("jnt_arm", pitch=wave(10, per, .2, -14))
    if slug == "branch_deer":
        c.r("jnt_antler", pitch=wave(1.5, per, .3))
    if slug == "running_cactus":
        c.r("jnt_arm_L", pitch=wave(22, per), roll=const(-6)); c.r("jnt_arm_R", pitch=wave(22, per, .5), roll=const(6))
        c.r("jnt_flower", roll=wave(8, per, .3), pitch=wave(5, per, .2))
    if slug == "ball_scorpion":
        c.lr("jnt_arm", yaw=wave(5, per, .1, 10), pitch=wave(3, per))
        c.lr("jnt_pinch", yaw=wave(14, per / 2, 0, -8))
        c.chain(tail(slug), pitch=wave(5, per, .1, 2), lag=.05)
        for n in (1, 2, 3):
            c.lr(f"jnt_leg{n}", roll=wave(2.5, per, .1 * n)); c.lr(f"jnt_knee{n}", roll=wave(2, per, .1 * n + .1))
    if slug == "sun_camel":
        c.r("jnt_neck2", pitch=wave(2, per, .1, -4)); c.r("jnt_head", yaw=const(10))  # side-eye
    return c

# ---------- Hit: instant snap back, spring home. Reads inside 0.4 s ----------
HIT = {"glimmouse": 1.25, "plazadillo": .45, "spoutle": .85, "acorn_squirrel": 1.1, "hopping_mushroom": 1.2,
       "branch_deer": .8, "running_cactus": 1.1, "ball_scorpion": .75, "sun_camel": .7}
def hit(rig, slug):
    g = HIT[slug]; dur = .45; c = Clip(rig, dur)
    env = keys((0, 0), (.05, 1, "out"), (.14, .85), (.45, 0, "io"))
    hp = scale(env, -14 * g); hz = scale(env, -.1 * g); hy = scale(env, -.07 * g)
    c.t("jnt_hips", y=hy, z=hz); c.r("jnt_hips", pitch=hp)
    for j in spine(c)[:-1]:
        c.r(j, pitch=scale(delay(env, .02), -9 * g))
    c.r("jnt_head", pitch=scale(delay(env, .03), -20 * g), roll=scale(delay(env, .03), 8 * g))
    c.chain(tail(slug), pitch=ring(.04, 22 * g, 5, 7), lag=.03)
    c.lr("jnt_ear", pitch=ring(.03, -20 * g, 6, 8), roll=ring(.03, 14 * g, 6, 8))
    grounded(c, slug, hy=hy, hz=hz, hp=hp)
    if slug == "glimmouse":
        c.lr("jnt_ear", pitch=scale(env, -34)); c.lr("jnt_arm", pitch=scale(env, -40))  # ears pin back
    if slug == "plazadillo":
        c.r("jnt_head", pitch=scale(env, 34)); c.r("jnt_crystal", pitch=ring(.03, 16, 6, 9))  # head tucks into the shell
    if slug == "spoutle":
        c.r("jnt_spout", pitch=ring(.03, -24, 7, 8), roll=ring(.05, 18, 7, 8))
    if slug == "acorn_squirrel":
        c.lr("jnt_forearm", pitch=scale(env, -18)); c.r("jnt_acorn", pitch=ring(.04, -24, 7, 8))  # hugs the acorn tighter
    if slug == "hopping_mushroom":
        c.r("jnt_cap", pitch=add(scale(env, 16), ring(.06, -20, 6, 7)))  # cap slips over its eyes
        c.lr("jnt_baby", pitch=ring(.04, -34, 7, 7), roll=ring(.04, 22, 7, 7)); c.lr("jnt_arm", pitch=scale(env, -50))
    if slug == "branch_deer":
        c.r("jnt_antler", pitch=ring(.03, -8, 7, 8), roll=ring(.03, 5, 7, 8))
    if slug == "running_cactus":
        c.lr("jnt_arm", roll=scale(env, -30), pitch=scale(env, -24))
        c.lr("jnt_forearm", pitch=ring(.04, 26, 6, 7)); c.r("jnt_flower", pitch=ring(.02, -38, 7, 7), roll=ring(.04, 24, 7, 7))
    if slug == "ball_scorpion":
        c.lr("jnt_arm", yaw=scale(env, 22)); c.lr("jnt_pinch", yaw=scale(env, 22))
        c.chain(tail(slug), pitch=ring(.02, -24, 5, 7), lag=.04)
        for n in (1, 2, 3): c.lr(f"jnt_leg{n}", roll=scale(env, 12))
    if slug == "sun_camel":
        c.r("jnt_neck", pitch=scale(env, -16)); c.r("jnt_neck2", pitch=scale(env, 24)); c.r("jnt_head", yaw=scale(env, -20))  # offended recoil
    return c

# ---------- Faint: a little story, then hold the last pose ----------
def faint(rig, slug):
    dur = 1.2 if slug not in ("branch_deer", "sun_camel") else 1.5
    c = Clip(rig, dur)
    T = dur / 1.2
    sideways = slug not in ("hopping_mushroom", "plazadillo", "ball_scorpion", "running_cactus")
    fall = keys((0, 0), (.3 * T, 0), (.85 * T, 1, "in"), (.95 * T, .94, "out"), (1.05 * T, 1, "in"))
    wob = keys((0, 0), (.12 * T, 1, "out"), (.3 * T, -.6), (.45 * T, 0))
    h = rig.pos["jnt_hips"][1]
    # drop the hips to about the body's thickness above the floor
    drop = -.62 if slug != "ball_scorpion" else -.5
    if slug in ("branch_deer", "sun_camel"): drop = -.72
    c.t("jnt_hips", y=scale(fall, drop + ground_units(rig, "Faint")))
    c.r("jnt_hips", roll=scale(wob, 6))
    c.r("jnt_head", yaw=scale(wob, 16), pitch=scale(wob, 8))
    if sideways:
        c.r("jnt_hips", roll=scale(fall, 78))
        c.lr("jnt_leg", pitch=scale(fall, -24)); c.lr("jnt_shin", pitch=scale(fall, 28))
        c.lr("jnt_arm", pitch=scale(fall, -30)); c.lr("jnt_forearm", pitch=scale(fall, 30))
        c.chain(tail(slug), roll=scale(fall, 14), pitch=scale(fall, 14), lag=.05)
        c.r("jnt_head", roll=scale(fall, 12), pitch=scale(fall, 10))
    if slug in ("branch_deer", "sun_camel"):
        for j in ("jnt_neck", "jnt_neck2"): c.r(j, pitch=scale(fall, 24), roll=scale(fall, -8))
    c.lr("jnt_ear", pitch=scale(fall, -30), roll=scale(fall, 18))
    if slug == "glimmouse":
        c.lr("jnt_ear", pitch=ring(.85 * T, 22, 4, 4), roll=scale(fall, 26))
        c.chain(tail(slug), yaw=keys((0, 0), (1.0 * T, 18), (1.2 * T, 4)), lag=.05)
    if slug == "plazadillo":
        # plops flat on its belly, chin on the floor, legs splayed: the shell stays proud
        c.r("jnt_head", pitch=scale(fall, 24))
        c.chain(tail(slug), pitch=scale(fall, 20), lag=.03)
        c.lr("jnt_leg", roll=scale(fall, 74), pitch=scale(fall, -8)); c.lr("jnt_shin", pitch=scale(fall, 16))
        c.lr("jnt_arm", roll=scale(fall, 74), pitch=scale(fall, 10)); c.lr("jnt_forearm", pitch=scale(fall, -14))
        c.r("jnt_crystal", roll=add(scale(fall, 9), ring(.9 * T, 14, 5, 5)))
    if slug == "spoutle":
        c.r("jnt_spout", pitch=scale(fall, 26), roll=add(scale(fall, -14), ring(.95 * T, 16, 5, 6)))
    if slug == "acorn_squirrel":
        # lets go of the acorn at last: the arms open and it stays by its chest
        c.lr("jnt_arm", pitch=keys((0, 0), (.3 * T, -24), (1.0 * T, -6)), roll=scale(fall, -30))
        c.r("jnt_acorn", pitch=scale(fall, 40))
    if slug == "hopping_mushroom":
        # forward flop, cap down over everything, babies droop
        c.r("jnt_hips", pitch=scale(fall, 76))
        c.r("jnt_cap", pitch=add(scale(fall, 18), ring(.95 * T, 12, 5, 6)))
        c.lr("jnt_baby", pitch=scale(fall, 48), roll=scale(fall, 26))
        c.lr("jnt_arm", pitch=scale(fall, -64), roll=scale(fall, -26))
        c.lr("jnt_leg", pitch=scale(fall, -60)); c.lr("jnt_shin", pitch=scale(fall, 20))
    if slug == "running_cactus":
        # timber: falls back flat with the arms still up
        c.r("jnt_hips", pitch=scale(fall, -82))
        c.lr("jnt_leg", pitch=scale(fall, 64)); c.lr("jnt_shin", pitch=scale(fall, -24))
        c.lr("jnt_arm", roll=scale(fall, -14)); c.lr("jnt_forearm", pitch=scale(fall, 18))
        c.r("jnt_flower", pitch=add(scale(fall, 60), ring(.95 * T, 18, 5, 6)))
    if slug == "ball_scorpion":
        # flips nothing: legs fold in, tail goes limp
        c.chain(tail(slug), pitch=scale(fall, 34), lag=.04)
        c.lr("jnt_arm", yaw=scale(fall, -18), pitch=scale(fall, 20)); c.lr("jnt_pinch", yaw=scale(fall, 28))
        for n in (1, 2, 3):
            c.lr(f"jnt_leg{n}", roll=scale(fall, 26)); c.lr(f"jnt_knee{n}", roll=scale(fall, -22))
    if slug == "branch_deer":
        c.r("jnt_antler", roll=ring(.95 * T, 5, 5, 6))
    return c

# ---------- Happy: everyone celebrates in their own way, 1 s ----------
def happy(rig, slug):
    dur = 1.0 if slug not in ("sun_camel", "branch_deer", "plazadillo") else 1.2
    c = Clip(rig, dur)
    hops = {"glimmouse": 3, "hopping_mushroom": 2, "running_cactus": 2, "acorn_squirrel": 2, "spoutle": 2,
            "plazadillo": 1, "ball_scorpion": 2, "branch_deer": 1, "sun_camel": 1}[slug]
    height = {"glimmouse": .55, "hopping_mushroom": .9, "running_cactus": .3, "acorn_squirrel": .35, "spoutle": .28,
              "plazadillo": .1, "ball_scorpion": .22, "branch_deer": .14, "sun_camel": .06}[slug]
    def jump(t):
        p = (t / dur) * hops
        if p >= hops: return 0.0
        u = p % 1.0
        return height * 4 * u * (1 - u)
    c.t("jnt_hips", y=jump)
    c.r("jnt_hips", pitch=lambda t: -6 * (jump(t) / max(height, 1e-6)))
    c.r("jnt_head", pitch=lambda t: -10 * (jump(t) / max(height, 1e-6)))
    tuck = lambda t: jump(t) / max(height, 1e-6)
    c.lr("jnt_leg", pitch=lambda t: -22 * tuck(t)); c.lr("jnt_shin", pitch=lambda t: 26 * tuck(t))
    c.lr("jnt_ear", pitch=lambda t: 18 * math.sin(2 * math.pi * hops * t / dur), roll=lambda t: 10 * tuck(t))
    wag = wave(24, dur / max(hops * 2, 2))
    c.chain(tail(slug), yaw=wag, lag=.03)
    if slug == "glimmouse":
        c.lr("jnt_arm", pitch=lambda t: -70 * tuck(t) - 12, roll=const(-16))
        c.lr("jnt_ear", yaw=wave(10, dur / 3)); c.r("jnt_head", roll=wave(8, dur / 1.5))
    if slug == "plazadillo":
        # slow proud nod and the emerald flashes up
        c.r("jnt_head", pitch=keys((0, 0), (.3, -18), (.6, 12), (.9, -6), (1.2, 0)))
        c.r("jnt_crystal", yaw=keys((0, 0), (1.2, 360), ), pitch=keys((0, 0), (.3, -8), (.9, -8), (1.2, 0)))
        c.chain(tail(slug), yaw=wave(12, .6), lag=.05)
    if slug == "spoutle":
        c.r("jnt_chest", pitch=keys((0, 0), (.2, -18), (.8, -14), (1, 0)))   # chest out, star on show
        c.r("jnt_spout", pitch=wave(10, .25), roll=wave(12, .5))
        c.r("jnt_head", yaw=wave(14, .5))
    if slug == "acorn_squirrel":
        c.r("jnt_acorn", pitch=keys((0, 0), (.25, -40), (.5, 0), (.75, -40), (1, 0)))  # kisses the acorn
        c.r("jnt_head", pitch=keys((0, 0), (.25, 24), (.5, -6), (.75, 24), (1, 0)))
    if slug == "hopping_mushroom":
        c.r("jnt_cap", pitch=lambda t: 14 * math.sin(2 * math.pi * hops * t / dur), roll=wave(6, .5))
        c.lr("jnt_baby", pitch=wave(30, .25), roll=wave(20, .5)); c.lr("jnt_arm", pitch=lambda t: -80 * tuck(t) - 10)
    if slug == "branch_deer":
        c.r("jnt_neck", pitch=keys((0, 0), (.4, -22), (.9, -18), (1.2, 0)))
        c.r("jnt_head", pitch=keys((0, 0), (.4, 12), (.7, -14), (1.2, 0)))
        c.r("jnt_antler", roll=ring(.45, 7, 4, 3))
        c.lr("jnt_arm", pitch=lambda t: -34 * tuck(t)); c.lr("jnt_forearm", pitch=lambda t: 50 * tuck(t))
    if slug == "running_cactus":
        c.lr("jnt_arm", roll=keys((0, 0), (.2, -46), (.4, -20), (.6, -46), (.8, -20), (1, 0)))
        c.lr("jnt_forearm", pitch=wave(18, .4)); c.r("jnt_flower", pitch=wave(18, .25), roll=wave(14, .5))
        c.r("jnt_hips", yaw=keys((0, 0), (.5, 180), (1, 360)))  # a spin of pure relief
    if slug == "ball_scorpion":
        c.lr("jnt_arm", yaw=wave(16, .5), pitch=keys((0, 0), (.2, -30), (.8, -30), (1, 0)))
        c.lr("jnt_pinch", yaw=wave(30, .2, 0, -10))  # clack clack
        c.chain(tail(slug), pitch=wave(14, .5), lag=.05)
        for n in (1, 2, 3): c.lr(f"jnt_leg{n}", roll=lambda t, n=n: -14 * tuck(t))
    if slug == "sun_camel":
        # the most it will ever give you: closes its eyes, lifts its chin, sways
        c.r("jnt_neck", pitch=keys((0, 0), (.4, -14), (.9, -14), (1.2, 0)))
        c.r("jnt_neck2", pitch=keys((0, 0), (.4, -8), (.9, -8), (1.2, 0)), roll=wave(7, .6))
        c.r("jnt_head", pitch=keys((0, 0), (.4, -16), (.9, -16), (1.2, 0)), yaw=wave(6, .6))
    return c

# ---------- Fidget: the signature tell, played rarely while standing ----------
def fidget(rig, slug):
    if slug == "glimmouse":
        # hears something: ears swivel, a nervous look left and right, then the tail tip flicks
        c = Clip(rig, 2.2)
        c.r("jnt_head", yaw=keys((0, 0), (.3, 0), (.5, 30, "out"), (1.0, 30), (1.2, -30, "out"), (1.7, -30), (2.2, 0)), pitch=keys((0, 0), (.2, -8), (1.8, -8), (2.2, 0)))
        c.r("jnt_ear_L", yaw=keys((0, 0), (.25, 30, "out"), (1.0, 30), (1.2, -10), (2.2, 0)))
        c.r("jnt_ear_R", yaw=keys((0, 0), (.25, 10, "out"), (1.0, 10), (1.2, -30), (2.2, 0)))
        c.chain(tail(slug), yaw=add(ring(.5, 22, 3, 2.5), ring(1.2, -22, 3, 2.5)), lag=.05)
        c.lr("jnt_arm", pitch=keys((0, 0), (.3, -36), (1.9, -36), (2.2, 0)))
    elif slug == "plazadillo":
        # very slowly sniffs the ground, gives one satisfied nod, the emerald tilts
        c = Clip(rig, 3.0)
        hp = keys((0, 0), (1.0, 3), (2.2, 3), (3.0, 0))
        c.r("jnt_hips", pitch=hp); c.r("jnt_head", pitch=keys((0, 0), (1.0, 12), (1.5, 7), (1.8, 13), (2.2, 4), (3.0, 0)), yaw=wave(5, 1.5))
        c.r("jnt_crystal", roll=keys((0, 0), (1.0, 9), (2.2, -6), (3.0, 0)))
        c.chain(tail(slug), yaw=wave(8, 1.5), lag=.1)
        grounded(c, slug, hp=hp)
    elif slug == "spoutle":
        # guard-dog puff: chest out, a look round its plaza, spout shake like a wet dog
        c = Clip(rig, 2.4)
        cp = keys((0, 0), (.4, -16, "back"), (1.5, -16), (1.9, 0))
        c.r("jnt_chest", pitch=cp); c.r("jnt_head", yaw=keys((0, 0), (.5, 0), (.8, 24), (1.2, -24), (1.5, 0)), pitch=keys((0, 0), (.4, 10), (1.5, 10), (1.9, 0)))
        shake = lambda t: 0.0 if t < 1.7 else 16 * math.exp(-5 * (t - 1.7)) * math.sin(2 * math.pi * 7 * (t - 1.7))
        c.r("jnt_head", roll=shake); c.r("jnt_spout", roll=delay(shake, .03))
        c.lr("jnt_ear", roll=delay(shake, .05))
        c.chain(tail(slug), yaw=add(wave(16, .4), const(0)), lag=.04)
        c.r("jnt_hips", roll=scale(shake, -.4))
    elif slug == "acorn_squirrel":
        # checks the acorn is still there, glares round in case anyone saw, hugs it
        c = Clip(rig, 2.4)
        c.r("jnt_head", pitch=keys((0, 0), (.3, 30), (.9, 30), (1.1, -4), (2.4, 0)), yaw=keys((0, 0), (1.1, 0), (1.3, 28, "out"), (1.6, 28), (1.8, -28, "out"), (2.1, -28), (2.4, 0)))
        c.r("jnt_acorn", pitch=keys((0, 0), (.3, -18), (.9, -18), (1.1, 8), (1.8, 8), (2.4, 0)), roll=keys((0, 0), (.45, 12), (.6, -12), (.75, 12), (.9, 0)))
        c.lr("jnt_forearm", pitch=keys((0, 0), (1.1, 0), (1.3, -14, "out"), (2.1, -14), (2.4, 0)))
        c.chain(tail(slug), pitch=ring(1.1, 18, 4, 3), lag=.05)
    elif slug == "hopping_mushroom":
        # a furious little stomp, one foot then the other, cap bouncing
        c = Clip(rig, 1.8)
        stomp = lambda a: keys((0, 0), (a, 0), (a + .14, -48, "out"), (a + .24, 0, "in"), (1.8, 0))
        c.r("jnt_leg_L", pitch=stomp(.2)); c.r("jnt_shin_L", pitch=scale(stomp(.2), -1.1))
        c.r("jnt_leg_R", pitch=stomp(.75)); c.r("jnt_shin_R", pitch=scale(stomp(.75), -1.1))
        c.r("jnt_hips", roll=keys((0, 0), (.3, -8), (.5, 0), (.85, 8), (1.05, 0)))
        c.r("jnt_cap", pitch=add(ring(.44, 12, 6, 6), ring(.99, 12, 6, 6)), roll=add(ring(.44, -8, 6, 6), ring(.99, 8, 6, 6)))
        c.lr("jnt_baby", pitch=add(ring(.46, 26, 7, 6), ring(1.01, 26, 7, 6)))
        c.lr("jnt_arm", pitch=keys((0, 0), (.2, -30), (1.2, -30), (1.8, 0)))
    elif slug == "branch_deer":
        # lifts its head, turns to listen, a slow antler sweep, ear flick: nobility
        c = Clip(rig, 3.0)
        c.r("jnt_neck", pitch=keys((0, 0), (.8, -14), (2.2, -14), (3.0, 0)))
        c.r("jnt_head", yaw=keys((0, 0), (.8, 0), (1.5, 30), (2.2, 30), (3.0, 0)), pitch=keys((0, 0), (.8, 8), (2.2, 8), (3.0, 0)))
        c.r("jnt_antler", roll=keys((0, 0), (1.5, 3), (3.0, 0)))
        c.r("jnt_ear_L", pitch=add(ring(.5, 22, 6, 7), ring(1.9, 22, 6, 7)))
        c.r("jnt_tail_1", yaw=ring(1.2, 14, 5, 4))
    elif slug == "running_cactus":
        # suddenly remembers it is late: startled jump, looks both ways, checks its flower
        c = Clip(rig, 2.0)
        j = keys((0, 0), (.15, -.06), (.3, .35, "out"), (.5, 0, "in"), (2.0, 0))
        c.t("jnt_hips", y=j)
        c.lr("jnt_arm", roll=keys((0, 0), (.3, -40, "out"), (.8, -12), (2.0, 0)), pitch=ring(.3, 22, 5, 4))
        c.r("jnt_head", yaw=keys((0, 0), (.6, 0), (.75, 34, "out"), (1.05, 34), (1.2, -34, "out"), (1.5, -34), (1.8, 0)))
        c.r("jnt_flower", pitch=ring(.3, -34, 6, 5), roll=ring(.5, 20, 6, 5))
        c.lr("jnt_leg", pitch=lambda t: -28 * max(j(t), 0) / .35); c.lr("jnt_shin", pitch=lambda t: 30 * max(j(t), 0) / .35)
    elif slug == "ball_scorpion":
        # clack clack, tail cocks and taps, a sideways shuffle of suspicion
        c = Clip(rig, 2.0)
        c.lr("jnt_pinch", yaw=keys((0, 0), (.2, 0), (.3, -24), (.4, 10), (.5, -24), (.6, 10), (.7, 0), (2.0, 0)))
        c.lr("jnt_arm", yaw=keys((0, 0), (.2, 14), (.7, 14), (1.0, 0)), pitch=keys((0, 0), (.2, -18), (.7, -18), (1.0, 0)))
        c.chain(tail(slug), pitch=keys((0, 0), (.8, 0), (1.1, -14), (1.25, 8, "out"), (1.4, -14), (1.55, 8, "out"), (2.0, 0)), lag=.03)
        c.r("jnt_hips", yaw=keys((0, 0), (1.0, 0), (1.3, 14), (1.7, 14), (2.0, 0)))
        for n, ph in ((1, 0), (2, .08), (3, .16)):
            step = lambda t, ph=ph: 12 * math.sin(2 * math.pi * 3 * (t - ph)) if 1.0 + ph <= t < 1.67 + ph else 0.0
            c.r(f"jnt_leg{n}_L", roll=step); c.r(f"jnt_leg{n}_R", roll=lambda t, s=step: -s(t + .16))
    else:  # sun_camel
        # chews, slowly, and gives you the side-eye. Then a long-suffering blink of a head tilt
        c = Clip(rig, 3.2)
        chew = lambda t: 5 * math.sin(2 * math.pi * 2.5 * t) if .3 < t < 2.5 else 0.0
        c.r("jnt_head", yaw=keys((0, 0), (.8, 0), (1.3, 26), (2.5, 26), (3.2, 0)), roll=add(chew, keys((0, 0), (1.3, 6), (2.5, 6), (3.2, 0))))
        c.r("jnt_neck2", pitch=keys((0, 0), (1.0, -6), (2.5, -6), (3.2, 0)), yaw=keys((0, 0), (1.3, 8), (2.5, 8), (3.2, 0)))
        c.lr("jnt_ear", pitch=ring(1.9, 16, 5, 5))
        c.chain(tail(slug), yaw=wave(10, 1.6), lag=.1)
    return c

# ---------- Sleep: low, slow, only breathing ----------
def sleep(rig, slug):
    c = Clip(rig, 3.2, loop=True)
    br = wave(1.0, 3.2)
    settled = const(1)
    drop = {"glimmouse": -.55, "plazadillo": -.6, "spoutle": -.55, "acorn_squirrel": -.5, "hopping_mushroom": -.5,
            "branch_deer": -.68, "running_cactus": -.42, "ball_scorpion": -.55, "sun_camel": -.68}[slug]
    lift = ground_units(rig, "Sleep")
    hy = lambda t: drop + lift + .012 * br(t)
    c.t("jnt_hips", y=hy)
    c.r("jnt_hips", pitch=const(4))
    for j in spine(c)[:-1]: c.r(j, pitch=lambda t: 3 + 1.2 * br(t))
    c.r("jnt_head", pitch=lambda t: 22 + 2.5 * br(t))
    c.chain(tail(slug), pitch=const(10), yaw=const(16), lag=0)
    c.lr("jnt_ear", pitch=const(-22), roll=const(14))
    grounded(c, slug, hy=hy, hp=const(4))
    if slug == "hopping_mushroom":
        c.r("jnt_cap", pitch=lambda t: 10 + 1.5 * br(t)); c.lr("jnt_baby", pitch=const(28), roll=const(16))
    if slug == "running_cactus":
        c.r("jnt_flower", pitch=const(40)); c.lr("jnt_arm", roll=const(26))
    if slug == "plazadillo":
        c.r("jnt_head", pitch=const(-8)); c.chain(tail(slug), pitch=const(24), lag=0)
    if slug == "ball_scorpion":
        c.chain(tail(slug), pitch=const(20), lag=0); c.lr("jnt_arm", yaw=const(-14))
        for n in (1, 2, 3):
            c.lr(f"jnt_leg{n}", roll=const(22)); c.lr(f"jnt_knee{n}", roll=const(-20))
    return c

# ---------- Carried: hanging limp but looking round ----------
def carried(rig, slug):
    c = Clip(rig, 2.4, loop=True)
    c.r("jnt_hips", pitch=wave(2, 1.2))
    c.r("jnt_head", yaw=wave(18, 2.4), pitch=wave(4, 1.2, .2))
    c.lr("jnt_leg", pitch=wave(8, 1.2, 0, 14)); c.lr("jnt_shin", pitch=wave(6, 1.2, .1, -10))
    c.lr("jnt_arm", pitch=wave(8, 1.2, .25, 10)); c.lr("jnt_forearm", pitch=wave(6, 1.2, .35))
    c.chain(tail(slug), yaw=wave(8, 2.4), pitch=wave(3, 1.2), lag=.08)
    c.lr("jnt_ear", pitch=wave(6, 1.2, .3))
    if slug == "hopping_mushroom":
        c.r("jnt_cap", roll=wave(3, 1.2)); c.lr("jnt_baby", pitch=wave(10, 1.2, .4))
    if slug == "running_cactus":
        c.r("jnt_flower", pitch=wave(6, 1.2, .3))
    if slug == "ball_scorpion":
        for n in (1, 2, 3): c.lr(f"jnt_leg{n}", roll=wave(8, 1.2, n * .1, -6))
        c.lr("jnt_pinch", yaw=wave(10, 1.2))
    if slug == "spoutle":
        c.r("jnt_spout", roll=wave(4, 1.2))
    return c

# ---------- Attack_Tackle: wind up, thrust, settle. In place: gameplay code owns the lunge ----------
def tackle(rig, slug):
    c = Clip(rig, .8)
    c.markers = {"impact": .3}
    g = {"plazadillo": .55, "branch_deer": .8, "sun_camel": .7, "ball_scorpion": .35}.get(slug, 1.0)
    pose = keys((0, 0), (.2, -1, "io"), (.3, 1.5, "out"), (.42, 1.2), (.8, 0, "io"))
    hp = scale(pose, 10 * g); hz = scale(pose, .11 * g); hy = scale(keys((0, 0), (.2, 1), (.3, .4), (.8, 0)), -.05)
    c.t("jnt_hips", y=hy, z=hz); c.r("jnt_hips", pitch=hp)
    for j in spine(c)[:-1]: c.r(j, pitch=scale(delay(pose, .015), 6 * g))
    c.r("jnt_head", pitch=scale(delay(pose, .03), 9 * g))
    c.chain(tail(slug), pitch=ring(.3, -22, 5, 6), lag=.03)
    c.lr("jnt_ear", pitch=ring(.3, -18, 6, 7))
    grounded(c, slug, hy=hy, hz=hz, hp=hp, cp=scale(delay(pose, .015), 6 * g))
    if slug == "ball_scorpion":
        c.lr("jnt_arm", yaw=scale(pose, 14), pitch=scale(pose, -8)); c.lr("jnt_pinch", yaw=ring(.3, -24, 6, 6))
    if slug == "running_cactus":
        c.lr("jnt_arm", pitch=scale(pose, 22)); c.r("jnt_flower", pitch=ring(.3, 24, 7, 7))
    if slug == "hopping_mushroom":
        c.r("jnt_cap", pitch=add(scale(pose, 12), ring(.32, 12, 6, 7))); c.lr("jnt_baby", pitch=ring(.3, 26, 7, 7))
    if slug == "plazadillo":
        c.r("jnt_crystal", pitch=ring(.3, 14, 6, 7))
    if slug == "spoutle":
        c.r("jnt_spout", pitch=ring(.3, 18, 7, 7))
    return c

RECIPES = {"Attack_Tackle": tackle, "BattleIdle": battle_idle, "Hit": hit, "Faint": faint, "Happy": happy, "Fidget": fidget, "Sleep": sleep, "Carried": carried}

# ---------- output ----------
def add_animation(js, bin_, name, times, tracks, rig):
    def push(values, ctype=5126, atype="SCALAR", mm=False):
        off = len(bin_)
        flat = [v for row in values for v in (row if isinstance(row, (tuple, list)) else (row,))]
        bin_.extend(struct.pack(f"<{len(flat)}f", *flat))
        while len(bin_) % 4: bin_.append(0)
        js["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": 4 * len(flat)})
        acc = {"bufferView": len(js["bufferViews"]) - 1, "componentType": ctype, "count": len(values), "type": atype}
        if mm: acc["min"], acc["max"] = [min(values)], [max(values)]
        js["accessors"].append(acc)
        return len(js["accessors"]) - 1
    tacc = push(times, mm=True)
    samplers, channels = [], []
    for j, tr in tracks.items():
        node = rig.index[j]
        if tr["q"]:
            rest = js["nodes"][node].get("rotation", [0, 0, 0, 1])
            q = [qmul(tuple(rest), v) for v in tr["q"]]
            samplers.append({"input": tacc, "interpolation": "LINEAR", "output": push(q, atype="VEC4")})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": "rotation"}})
        if tr["t"]:
            rest = js["nodes"][node].get("translation", [0, 0, 0])
            v = [tuple(rest[a] + row[a] for a in range(3)) for row in tr["t"]]
            samplers.append({"input": tacc, "interpolation": "LINEAR", "output": push(v, atype="VEC3")})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": "translation"}})
    js["animations"].append({"name": name, "samplers": samplers, "channels": channels})

def check_loop(times, tracks):
    worst = 0.0
    for tr in tracks.values():
        if tr["q"]:
            a, b = tr["q"][0], tr["q"][-1]
            dot = abs(sum(x * y for x, y in zip(a, b)))
            worst = max(worst, math.degrees(2 * math.acos(min(1, dot))))
    return worst

COMP = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}
WIDTH = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}
def accessor(js, bin_, i):
    a = js["accessors"][i]; v = js["bufferViews"][a["bufferView"]]
    n = WIDTH[a["type"]]; f, sz = COMP[a["componentType"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    return [struct.unpack_from("<" + f * n, bin_, off + k * n * sz) for k in range(a["count"])]

def slerp(a, b, u):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0: b, d = tuple(-x for x in b), -d
    q = tuple(x + (y - x) * u for x, y in zip(a, b))
    m = math.sqrt(sum(x * x for x in q)) or 1.0
    return tuple(x / m for x in q)

def originals(js, bin_, rig):
    """The 5 source clips as deltas from rest. Scale channels cannot be carried (Bone.Transform is a CFrame)."""
    out = {}
    for anim in js["animations"]:
        channels = [c for c in anim["channels"] if js["nodes"][c["target"]["node"]].get("name") in rig.index]
        dur = 0.0
        for c in channels:
            dur = max(dur, accessor(js, bin_, anim["samplers"][c["sampler"]]["input"])[-1][0])
        frames = int(round(dur * FPS)) + 1
        times = [min(i / FPS, dur) for i in range(frames)]
        tracks, dropped = {}, []
        for c in channels:
            name = js["nodes"][c["target"]["node"]]["name"]; path = c["target"]["path"]
            if path == "scale":
                dropped.append(name); continue
            smp = anim["samplers"][c["sampler"]]
            inp = [x[0] for x in accessor(js, bin_, smp["input"])]
            val = accessor(js, bin_, smp["output"])
            rest = js["nodes"][c["target"]["node"]].get("translation", [0, 0, 0])
            row = []
            for t in times:
                k = 0
                while k + 1 < len(inp) - 1 and inp[k + 1] <= t: k += 1
                if len(inp) == 1: v = val[0]
                else:
                    u = clamp01((t - inp[k]) / max(inp[k + 1] - inp[k], 1e-6))
                    if path == "rotation": v = slerp(val[k], val[k + 1], u)
                    else: v = tuple(x + (y - x) * u for x, y in zip(val[k], val[k + 1]))
                row.append(v if path == "rotation" else tuple(v[a] - rest[a] for a in range(3)))
            tr = tracks.setdefault(name, {"q": None, "t": None})
            tr["q" if path == "rotation" else "t"] = row
        name = anim["name"]
        out[name] = dict(dur=dur, loop=name in ("Idle", "Walk"), times=times, tracks=tracks, droppedScale=sorted(set(dropped)))
        if name.startswith("Attack_"):
            out[name]["markers"] = {"impact": round(impact_time(times, tracks), 3)}
    return out

def qconj(q): return (-q[0], -q[1], -q[2], q[3])

def close_loop(c, threshold=.5):
    """Hides a source loop seam in the clip data: the GLB keeps its seam, the game does not show it."""
    n = len(c["times"]); fixed = {}
    for j, tr in c["tracks"].items():
        if not tr["q"]: continue
        a, b = tr["q"][0], tr["q"][-1]
        d = abs(sum(x * y for x, y in zip(a, b)))
        deg = math.degrees(2 * math.acos(min(1.0, d)))
        if deg <= threshold: continue
        fix = qmul(a, qconj(b))
        start = int(n * .6)
        for i in range(start, n):
            u = (i - start) / (n - 1 - start)
            tr["q"][i] = qmul(slerp((0, 0, 0, 1), fix, u * u), tr["q"][i])
        fixed[j] = round(deg, 2)
    return fixed

def impact_time(times, tracks):
    """Fastest moment of the whole body after the wind-up. An estimate: tune it against the VFX."""
    best, at = -1.0, times[len(times) // 2]
    for i in range(1, len(times)):
        if times[i] < .2 * times[-1] or times[i] > .85 * times[-1]: continue
        speed = 0.0
        for tr in tracks.values():
            if tr["q"]:
                d = abs(sum(x * y for x, y in zip(tr["q"][i - 1], tr["q"][i])))
                speed += 2 * math.acos(min(1.0, d))
        if speed > best: best, at = speed, times[i]
    return at

SPECIES_ID = {"glimmouse": "Glimmouse", "plazadillo": "Plazadillo", "spoutle": "Spoutle", "acorn_squirrel": "AcornSquirrel",
              "hopping_mushroom": "HoppingMushroom", "branch_deer": "BranchDeer", "running_cactus": "RunningCactus",
              "ball_scorpion": "BallScorpion", "sun_camel": "SunCamel"}
STAGE_SCALE = {"Baby": .56, "Juvenile": .78, "Adult": 1.0}

def num(x):
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s

def luau_track(tr, frames, k):
    q = tr.get("q") or [(0.0, 0.0, 0.0, 1.0)] * frames
    # keep every quaternion on the same side as the last one, so blends never go the long way round
    fixed, prev = [], None
    for v in q:
        if prev is not None and sum(a * b for a, b in zip(prev, v)) < 0: v = tuple(-a for a in v)
        fixed.append(v); prev = v
    parts = ["r={" + ",".join(num(a) for v in fixed for a in v) + "}"]
    if tr.get("t"):
        parts.append("t={" + ",".join(num(a * k) for v in tr["t"] for a in v) + "}")
    return "{" + ",".join(parts) + "}"

def quiet(tr):
    q_ok = not tr.get("q") or all(abs(v[3]) > .99999 for v in tr["q"])
    t_ok = not tr.get("t") or all(abs(a) < 1e-4 for v in tr["t"] for a in v)
    return q_ok and t_ok

def write_module(path, slug, rig, clips):
    lines = ["--!strict", f"-- GENERATED by scripts/author-pet-reactions.py for {slug}. Do not edit.",
             "-- Same shape as Shared.PetAnimations; the tracks are Bone.Transform values per frame.",
             "-- r: quaternions (x,y,z,w). t: metres at Adult. Multiply t by stageScale[stage] * importedStudsPerMetre.",
             "-- stylua: ignore", "return {", "\tfps = 30,",
             '\tstageScale = { Baby = 0.56, Juvenile = 0.78, Adult = 1 },', "\tjoints = {"]
    for j in rig.index:
        lines.append(f'\t\t{{ name = "{j}", parent = "{rig.parent[j] if rig.parent[j] in rig.index else "Root"}" }},')
    lines += ["\t},", "\tclips = {"]
    for name, c in clips.items():
        frames = len(c["times"])
        lines.append(f'\t\t{name} = {{ duration = {num(c["dur"])}, frames = {frames}, loop = {"true" if c["loop"] else "false"},')
        if c.get("markers"):
            lines.append("\t\t\tmarkers = { " + ", ".join(f"{k} = {num(v)}" for k, v in c["markers"].items()) + " },")
        lines.append("\t\t\ttracks = {")
        for j, tr in c["tracks"].items():
            if quiet(tr): continue
            lines.append(f"\t\t\t\t{j} = {luau_track(tr, frames, rig.k)},")
        lines += ["\t\t\t},", "\t\t},"]
    lines += ["\t},", "}", ""]
    path.write_text("\n".join(lines))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", help="also write preview GLBs (original + new clips) here")
    ap.add_argument("--species"); ap.add_argument("--stages", default="Baby,Juvenile,Adult")
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()
    slugs = a.species.split(",") if a.species else SLUGS
    outdir = Path(a.out) / "luau"; outdir.mkdir(parents=True, exist_ok=True)
    seams, summary = [], {}
    for slug in slugs:
        js, bin_ = read_glb(PETS / slug / f"{slug}_adult.glb")
        rig = Rig(js); rig.slug, rig.stage = slug, "Adult"
        clips = originals(js, bin_, rig)
        for name in ("Idle", "Walk"):
            fixed = close_loop(clips[name])
            if fixed: clips[name]["seamClosed"] = fixed
        for name, recipe in RECIPES.items():
            clip = recipe(rig, slug)
            times, tracks = clip.bake()
            if clip.loop:
                seams.append((f"{slug}/{name}", round(check_loop(times, tracks), 3)))
            clips[name] = dict(dur=clip.dur, loop=clip.loop, times=times, tracks=tracks, authored=True)
            if getattr(clip, "markers", None): clips[name]["markers"] = clip.markers
        # Baby and Juvenile bodies differ, so a settled pose can need its own height.
        # Only these two clips touch the floor with the body; everything else shares one clip.
        for stage in ("Baby", "Juvenile"):
            rig.stage = stage
            for name in ("Faint", "Sleep"):
                clip = RECIPES[name](rig, slug)
                times, tracks = clip.bake()
                clips[f"{name}_{stage}"] = dict(dur=clip.dur, loop=clip.loop, times=times, tracks=tracks, authored=True)
        rig.stage = "Adult"
        module = outdir / f"{SPECIES_ID[slug]}.luau"
        write_module(module, slug, rig, clips)
        summary[SPECIES_ID[slug]] = {
            "bytes": module.stat().st_size,
            "clips": {n: {"duration": round(c["dur"], 3), "loop": c["loop"], "source": "authored" if c.get("authored") else "original",
                          "markers": c.get("markers"), "droppedScaleOn": c.get("droppedScale"), "seamClosedDegrees": c.get("seamClosed")} for n, c in clips.items()},
        }
        if a.glb:
            d = Path(a.glb); d.mkdir(parents=True, exist_ok=True)
            for stage in a.stages.split(","):
                path = PETS / slug / f"{slug}_{stage.lower()}.glb"
                vjs, vbin = read_glb(path)
                vrig = Rig(vjs)
                for name in RECIPES:
                    c = clips.get(f"{name}_{stage}", clips[name])
                    add_animation(vjs, vbin, name, c["times"], c["tracks"], vrig)
                write_glb(d / path.name, vjs, vbin)
    if not a.species:
        (Path(a.out) / "clip-index.json").write_text(json.dumps(summary, indent=1))
    bad = [s for s in seams if s[1] > .5]
    print("species", len(summary), "bytes", sum(v["bytes"] for v in summary.values()), "worst loop seam", max((s[1] for s in seams), default=0), "over 0.5 deg:", bad[:6])

if __name__ == "__main__":
    main()
