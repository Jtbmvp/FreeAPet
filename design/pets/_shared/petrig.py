"""Generic code-animation toolkit for Meshy-rigged quadruped pets (runs in Blender / `bpy`).

The delivered rig is never edited (names, rest pose, weights). A species module
gives a config:

  BONES   alias -> bone name (spine, head, ears, tails...)
  LEGS    leg -> [chain, ...]; chain = 2 or 3 bones (upper, lower[, paw]).
          Several chains per leg move together (overlapping Meshy chains).
  FOLLOW  bone -> bone it rides instead of its rig parent
  GUESS   leg -> (upper pitch, lower pitch) in radians, bent start for the IK

Axes are the armature's: the pet faces -Y, +Z up, +X is its left.
  pitch(+)  nose down / a hanging leg swings back / a tail tip goes up-and-forward
  yaw(+)    turns to its left;   roll(+) leans to its left

Each bone gets a rigid world delta G (posed = G @ rest). Legs use a damped
Newton IK on the upper+lower bones so the foot point lands on its target, then
a floor clamp lifts the target until no foot vertex is below z=0. A leg can
blend to plain FK (`w`, `fk`) for jumps and lying poses.
"""

import json
import math
import os
import struct

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

FPS = 30


# ---------------------------------------------------------------- math
def quat(pitch=0.0, yaw=0.0, roll=0.0):
    return (Quaternion((0, 0, 1), math.radians(yaw)) @ Quaternion((1, 0, 0), math.radians(pitch))
            @ Quaternion((0, 1, 0), math.radians(roll)))


def rot_about(p, q):
    return Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p)


