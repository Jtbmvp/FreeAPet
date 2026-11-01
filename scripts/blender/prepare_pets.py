"""Prepares the Claude Design pet GLBs for the Roblox 3D Importer.

Run inside Blender (MCP or Text Editor). Reads every pet GLB in SRC_DIR,
builds one scene with the six pets side by side and writes OUT_FILE:
  * each material gets ONE image wired straight into Base Color: the grey
    stud texture already multiplied by the material colour (Roblox ignores
    the design's Mix/Multiply node), or a 4x4 solid colour;
  * the texture repeat (Mapping node) is baked into the UVs;
  * mesh data is renamed after its object (head, tail_1...), because the
    importer names MeshParts after the mesh, and the rig needs the names;
  * each pet root is renamed to its SpeciesId and scaled to studs;
  * animations are left out (Roblox ignores rigid-node clips; the game
    plays them from data instead).
"""

import os

import bpy

SRC_DIR = "/home/jbernardo/Documentos/FreeAPet-models"
OUT_FILE = "/home/jbernardo/Documentos/FreeAPet-models/FreeAPet_Pets_ready.glb"
STUDS_PER_METER = 1.8
SPECIES = {
    "acorn": "AcornSquirrel",
    "hopping": "HoppingMushroom",
    "branch": "BranchDeer",
    "running": "RunningCactus",
    "ball": "BallScorpion",
    "sun": "SunCamel",
}


def lin_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def bake_material(mat, prefix):
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    base = bsdf.inputs["Base Color"]
    factor = list(base.default_value)[:3]
    tex, scale = None, (1.0, 1.0)
    if base.is_linked:
        src = base.links[0].from_node
        if src.type == "MIX":
            if not src.inputs["B"].is_linked:
                factor = list(src.inputs["B"].default_value)[:3]
            a = src.inputs["A"]
            if a.is_linked and a.links[0].from_node.type == "TEX_IMAGE":
                tex = a.links[0].from_node
        elif src.type == "TEX_IMAGE":
            tex = src
    if tex is not None:
        vec = tex.inputs["Vector"]
        if vec.is_linked and vec.links[0].from_node.type == "MAPPING":
            s = vec.links[0].from_node.inputs["Scale"].default_value
            scale = (s[0], s[1])
        w, h = tex.image.size
        px = list(tex.image.pixels)
        out = [0.0] * len(px)
        for i in range(0, len(px), 4):
            for k in range(3):
                out[i + k] = lin_to_srgb(min(1.0, srgb_to_lin(px[i + k]) * factor[k]))
            out[i + 3] = 1.0
    else:
        w = h = 4
        out = ([lin_to_srgb(min(1.0, c)) for c in factor] + [1.0]) * (w * h)
    img = bpy.data.images.new(f"{prefix}_{mat.name}", w, h)
    img.pixels[:] = out
    img.pack()
    for n in list(nt.nodes):
        if n.type in ("MIX", "MAPPING", "TEX_IMAGE", "UVMAP"):
            nt.nodes.remove(n)
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = img
    node.interpolation = "Linear" if tex is not None else "Closest"
    nt.links.new(node.outputs["Color"], base)
    return scale


def species_for(filename):
    low = filename.lower()
    for key, species in SPECIES.items():
        if low.startswith(key):
            return species
    return None


def main():
    scene = bpy.data.scenes.get("FreeAPet_Pets") or bpy.data.scenes.new("FreeAPet_Pets")
    bpy.context.window.scene = scene
    for o in list(scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)

    files = sorted(f for f in os.listdir(SRC_DIR) if f.endswith(".glb") and species_for(f))
    offset = 0.0
    for f in files:
        species = species_for(f)
        before = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(SRC_DIR, f))
        new = [o for o in scene.objects if o not in before]
        roots = [o for o in new if o.parent is None]
        root = roots[0]
        root.name = species

        # Each pet's materials are copies, so one pet's bake never touches another's.
        meshes = [o for o in new if o.type == "MESH"]
        scales = {}
        for o in meshes:
            for slot in o.material_slots:
                if slot.material and slot.material.name not in scales:
                    mat = slot.material.copy()
                    mat.name = f"{species}_{slot.material.name}"
                    scales[slot.material.name] = (mat, bake_material(mat, species))
                if slot.material:
                    mat, _ = scales[slot.material.name]
                    slot.material = mat
        for o in meshes:
            me = o.data.copy()
            me.name = o.name
            o.data = me
            uv = me.uv_layers.active.data if me.uv_layers else None
            if uv is None:
                continue
            for poly in me.polygons:
                mat = o.material_slots[poly.material_index].material
                key = next((k for k, v in scales.items() if v[0] == mat), None)
                sx, sy = scales[key][1] if key else (1.0, 1.0)
                for li in poly.loop_indices:
                    u, v = uv[li].uv
                    uv[li].uv = (u * sx, v * sy)

        root.scale = [s * STUDS_PER_METER for s in root.scale]
        root.location.x += offset
        offset += 6.0
        print(f"{f} -> {species}: {len(meshes)} meshes, {len(scales)} materials")

    for o in scene.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_FILE,
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=True,
    )
    print("wrote", OUT_FILE, os.path.getsize(OUT_FILE), "bytes")


main()
