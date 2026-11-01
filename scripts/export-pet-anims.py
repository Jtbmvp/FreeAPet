#!/usr/bin/env python3
"""Converts the pets' GLB rigs and clips (Claude Design sheets) into Luau data.

Writes src/shared/PetAnimations/<SpeciesId>.luau with:
  * joint frames (jnt_* nodes) relative to the art model's pivot, in the space
    of the mesh pets already imported in Studio (Assets.Animals.<SpeciesId>);
  * every clip, resampled at FPS, as per-joint deltas from the rest pose
    (what Motor6D.Transform expects: rotation quaternion + translation in studs
    at the asset's scale).

The Studio models came from the Blender-baked *_ready.glb (rotated and scaled),
so GLB space is matched to Studio space with a similarity fit on a few mesh
centres (design/pets/studio_anchors.json, dumped from Studio).

Scale channels (breathing squash) are ignored: Motor6D cannot scale.

Usage: python3 -I scripts/export-pet-anims.py
"""

import json
import math
import os
import struct
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLB_DIR = os.path.join(ROOT, "design", "pets", "glb")
ANCHORS = os.path.join(ROOT, "design", "pets", "studio_anchors.json")
OUT_DIR = os.path.join(ROOT, "src", "shared", "PetAnimations")
FPS = 30
LOOPING = {"Idle", "Walk", "BattleIdle"}

SPECIES_FILES = {
    "AcornSquirrel": "acorn_squirrel.glb",
    "HoppingMushroom": "hopping_mushroom.glb",
    "BranchDeer": "branch_deer.glb",
    "RunningCactus": "running_cactus.glb",
    "BallScorpion": "ball_scorpion.glb",
    "SunCamel": "sun_camel.glb",
}

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    data = open(path, "rb").read()
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + json_len])
    offset = 20 + json_len
    bin_len = struct.unpack_from("<I", data, offset)[0]
    return gltf, data[offset + 8 : offset + 8 + bin_len]


def read_accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    width = WIDTH[acc["type"]]
    fmt = COMPONENTS[acc["componentType"]]
    size = struct.calcsize(fmt)
    stride = view.get("byteStride", size * width)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    rows = []
    for i in range(acc["count"]):
        rows.append(struct.unpack_from("<" + fmt * width, blob, start + i * stride))
    return np.array(rows, dtype=float)


def quat_to_matrix(q):
    x, y, z, w = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array(
        [
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz,
        ]
    )


def quat_inv(q):
    return np.array([-q[0], -q[1], -q[2], q[3]]) / np.dot(q, q)


def slerp(a, b, t):
    if np.dot(a, b) < 0:
        b = -b
    d = min(1.0, float(np.dot(a, b)))
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    theta = math.acos(d) * t
    c = b - a * d
    c /= np.linalg.norm(c)
    return a * math.cos(theta) + c * math.sin(theta)


def local_matrix(node):
    m = np.eye(4)
    if "matrix" in node:
        return np.array(node["matrix"]).reshape(4, 4).T
    s = np.array(node.get("scale", [1, 1, 1]))
    m[:3, :3] = quat_to_matrix(node.get("rotation", [0, 0, 0, 1])) * s
    m[:3, 3] = node.get("translation", [0, 0, 0])
    return m


def similarity_fit(src, dst):
    """Umeyama: dst ~= s * R @ src + t."""
    mu_s, mu_d = src.mean(0), dst.mean(0)
    xs, xd = src - mu_s, dst - mu_d
    cov = xd.T @ xs / len(src)
    u, d, vt = np.linalg.svd(cov)
    sign = np.eye(3)
    if np.linalg.det(u) * np.linalg.det(vt) < 0:
        sign[2, 2] = -1
    r = u @ sign @ vt
    var = (xs**2).sum() / len(src)
    s = np.trace(np.diag(d) @ sign) / var
    t = mu_d - s * r @ mu_s
    return s, r, t


def cframe_numbers(pos, rot):
    values = [pos[0], pos[1], pos[2]] + [rot[i][j] for i in range(3) for j in range(3)]
    return [round(float(v), 5) for v in values]


