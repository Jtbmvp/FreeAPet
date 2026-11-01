#!/usr/bin/env python3
"""Writes every image embedded in a GLB to a folder, named <index>_<first material>.png.
Usage: python3 -I scripts/extract-glb-images.py file.glb out_dir"""
import json, struct, sys, os
path, out = sys.argv[1], sys.argv[2]
b = open(path,'rb').read()
n = struct.unpack_from('<I', b, 12)[0]; g = json.loads(b[20:20+n])
off = 20 + n; bl = struct.unpack_from('<I', b, off)[0]; blob = b[off+8:off+8+bl]
os.makedirs(out, exist_ok=True)
names = {}
for mi, m in enumerate(g.get('materials', [])):
    pbr = m.get('pbrMetallicRoughness', {})
    t = pbr.get('baseColorTexture', {}).get('index')
    if t is not None:
        img = g['textures'][t]['source']
        names.setdefault(img, []).append(m['name'])
for i, im in enumerate(g.get('images', [])):
    v = g['bufferViews'][im['bufferView']]
    data = blob[v.get('byteOffset',0): v.get('byteOffset',0)+v['byteLength']]
    mats = names.get(i, ['unused'])
    fn = os.path.join(out, f"{i:03d}_{mats[0]}.png")
    open(fn,'wb').write(data)
print(len(g.get('images', [])), "images")
