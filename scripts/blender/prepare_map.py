"""Prepares the Claude Design map GLB for the Roblox 3D Importer.

Run inside Blender. Same colour/UV bake as the pets (see stud_bake.py);
the map is already in studs (1 unit = 1 stud), so no scaling.
"""

import os

import bpy

HERE = "/home/jbernardo/Projetos/FreeAPet/scripts/blender"
exec(open(os.path.join(HERE, "stud_bake.py")).read())

SRC = "/home/jbernardo/Documentos/FreeAPet-models/free_a_pet_map.glb"
OUT = "/home/jbernardo/Documentos/FreeAPet-models/FreeAPet_Map_ready.glb"


def main():
    scene = bpy.data.scenes.get("FreeAPet_Map") or bpy.data.scenes.new("FreeAPet_Map")
    bpy.context.window.scene = scene
    for o in list(scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in scene.objects if o.type == "MESH"]
    materials = bake_objects(meshes, "map")
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    biggest = max(meshes, key=lambda o: sum(len(p.vertices) - 2 for p in o.data.polygons))
    big_tris = sum(len(p.vertices) - 2 for p in biggest.data.polygons)
    export_scene(OUT)
    print(f"map: {len(meshes)} meshes, {materials} materials, {tris} triangles, biggest {biggest.name} {big_tris} tris")
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


main()