def lua_number(v):
    text = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def sample_clips(gltf, blob, nodes, joint_set, species):
    """Every clip resampled at FPS: {name: (duration, frames, {node: {path: [values]}})}."""
    clips = {}
    for anim in gltf.get("animations", []):
        duration = 0.0
        for ch in anim["channels"]:
            sampler = anim["samplers"][ch["sampler"]]
            duration = max(duration, float(read_accessor(gltf, blob, sampler["input"])[-1, 0]))
        frames = max(2, int(round(duration * FPS)) + 1)
        sample_times = np.linspace(0, duration, frames)
        tracks = {}
        for ch in anim["channels"]:
            path = ch["target"]["path"]
            node = ch["target"]["node"]
            if path not in ("rotation", "translation") or node not in joint_set:
                continue
            sampler = anim["samplers"][ch["sampler"]]
            interp = sampler.get("interpolation", "LINEAR")
            if interp == "CUBICSPLINE":
                sys.exit(f"{species}/{anim['name']}: CUBICSPLINE not supported, bake to LINEAR")
            times = read_accessor(gltf, blob, sampler["input"])[:, 0]
            values = read_accessor(gltf, blob, sampler["output"])
            out = []
            for st in sample_times:
                k = int(np.searchsorted(times, st, side="right")) - 1
                k = max(0, min(k, len(times) - 1))
                if k == len(times) - 1 or interp == "STEP":
                    v = values[k]
                else:
                    a = (st - times[k]) / (times[k + 1] - times[k])
                    v = slerp(values[k], values[k + 1], a) if path == "rotation" else values[k] + (values[k + 1] - values[k]) * a
                out.append(np.array(v))
            tracks.setdefault(node, {})[path] = out
        clips[anim["name"]] = (duration, frames, tracks)
    return clips


