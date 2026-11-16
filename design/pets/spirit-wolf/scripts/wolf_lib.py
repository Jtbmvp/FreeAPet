"""Spirit Wolf animation toolkit (runs inside Blender / the `bpy` module).

The Meshy rig is used exactly as delivered: bone names, rest pose and skin
weights are never edited. Clips are authored in code, in armature axes:
the wolf faces -Y, +Z is up, +X is its left.

  pitch(+)  nose / front end goes down, a hanging leg swings backwards, tail tip goes up
  yaw(+)    turns to its left
  roll(+)   leans to its left

Every bone gets a rigid world-space delta G (posed = G @ rest). Legs are
solved with a small damped-Newton IK so paws stay where the clip puts them
while the body moves; a clip can blend any leg to plain FK (used when the
wolf leaves the ground or lies down).
"""

import math
import os

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30

# ---------------------------------------------------------------- rig map
BONES = {
    "root": "Bone_000",
    "pelvis": "Bone_001",
    "spine": "Bone_013",
    "chest": "Bone_012",
    "head": "Bone_027",
    "muzzle": "Bone_025",
    "nose": "Bone_024",
    "antler_L": "Bone_023",
    "antler_L_tip": "Bone_022",
    "antler_R": "Bone_021",
    "antler_R_tip": "Bone_020",
    "tail1": "Bone_017",
    "tail2": "Bone_016",
    "tail3": "Bone_015",
    "tail4": "Bone_014",
}

# Front legs have two overlapping chains in the Meshy rig (both carry skin
# weights), so each front leg drives both with the same world transforms.
LEGS = {
    "FL": [["Bone_047", "Bone_046", "Bone_045", "Bone_044", "Bone_043"],
           ["Bone_037", "Bone_036", "Bone_035", "Bone_034", "Bone_033"]],
    "FR": [["Bone_042", "Bone_041", "Bone_040", "Bone_039", "Bone_038"],
           ["Bone_032", "Bone_031", "Bone_030", "Bone_029", "Bone_028"]],
    "HL": [["Bone_011", "Bone_010", "Bone_009", "Bone_008", "Bone_007"]],
    "HR": [["Bone_006", "Bone_005", "Bone_004", "Bone_003", "Bone_002"]],
}
# The antlers hang off the chest bone in the rig; they must ride the head.
FOLLOW = {"Bone_021": "Bone_027", "Bone_023": "Bone_027"}
LEG_GUESS = {"FL": (0.15, -0.3, 0.0), "FR": (0.15, -0.3, 0.0), "HL": (-0.1, 0.2, 0.0), "HR": (-0.1, 0.2, 0.0)}


# ---------------------------------------------------------------- math
def quat(pitch=0.0, yaw=0.0, roll=0.0):
    """Degrees, armature axes."""
    return (
        Quaternion((0, 0, 1), math.radians(yaw))
        @ Quaternion((1, 0, 0), math.radians(pitch))
        @ Quaternion((0, 1, 0), math.radians(roll))
    )


def rot_about(p, q):
    return Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p)