def clamp01(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x


EASE = {
    "s": lambda x: clamp01(x) ** 2 * (3 - 2 * clamp01(x)),
    "lin": clamp01,
    "in": lambda x: clamp01(x) ** 2,
    "in3": lambda x: clamp01(x) ** 3,
    "out": lambda x: 1 - (1 - clamp01(x)) ** 2,
    "out3": lambda x: 1 - (1 - clamp01(x)) ** 3,
    "back": lambda x: 1 + 2.2 * (clamp01(x) - 1) ** 3 + 1.2 * (clamp01(x) - 1) ** 2,
}


def kf(t, keys):
    """keys: [(time, value[, ease into this key])]. Holds before/after the ends."""
    if t <= keys[0][0]:
        return keys[0][1]
    for a, b in zip(keys, keys[1:]):
        if t <= b[0]:
            x = EASE[b[2] if len(b) > 2 else "s"]((t - a[0]) / (b[0] - a[0]))
            return a[1] + (b[1] - a[1]) * x
    return keys[-1][1]


def wave(t, period, phase=0.0):
    return math.sin(2 * math.pi * (t / period - phase))


# ---------------------------------------------------------------- pose spec
class Leg:
    def __init__(self):
        self.dx = self.dy = self.dz = 0.0  # foot target offset from rest
        self.paw = 0.0  # absolute pitch of the paw bone (3-bone chains): + lifts the heel
        self.fk = None  # per bone (pitch, yaw, roll) relative to the parent, used when w > 0
        self.w = 0.0


class Pose:
    def __init__(self, legs):
        self.t = Vector((0, 0, 0))
        self.r = {}
        self.legs = {n: Leg() for n in legs}

    def rot(self, alias, pitch=0.0, yaw=0.0, roll=0.0):
        p, y, r = self.r.get(alias, (0.0, 0.0, 0.0))
        self.r[alias] = (p + pitch, y + yaw, r + roll)


# ---------------------------------------------------------------- rig
class Rig:
    def __init__(self, arm, mesh, cfg):
        self.arm, self.cfg = arm, cfg
        self.legs = cfg.LEGS
        follow = getattr(cfg, "FOLLOW", {})
        self.follow = follow
        bones = arm.data.bones
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.head = {b.name: b.head_local.copy() for b in bones}
        self.tail = {b.name: b.tail_local.copy() for b in bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        order = []

        def walk(b):
            order.append(b.name)
            for c in b.children:
                walk(c)

        for b in bones:
            if not b.parent:
                walk(b)
        late = set()
        for n in order:  # FOLLOW subtrees are solved after the bone they ride
            if n in follow or self.parent[n] in late:
                late.add(n)
        self.order = [n for n in order if n not in late] + [n for n in order if n in late]
        self.leg_bones = {b for chains in self.legs.values() for c in chains for b in c}
        self.alias = {v: k for k, v in cfg.BONES.items()}
        self.home = {n: self.foot_point(c[0]) for n, c in self.legs.items()}
        self.reset_guess()
        # lowest rest vertices of each leg's lower bones, for the floor clamp
        names = [g.name for g in mesh.vertex_groups]
        slot = {}
        for leg, chains in self.legs.items():
            for c in chains:
                for i, b in enumerate(c):
                    if i >= 1:
                        slot[b] = (leg, i)
        pts = {n: [] for n in self.legs}
        co = np.empty(len(mesh.data.vertices) * 3)
        mesh.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        low = np.nonzero(co[:, 2] < 0.25)[0]
        for vi in low:
            v = mesh.data.vertices[int(vi)]
            if v.groups:
                g = max(v.groups, key=lambda g: g.weight)
                s = slot.get(names[g.group])
                if s:
                    pts[s[0]].append((s[1], Vector(co[vi])))
        self.floor = {}
        for leg, p in pts.items():
            p.sort(key=lambda q: q[1].z)
            self.floor[leg] = p[:60] + p[60::max(1, len(p) // 120)]

    def foot_point(self, chain):
        return (self.head[chain[2]] if len(chain) > 2 else self.tail[chain[1]]).copy()

    def reset_guess(self):
        self.guess = {n: [*self.cfg.GUESS[n], 0.0] for n in self.legs}
        self.miss = {n: 0.0 for n in self.legs}

    def solve(self, pose):
        G = {}
        for name in self.order:
            if name in self.leg_bones:
                continue
            par = self.follow.get(name, self.parent[name])
            base = G[par] if par else Matrix.Translation(pose.t)
            rot = pose.r.get(self.alias.get(name))
            G[name] = base @ rot_about(self.head[name], quat(*rot)) if rot else base.copy()
        for leg, chains in self.legs.items():
            gs = self._leg(leg, chains[0], G[self.parent[chains[0][0]]], pose.legs[leg])
            for chain in chains:
                for b, g in zip(chain, gs):
                    G[b] = g
        return G

    def _leg(self, leg, chain, gpar, spec):
        h = [self.head[b] for b in chain]
        foot = self.foot_point(chain)

        def fk2(x):
            g0 = gpar @ rot_about(h[0], Quaternion((0, 1, 0), x[2]) @ Quaternion((1, 0, 0), x[0]))
            return g0, g0 @ rot_about(h[1], Quaternion((1, 0, 0), x[1]))

        def newton(x, want):
            for _ in range(30):
                g1 = fk2(x)[1]
                e = g1 @ foot - want
                if e.length < 1e-5:
                    break
                cols = []
                for i in range(3):
                    y = list(x)
                    y[i] += 1e-3
                    cols.append((fk2(y)[1] @ foot - g1 @ foot) / 1e-3)
                J = Matrix((cols[0], cols[1], cols[2])).transposed()
                dx = J.transposed() @ ((J @ J.transposed() + Matrix.Identity(3) * 2e-4).inverted() @ e)
                step = max(1.0, dx.length / 0.35)
                x = [x[i] - dx[i] / step for i in range(3)]
            x[2] = max(-0.6, min(0.6, x[2]))
            return x, (fk2(x)[1] @ foot - want).length

        def ik(want):
            x, miss = newton(list(self.guess[leg]), want)
            if miss > 2e-3:  # straight legs are singular: restart from bent poses
                a, b = self.cfg.GUESS[leg]
                for k in (1.0, 3.0, 5.0):
                    x2, m2 = newton([a * k, b * k, 0.0], want)
                    if m2 < miss - 1e-4:
                        x, miss = x2, m2
                    if miss < 2e-3:
                        break
            self.guess[leg], self.miss[leg] = x, miss
            g0, g1 = fk2(x)
            gs = [g0, g1]
            if len(chain) > 2:
                ank = g1 @ h[2]
                gs.append(Matrix.Translation(ank) @ quat(pitch=spec.paw).to_matrix().to_4x4() @ Matrix.Translation(-h[2]))
            return gs

        target = self.home[leg] + Vector((spec.dx, spec.dy, spec.dz))
        gs = ik(target)
        if spec.w < 1.0:
            for _ in range(3):
                low = min((gs[i] @ co).z for i, co in self.floor[leg]) if self.floor[leg] else 0
                if low > -0.002:
                    break
                target.z -= low
                gs = ik(target)
        if spec.w <= 0.0 or spec.fk is None:
            return gs
        out, prev_ik, prev = [], gpar, gpar
        for i in range(len(chain)):
            q_ik = prev_ik.to_quaternion().inverted() @ gs[i].to_quaternion()
            g = prev @ rot_about(h[i], q_ik.slerp(quat(*spec.fk[i]), spec.w))
            out.append(g)
            prev_ik, prev = gs[i], g
        return out

    def basis(self, G):
        pm = {n: G[n] @ self.rest[n] for n in self.order}
        out = {}
        for n in self.order:
            p = self.parent[n]
            if p:
                out[n] = (self.rest[p].inverted() @ self.rest[n]).inverted() @ pm[p].inverted() @ pm[n]
            else:
                out[n] = self.rest[n].inverted() @ pm[n]
        return out


# ---------------------------------------------------------------- scene
def load(src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None:  # bone display shape
            bpy.data.objects.remove(o)
    bpy.context.scene.render.fps = FPS
    return next(o for o in bpy.data.objects if o.type == "ARMATURE"), next(o for o in bpy.data.objects if o.type == "MESH")


def mesh_low(mesh, below=None):
    """Lowest vertex z; with `below`, also {bone: min z} for vertices under that height."""
    ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(ev.matrix_world)
    z = co @ mw[2, :3] + mw[2, 3]
    owners = {}
    if below is not None:
        for vi in np.nonzero(z < below)[0][:400]:
            src = mesh.data.vertices[int(vi)]
            if src.groups:
                n = mesh.vertex_groups[max(src.groups, key=lambda g: g.weight).group].name
                owners[n] = min(owners.get(n, 0.0), round(float(z[vi]), 3))
    ev.to_mesh_clear()
    return float(z.min()), owners


def bake(rig, name, fn, duration, loop):
    arm = rig.arm
    frames = round(duration * FPS)
    rig.reset_guess()
    legs = list(rig.legs)
    if loop:
        for f in range(frames):
            p = Pose(legs)
            fn(f / FPS, p)
            rig.solve(p)
    samples = []
    for f in range(frames + 1):
        p = Pose(legs)
        fn((f % frames if loop else f) / FPS, p)
        samples.append(rig.basis(rig.solve(p)))
        for leg, m in rig.miss.items():
            if m > 0.02:
                print(f"   IK miss {name} f{f} {leg} {m:.3f}")
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if not arm.animation_data:
        arm.animation_data_create()
    arm.animation_data.action = act
    moved = {n for n in rig.order if max(s[n].to_translation().length for s in samples) > 1e-5}
    last = {}
    for f, bs in enumerate(samples):
        for n in rig.order:
            pb = arm.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            q = bs[n].to_quaternion()
            if n in last and last[n].dot(q) < 0:
                q.negate()
            last[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n in moved:
                pb.location = bs[n].to_translation()
                pb.keyframe_insert("location", frame=f)
    use_action(arm, act)
    return act


def use_action(arm, act):
    arm.animation_data.action = act
    if getattr(act, "slots", None) and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]


# ---------------------------------------------------------------- renders
VIEWS = {"side": (1, 0, 0.12), "q": (0.75, -0.7, 0.3), "front": (0, -1, 0.1), "back": (-0.6, 0.8, 0.3)}


def setup_render(size=400, samples=8):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.resolution_x = sc.render.resolution_y = size
    if not sc.camera:
        w = bpy.data.worlds.new("w")
        sc.world = w
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.56, 0.62, 1)
        w.node_tree.nodes["Background"].inputs[1].default_value = 1.2
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 3
        sun.rotation_euler = (0.8, 0.2, -0.6)
        sc.collection.objects.link(sun)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        cam.data.type = "ORTHO"
        sc.collection.objects.link(cam)
        sc.camera = cam
        g = bpy.data.meshes.new("ground")
        g.from_pydata([(-5, -5, 0), (5, -5, 0), (5, 5, 0), (-5, 5, 0)], [], [(0, 1, 2, 3)])
        sc.collection.objects.link(bpy.data.objects.new("ground", g))
    return sc


def render(path, view="side", scale=3.0, centre=(0, 0, 0.8), transparent=False):
    sc = bpy.context.scene
    cam = sc.camera
    cam.data.ortho_scale = scale
    c = Vector(centre)
    cam.location = c + Vector(VIEWS[view]).normalized() * 8
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    ground = bpy.data.objects.get("ground")
    if ground:
        ground.hide_render = transparent
    sc.render.film_transparent = transparent
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- build / export
def strip_scale_channels(path):
    """Roblox bones cannot scale: drop the (constant) scale channels the exporter writes."""
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    for anim in gltf.get("animations", []):
        keep = [c for c in anim["channels"] if c["target"]["path"] != "scale"]
        used = sorted({c["sampler"] for c in keep})
        remap = {o: n for n, o in enumerate(used)}
        anim["samplers"] = [anim["samplers"][i] for i in used]
        anim["channels"] = [dict(c, sampler=remap[c["sampler"]]) for c in keep]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    open(path, "wb").write(struct.pack("<4sII", b"glTF", 2, 20 + len(js) + len(rest))
                           + struct.pack("<I4s", len(js), b"JSON") + js + rest)


def build(pet_dir, cfg, clips_mod, args):
    """Bake every clip, validate floor contact, export GLB/FBX/clips json, register in the viewer.

    args: [] or ["export"] | ["check"] | ["strips", DIR, clip...]
    """
    meta = json.load(open(os.path.join(pet_dir, "pet.json")))
    name = meta["file"]
    mode = args[0] if args else "export"
    arm, mesh = load(os.path.join(pet_dir, "source", meta["source"]))
    rig = Rig(arm, mesh, cfg)
    report, actions = {}, {}
    for cname, fn, dur, loop, markers, family in clips_mod.CLIPS:
        act = bake(rig, cname, fn, dur, loop)
        for k, v in markers.items():
            act[f"marker_{k}"] = v
            act.pose_markers.new(k).frame = round(v * FPS)
        actions[cname] = act
        zs = []
        for f in range(round(dur * FPS) + 1):
            bpy.context.scene.frame_set(f)
            zs.append(mesh_low(mesh)[0])
        lo = min(zs)
        report[cname] = round(lo, 3)
        print(f"CLIP {cname:22s} {dur:4.1f}s min_z={lo:+.3f} @f{zs.index(lo)} below-2cm={sum(z < -0.02 for z in zs)}")
        if lo < -0.02:
            bpy.context.scene.frame_set(zs.index(lo))
            print("   sinking:", mesh_low(mesh, -0.02)[1])
    if mode == "strips":
        out, only = args[1], args[2:]
        setup_render(int(os.environ.get("STRIP_SIZE", 300)))
        n = int(os.environ.get("STRIP_N", 8))
        for cname, fn, dur, loop, markers, family in clips_mod.CLIPS:
            if only and cname not in only:
                continue
            use_action(arm, actions[cname])
            for i in range(n):
                bpy.context.scene.frame_set(round(i * dur * FPS / (n if loop else n - 1)))
                for view in ("side", "q"):
                    render(os.path.join(out, f"{cname}_{view}_{i}.png"), view, meta.get("frame", 2.8), (0, 0, 0.75))
    if mode != "export":
        return
    out = os.path.join(pet_dir, "export")
    os.makedirs(out, exist_ok=True)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location, pb.rotation_quaternion = (0, 0, 0), (1, 0, 0, 0)
    for cname, act in actions.items():
        tr = arm.animation_data.nla_tracks.new()
        tr.name = cname
        st = tr.strips.new(cname, 0, act)
        if getattr(act, "slots", None) and len(act.slots):
            st.action_slot = act.slots[0]
    glb = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=glb, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
        export_force_sampling=True, export_optimize_animation_size=False, export_anim_slide_to_zero=True,
        export_skins=True, export_yup=True)
    strip_scale_channels(glb)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(out, name + ".fbx"), bake_anim=True, bake_anim_use_nla_strips=True,
        bake_anim_use_all_actions=False, bake_anim_simplify_factor=0.0, add_leaf_bones=False,
        path_mode="COPY", embed_textures=True, object_types={"ARMATURE", "MESH"})
    info = {
        "name": name, "displayName": meta["name"], "fps": FPS, "source": meta["source"],
        "bones": cfg.BONES, "legs": cfg.LEGS,
        "clips": {c: {"duration": d, "frames": round(d * FPS) + 1, "loop": lp, "markers": m, "family": fam,
                      "note": getattr(clips_mod, "NOTES", {}).get(c, ""), "min_z": report[c]}
                  for c, fn, d, lp, m, fam in clips_mod.CLIPS},
    }
    json.dump(info, open(os.path.join(out, name + "_clips.json"), "w"), indent=1)
    # thumbnail: rest-ish Idle frame, transparent background
    use_action(arm, actions[clips_mod.CLIPS[0][0]])
    bpy.context.scene.frame_set(0)
    setup_render(256, 16)
    pets = os.path.dirname(pet_dir)
    thumb = os.path.join(pets, "viewer", "thumbs", meta["id"] + ".png")
    os.makedirs(os.path.dirname(thumb), exist_ok=True)
    render(thumb, "q", meta.get("frame", 2.8) * 0.82, (0, 0, 0.8), transparent=True)
    register(pets, meta, os.path.basename(pet_dir), len(clips_mod.CLIPS))
    print("EXPORTED", glb, os.path.getsize(glb))


def register(pets_dir, meta, folder, nclips):
    """Rebuild viewer/pets.json from every pet folder (the site polls it and refreshes by itself)."""
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from register import register_all
    register_all(pets_dir)
