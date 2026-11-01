"""Shared helpers for preparing Claude Design GLBs for the Roblox 3D Importer.

The Roblox importer ignores glTF colour factors and texture transforms, so
every material is rebuilt as ONE image wired straight into Base Color: the
grey stud texture multiplied by the material colour (or a 4x4 solid colour
when there is no texture), and the texture repeat is baked into the UVs.
Load with exec(open(<this file>).read()) from the prepare_* scripts.
"""

import bpy


def lin_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def bake_material(mat, prefix):
    """Rebuilds mat in place; returns the UV scale its texture used."""
    nt = mat.node_tree
    # Lit materials colour the Principled BSDF; unlit ones (glows, beams,
    # signs: KHR_materials_unlit) colour an Emission node instead.
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        base = bsdf.inputs["Base Color"]
    else:
        emission = next((n for n in nt.nodes if n.type == "EMISSION"), None)
        if emission is None:
            return (1.0, 1.0)
        base = emission.inputs["Color"]
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


def bake_objects(objects, prefix):
    """Gives these mesh objects their own baked material copies and scales their UVs."""
    baked = {}  # original material name -> (new material, uv scale)
    for o in objects:
        for slot in o.material_slots:
            if slot.material is None:
                continue
            name = slot.material.name
            if name not in baked:
                mat = slot.material.copy()
                mat.name = f"{prefix}_{name}"
                baked[name] = (mat, bake_material(mat, prefix))
            slot.material = baked[name][0]
    scale_by_mat = {mat: scale for mat, scale in baked.values()}
    for o in objects:
        me = o.data
        if not me.uv_layers:
            continue
        uv = me.uv_layers.active.data
        for poly in me.polygons:
            mat = o.material_slots[poly.material_index].material if o.material_slots else None
            sx, sy = scale_by_mat.get(mat, (1.0, 1.0))
            if sx == 1.0 and sy == 1.0:
                continue
            for li in poly.loop_indices:
                u, v = uv[li].uv
                uv[li].uv = (u * sx, v * sy)
    return len(baked)


def export_scene(path):
    for o in bpy.context.scene.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=True,
    )