def clamp01(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x


def smooth(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


EASE = {
    "s": smooth,
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
            e = EASE[b[2] if len(b) > 2 else "s"]
            x = e((t - a[0]) / (b[0] - a[0]))
            return a[1] + (b[1] - a[1]) * x
    return keys[-1][1]


def wave(t, period, phase=0.0):
    return math.sin(2 * math.pi * (t / period - phase))


# ---------------------------------------------------------------- pose spec
class Leg:
    def __init__(self):
        self.dx = self.dy = self.dz = 0.0  # paw target offset from its rest spot
        self.m = 0.0  # pastern pitch (absolute)
        self.paw = 0.0  # paw pitch (absolute): + lifts the heel
        self.toe = 0.0
        self.fk = None  # five (pitch, yaw, roll) tuples, relative to the parent bone
        self.w = 0.0  # 0 = IK, 1 = FK


class Pose:
    def __init__(self):
        self.t = Vector((0, 0, 0))  # root translation
        self.r = {}
        self.legs = {n: Leg() for n in LEGS}

    def rot(self, alias, pitch=0.0, yaw=0.0, roll=0.0):
        p, y, r = self.r.get(alias, (0.0, 0.0, 0.0))
        self.r[alias] = (p + pitch, y + yaw, r + roll)

    def tail(self, pitch=(0, 0, 0, 0), yaw=(0, 0, 0, 0), roll=(0, 0, 0, 0)):
        for i in range(4):
            self.rot(f"tail{i + 1}", pitch[i], yaw[i], roll[i])


# ---------------------------------------------------------------- rig
class Rig:
    def __init__(self, arm, mesh):
        self.arm = arm
        # rest-pose vertices of each lower leg (pastern, paw, toes) for the floor clamp
        self.floor = {}
        names = [g.name for g in mesh.vertex_groups]
        for leg, chains in LEGS.items():
            slot = {b: i for c in chains for i, b in enumerate(c) if i >= 2}
            pts = []
            for v in mesh.data.vertices:
                if v.groups and v.co.z < 0.3:
                    g = max(v.groups, key=lambda g: g.weight)
                    if names[g.group] in slot:
                        pts.append((slot[names[g.group]], (mesh.matrix_world @ v.co).copy()))
            pts.sort(key=lambda p: p[1].z)
            self.floor[leg] = pts[:60] + pts[60::max(1, len(pts) // 120)]
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        self.head = {b.name: b.head_local.copy() for b in arm.data.bones}
        self.tip = {b.name: b.tail_local.copy() for b in arm.data.bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
        self.order = []

        def walk(b):
            self.order.append(b.name)
            for c in b.children:
                walk(c)

        for b in arm.data.bones:
            if not b.parent:
                walk(b)
        late = set()
        for n in self.order:  # FOLLOW subtrees are solved after the bone they ride
            if n in FOLLOW or self.parent[n] in late:
                late.add(n)
        self.order = [n for n in self.order if n not in late] + [n for n in self.order if n in late]
        self.leg_bones = {b for chains in LEGS.values() for c in chains for b in c}
        self.alias = {v: k for k, v in BONES.items()}
        self.home = {n: self.head[chains[0][3]].copy() for n, chains in LEGS.items()}
        self.guess = {n: list(LEG_GUESS[n]) for n in LEGS}
        self.miss = {n: 0.0 for n in LEGS}

    def reset_guess(self):
        self.guess = {n: list(LEG_GUESS[n]) for n in LEGS}

    # world-space deltas for every bone
    def solve(self, pose):
        G = {}
        for name in self.order:
            if name in self.leg_bones:
                continue
            par = FOLLOW.get(name, self.parent[name])
            base = G[par] if par else Matrix.Translation(pose.t)
            rot = pose.r.get(self.alias.get(name))
            G[name] = base @ rot_about(self.head[name], quat(*rot)) if rot else base.copy()
        for leg, chains in LEGS.items():
            spec = pose.legs[leg]
            main = chains[0]
            gpar = G[self.parent[main[0]]]
            gs = self._leg(leg, main, gpar, spec)
            for chain in chains:
                for b, g in zip(chain, gs):
                    G[b] = g
        return G

    def _leg(self, leg, chain, gpar, spec):
        h = [self.head[b] for b in chain]
        rabs = quat(pitch=spec.m)
        rpaw = quat(pitch=spec.paw).to_matrix().to_4x4()
        target = self.home[leg] + Vector((spec.dx, spec.dy, spec.dz))

        def fk2(x):
            g0 = gpar @ rot_about(h[0], Quaternion((0, 1, 0), x[2]) @ Quaternion((1, 0, 0), x[0]))
            g1 = g0 @ rot_about(h[1], Quaternion((1, 0, 0), x[1]))
            return g0, g1

        def ik(target):
            want = target - rabs @ (h[3] - h[2])

            def newton(x):
                for _ in range(30):
                    g0, g1 = fk2(x)
                    e = g1 @ h[2] - want
                    if e.length < 1e-5:
                        break
                    cols = []
                    for i in range(3):
                        y = list(x)
                        y[i] += 1e-3
                        cols.append(((fk2(y)[1] @ h[2]) - (g1 @ h[2])) / 1e-3)
                    J = Matrix((cols[0], cols[1], cols[2])).transposed()
                    A = J @ J.transposed() + Matrix.Identity(3) * 2e-4
                    dx = J.transposed() @ (A.inverted() @ e)
                    step = max(1.0, dx.length / 0.35)
                    x = [x[i] - dx[i] / step for i in range(3)]
                x[2] = max(-0.6, min(0.6, x[2]))
                return x, (fk2(x)[1] @ h[2] - want).length

            x, miss = newton(list(self.guess[leg]))
            if miss > 2e-3:  # a straight leg is singular: restart from bent poses
                a, b, _ = LEG_GUESS[leg]
                for k in (1.0, 3.0, 5.0):
                    x2, m2 = newton([a * k, b * k, 0.0])
                    if m2 < miss - 1e-4:
                        x, miss = x2, m2
                    if miss < 2e-3:
                        break
            self.guess[leg] = x
            g0, g1 = fk2(x)
            p2 = g1 @ h[2]
            self.miss[leg] = (p2 - want).length
            g2 = Matrix.Translation(p2) @ rabs.to_matrix().to_4x4() @ Matrix.Translation(-h[2])
            g3 = Matrix.Translation(g2 @ h[3]) @ rpaw @ Matrix.Translation(-h[3])
            g4 = g3 @ rot_about(h[4], quat(pitch=spec.toe))
            return [g0, g1, g2, g3, g4]

        gs = ik(target)
        if spec.w < 1.0:
            # Floor clamp: lift the paw target until no lower-leg vertex is under the ground.
            for _ in range(3):
                low = min((gs[i] @ co).z for i, co in self.floor[leg])
                if low > -0.002:
                    break
                target.z -= low
                gs = ik(target)
        if spec.w <= 0.0 or spec.fk is None:
            return gs
        out, prev_ik, prev = [], gpar, gpar
        for i in range(5):
            q_ik = prev_ik.to_quaternion().inverted() @ gs[i].to_quaternion()
            q = q_ik.slerp(quat(*spec.fk[i]), spec.w)
            g = prev @ rot_about(h[i], q)
            out.append(g)
            prev_ik, prev = gs[i], g
        return out

    def basis(self, G):
        """Pose-bone basis matrices (what Blender keys) from the world deltas."""
        pm = {n: G[n] @ self.rest[n] for n in self.order}
        out = {}
        for n in self.order:
            p = self.parent[n]
            if p:
                rel = self.rest[p].inverted() @ self.rest[n]
                out[n] = rel.inverted() @ pm[p].inverted() @ pm[n]
            else:
                out[n] = self.rest[n].inverted() @ pm[n]
        return out

    def apply(self, pose):
        bs = self.basis(self.solve(pose))
        for n, m in bs.items():
            pb = self.arm.pose.bones[n]
            pb.rotation_mode = "QUATERNION"
            pb.location = m.to_translation()
            pb.rotation_quaternion = m.to_quaternion()
            pb.scale = (1, 1, 1)
        bpy.context.view_layer.update()


# ---------------------------------------------------------------- scene
def load(src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.parent is None:  # bone display shape, not part of the pet
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    bpy.context.scene.render.fps = FPS
    return arm, mesh


def mesh_min_z(mesh):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    z = min((mw @ v.co).z for v in me.vertices)
    ev.to_mesh_clear()
    return z


def bake(rig, name, fn, duration, loop):
    """fn(t, pose) fills a Pose. Returns the action and per-frame stats."""
    arm = rig.arm
    frames = round(duration * FPS)
    rig.reset_guess()
    if loop:  # warm the IK up over one cycle so frame 0 matches frame N
        for f in range(frames):
            p = Pose()
            fn(f / FPS, p)
            rig.solve(p)
    samples = []
    for f in range(frames + 1):
        p = Pose()
        fn((f % frames if loop else f) / FPS, p)
        samples.append(rig.basis(rig.solve(p)))
        for leg, m in rig.miss.items():
            if m > 0.01:
                print(f"   IK miss {name} f{f} {leg} {m:.3f}")
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if not arm.animation_data:
        arm.animation_data_create()
    arm.animation_data.action = act
    last = {}
    moved = {n for n in rig.order if max(s[n].to_translation().length for s in samples) > 1e-5}
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
    if getattr(act, "slots", None) and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    act["duration"] = duration
    act["loop"] = loop
    return act


def use_action(arm, act):
    arm.animation_data.action = act
    if getattr(act, "slots", None) and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]


def reset_pose(arm):
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- renders
def setup_render(size=420, samples=10):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.resolution_x = sc.render.resolution_y = size
    if not sc.world:
        w = bpy.data.worlds.new("w")
        sc.world = w
        w.use_nodes = True
        bg = w.node_tree.nodes["Background"]
        bg.inputs[0].default_value = (0.55, 0.56, 0.62, 1)
        bg.inputs[1].default_value = 1.2
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 3
        sun.rotation_euler = (0.8, 0.2, -0.6)
        sc.collection.objects.link(sun)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
        cam.data.type = "ORTHO"
        ground = bpy.data.meshes.new("ground")
        ground.from_pydata([(-4, -4, 0), (4, -4, 0), (4, 4, 0), (-4, 4, 0)], [], [(0, 1, 2, 3)])
        sc.collection.objects.link(bpy.data.objects.new("ground", ground))
    return sc


VIEWS = {"side": (1, 0, 0.12), "q": (0.75, -0.7, 0.3), "front": (0, -1, 0.1), "back": (-0.6, 0.8, 0.3)}


def render(path, view="side", scale=3.0, centre=(0, -0.05, 0.8)):
    sc = bpy.context.scene
    cam = sc.camera
    cam.data.ortho_scale = scale
    c = Vector(centre)
    d = Vector(VIEWS[view]).normalized()
    cam.location = c + d * 8
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