def export_species(species, filename, anchors):
    gltf, blob = load_glb(os.path.join(GLB_DIR, filename))
    nodes = gltf["nodes"]
    parent = {}
    for i, node in enumerate(nodes):
        for c in node.get("children", []):
            parent[c] = i
    joints = [i for i, n in enumerate(nodes) if n.get("name", "").startswith("jnt_")]
    joint_set = set(joints)
    clips = sample_clips(gltf, blob, nodes, joint_set, species)

    def rest_of(i):
        return np.array(nodes[i].get("rotation", [0, 0, 0, 1])), np.array(nodes[i].get("translation", [0, 0, 0]))

    def pose_of(clip, frame):
        """Local (rotation, translation) overrides of the joints for a clip frame."""
        if clip is None:
            return {}
        _, _, tracks = clips[clip]
        pose = {}
        for node, track in tracks.items():
            q, t = rest_of(node)
            pose[node] = (track["rotation"][frame] if "rotation" in track else q, track["translation"][frame] if "translation" in track else t)
        return pose

    def world_of(i, pose):
        local = local_matrix(nodes[i])
        if i in pose:
            q, t = pose[i]
            scale = np.linalg.norm(local[:3, :3], axis=0)
            local[:3, :3] = quat_to_matrix(q) * scale
            local[:3, 3] = t
        return world_of(parent[i], pose) @ local if i in parent else local

    # Mesh centres in GLB space, matched to the Studio anchors by name.
    mesh_names = {}
    for i, node in enumerate(nodes):
        if "mesh" in node:
            mesh_names.setdefault(node.get("name"), []).append(i)
    matched = []
    for name, studio in anchors.items():
        found = mesh_names.get(name, [])
        if len(found) != 1:
            continue
        mesh = gltf["meshes"][nodes[found[0]]["mesh"]]
        lo = np.min([gltf["accessors"][p["attributes"]["POSITION"]]["min"] for p in mesh["primitives"]], 0)
        hi = np.max([gltf["accessors"][p["attributes"]["POSITION"]]["max"] for p in mesh["primitives"]], 0)
        matched.append((found[0], np.append((lo + hi) / 2, 1), np.array(studio)))
    if len(matched) < 3:
        sys.exit(f"{species}: only {len(matched)} anchors matched")
    dst = np.array([m[2] for m in matched])

    # The Blender bake saved the meshes in some clip frame, not the rest pose:
    # find the pose that matches Studio best and use it as the base pose.
    best = None
    candidates = [(None, 0)] + [(c, f) for c, (_, frames, _) in clips.items() for f in range(frames)]
    for clip, frame in candidates:
        pose = pose_of(clip, frame)
        src = np.array([(world_of(i, pose) @ c)[:3] for i, c, _ in matched])
        s, r, t = similarity_fit(src, dst)
        rms = np.sqrt((((s * (r @ src.T)).T + t - dst) ** 2).sum(1).mean())
        if best is None or rms < best[0]:
            best = (rms, clip, frame, s, r, t)
    rms, base_clip, base_frame, s, r, t = best
    # Imports only turn the model around Y: drop the fit's tiny tilt so the pet stands straight.
    yaw_rad = math.atan2(r[0, 2], r[2, 2])
    r = np.array([[math.cos(yaw_rad), 0, math.sin(yaw_rad)], [0, 1, 0], [-math.sin(yaw_rad), 0, math.cos(yaw_rad)]])
    src = np.array([(world_of(i, pose_of(base_clip, base_frame)) @ c)[:3] for i, c, _ in matched])
    xs, xd = src - src.mean(0), dst - dst.mean(0)
    s = float(np.sum(xd * (r @ xs.T).T) / np.sum(xs**2))
    t = dst.mean(0) - s * r @ src.mean(0)
    rms = np.sqrt((((s * (r @ src.T)).T + t - dst) ** 2).sum(1).mean())
    base = pose_of(base_clip, base_frame)
    yaw = math.degrees(math.atan2(r[0, 2], r[2, 2]))
    print(f"{species}: base pose {base_clip or 'rest'}[{base_frame}], {len(matched)} anchors, {s:.3f} studs/m, yaw {yaw:.0f}, rms {rms:.3f}")
    if rms > 0.05:
        sys.exit(f"{species}: fit too loose, check the anchors")

    def studio_frame(i):
        w = world_of(i, base)
        rot = w[:3, :3] / np.linalg.norm(w[:3, :3], axis=0)
        return cframe_numbers(s * r @ w[:3, 3] + t, r @ rot)

    def joint_parent(i):
        p = parent.get(i)
        while p is not None and p not in joint_set:
            p = parent.get(p)
        return p

    def depth(i):
        p = joint_parent(i)
        return 0 if p is None else depth(p) + 1

    joints.sort(key=depth)
    top = joints[0]  # the root frame: topmost ancestor of the joints (rig origin)
    while top in parent:
        top = parent[top]

    # Deltas from the base pose, in each joint's own frame (Motor6D.Transform).
    out_clips = {}
    for name, (duration, frames, tracks) in clips.items():
        result = {}
        for node, track in tracks.items():
            base_q, base_t = base.get(node, rest_of(node))
            base_rot = quat_to_matrix(base_q)
            rest_q, rest_t = rest_of(node)
            rot_out, pos_out = [], []
            for f in range(frames):
                q = track["rotation"][f] if "rotation" in track else rest_q
                p = track["translation"][f] if "translation" in track else rest_t
                dq = quat_mul(quat_inv(base_q), q)
                dq = dq / np.linalg.norm(dq)
                rot_out.extend(dq)
                pos_out.extend(base_rot.T @ (p - base_t) * s)
            entry = {"r": rot_out}
            if np.abs(pos_out).max() > 1e-4:
                entry["t"] = pos_out
            result[nodes[node]["name"]] = entry
        out_clips[name] = {"duration": duration, "frames": frames, "tracks": result}

    lines = [
        "--!strict",
        f"-- GENERATED by scripts/export-pet-anims.py from design/pets/glb/{filename}. Do not edit.",
        "",
        "return {",
        f"\tfps = {FPS},",
        f"\troot = {{ {', '.join(lua_number(v) for v in studio_frame(top))} }},",
        "\tjoints = {",
    ]
    for j in joints:
        p = joint_parent(j)
        pname = nodes[p]["name"] if p is not None else "RootPart"
        frame = ", ".join(lua_number(v) for v in studio_frame(j))
        lines.append(f'\t\t{{ name = "{nodes[j]["name"]}", parent = "{pname}", frame = {{ {frame} }} }},')
    lines.append("\t},")
    lines.append("\tclips = {")
    for name, clip in out_clips.items():
        loop = "true" if name in LOOPING else "false"
        lines.append(f'\t\t{name} = {{ duration = {lua_number(clip["duration"])}, frames = {clip["frames"]}, loop = {loop}, tracks = {{')
        for joint, entry in clip["tracks"].items():
            parts = [f"r = {{ {', '.join(lua_number(v) for v in entry['r'])} }}"]
            if "t" in entry:
                parts.append(f"t = {{ {', '.join(lua_number(v) for v in entry['t'])} }}")
            lines.append(f"\t\t\t{joint} = {{ {', '.join(parts)} }},")
        lines.append("\t\t} },")
    lines.append("\t},")
    lines.append("}")
    with open(os.path.join(OUT_DIR, f"{species}.luau"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    anchors = json.load(open(ANCHORS))
    os.makedirs(OUT_DIR, exist_ok=True)
    for species, filename in SPECIES_FILES.items():
        export_species(species, filename, anchors[species])


if __name__ == "__main__":
    main()
