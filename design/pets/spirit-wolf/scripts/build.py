"""Builds the Spirit Wolf clips and exports them.

  python build.py            bake + validate + export (GLB, FBX, clips json)
  python build.py strips DIR also render a frame strip per clip into DIR
  python build.py check      bake + validate only
Runs with Blender's Python (`blender -b -P build.py -- ...`) or the `bpy` module.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402

import wolf_clips  # noqa: E402
import wolf_lib as W  # noqa: E402

PET = os.path.dirname(HERE)
SRC = os.path.join(PET, "source", "SpiritWolf_meshy_rigged.glb")
OUT = os.path.join(PET, "export")
NAME = "SpiritWolf"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
mode = args[0] if args else "export"

def strip_scale_channels(path):
    """Roblox bones cannot scale: drop the (constant) scale channels the exporter writes."""
    import struct
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    dropped = 0
    for anim in gltf.get("animations", []):
        keep = [c for c in anim["channels"] if c["target"]["path"] != "scale"]
        dropped += len(anim["channels"]) - len(keep)
        used = sorted({c["sampler"] for c in keep})
        remap = {old: new for new, old in enumerate(used)}
        anim["samplers"] = [anim["samplers"][i] for i in used]
        anim["channels"] = [dict(c, sampler=remap[c["sampler"]]) for c in keep]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + len(rest)) + struct.pack("<I4s", len(js), b"JSON") + js + rest
    open(path, "wb").write(out)
    return dropped


arm, mesh = W.load(SRC)
rig = W.Rig(arm, mesh)
report, actions = {}, {}
for name, fn, dur, loop, markers, family in wolf_clips.CLIPS:
    act = W.bake(rig, name, fn, dur, loop)
    for k, v in markers.items():
        act[f"marker_{k}"] = v
        act.pose_markers.new(k).frame = round(v * W.FPS)
    actions[name] = act
    W.use_action(arm, act)
    zs = []
    for f in range(round(dur * W.FPS) + 1):
        bpy.context.scene.frame_set(f)
        zs.append(W.mesh_min_z(mesh))
    lo = min(zs)
    report[name] = {"frames": len(zs), "min_z": round(lo, 3), "at_frame": zs.index(lo)}
    if lo < -0.02:  # which bones own the vertices that sink
        bpy.context.scene.frame_set(zs.index(lo))
        ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = ev.to_mesh()
        owners = {}
        for v, src in zip(me.vertices, mesh.data.vertices):
            if v.co.z < -0.02 and src.groups:
                g = max(src.groups, key=lambda g: g.weight)
                n = mesh.vertex_groups[g.group].name
                owners[n] = min(owners.get(n, 0), round(v.co.z, 3))
        ev.to_mesh_clear()
        print("   sinking:", owners)
    print(f"CLIP {name:22s} {dur:4.1f}s frames={len(zs):3d} min_z={lo:+.3f} @f{zs.index(lo)}"
          f" below-2cm={sum(z < -0.02 for z in zs)}")

if mode == "strips":
    out = args[1]
    only = args[2:] or [c[0] for c in wolf_clips.CLIPS]
    W.setup_render(int(os.environ.get("STRIP_SIZE", 300)), 8)
    for name, fn, dur, loop, markers, family in wolf_clips.CLIPS:
        if name not in only:
            continue
        W.use_action(arm, actions[name])
        n = int(os.environ.get("STRIP_N", 8))
        for i in range(n):
            f = round(i * dur * W.FPS / (n if loop else n - 1))
            bpy.context.scene.frame_set(f)
            for view in ("side", "q"):
                W.render(os.path.join(out, f"{name}_{view}_{i}.png"), view, 2.7, (0, -0.15, 0.75))

if mode == "export":
    os.makedirs(OUT, exist_ok=True)
    W.reset_pose(arm)
    arm.animation_data.action = None
    for name, act in actions.items():
        tr = arm.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, 0, act)
        st.name = name
        if getattr(act, "slots", None) and len(act.slots):
            st.action_slot = act.slots[0]
    bpy.context.scene.frame_start = 0
    glb = os.path.join(OUT, NAME + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=glb, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
        export_force_sampling=True, export_optimize_animation_size=True, export_anim_slide_to_zero=True,
        export_optimize_animation_keep_anim_armature=True,  # drops the constant scale channels (Roblox cannot scale bones)
        export_skins=True, export_yup=True, export_image_format="AUTO",
    )
    print("scale channels removed:", strip_scale_channels(glb))
    try:
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(OUT, NAME + ".fbx"), bake_anim=True, bake_anim_use_nla_strips=True,
            bake_anim_use_all_actions=False, bake_anim_simplify_factor=0.0, add_leaf_bones=False,
            path_mode="COPY", embed_textures=True, object_types={"ARMATURE", "MESH"},
        )
    except Exception as e:  # FBX add-on missing in some bpy builds
        print("FBX export skipped:", e)
    info = {
        "name": NAME, "displayName": "Spirit Wolf", "fps": W.FPS, "source": os.path.basename(SRC),
        "facing": "-Z in glTF (-Y in Blender)", "bones": W.BONES, "legs": W.LEGS,
        "clips": {
            n: {"duration": d, "frames": round(d * W.FPS) + 1, "loop": lp, "markers": m, "family": fam,
                "note": wolf_clips.NOTES.get(n, ""), "min_z": report[n]["min_z"]}
            for n, fn, d, lp, m, fam in wolf_clips.CLIPS
        },
    }
    with open(os.path.join(OUT, NAME + "_clips.json"), "w") as fh:
        json.dump(info, fh, indent=1)
    print("EXPORTED", glb, os.path.getsize(glb))
    sys.path.insert(0, os.path.join(PET, "..", "_shared"))
    from register import register_all  # noqa: E402

    register_all(os.path.dirname(PET))  # the site picks the new export up by itself
