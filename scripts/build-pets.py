#!/usr/bin/env python3
"""Builds design/pets/FreeAPetPets.rbxmx from design/pets/pets.json.

pets.json is extracted from the Claude Design pet sheets (the PARTS tables
of *-model-*.js at adult size): meters, y-up, facing +Z, Euler XYZ radians.
Every piece becomes a plain Roblox Part with studs on top, like the map
export: boxes -> blocks, lathes -> cylinders, 4-sided pyramid ears -> two
stacked blocks. The model is turned to face -Z (Roblox forward), scaled to
studs, centred on X/Z and rests on Y = 0. AnimalFactory welds the parts to
its own root, so parts are unanchored and non-colliding here.

Usage: python3 scripts/build-pets.py
"""

import json
import math
import os
from xml.sax.saxutils import escape

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "design/pets/pets.json")
OUT = os.path.join(ROOT, "design/pets/FreeAPetPets.rbxmx")

STUDS_PER_METER = 1.8
MATERIAL = {"stud": 256, "ink": 272, "iris": 272, "white": 272}  # Plastic / SmoothPlastic
SURFACE_STUDS, SURFACE_SMOOTH = 3, 0
SHAPE_BLOCK, SHAPE_CYLINDER = 1, 2


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def apply(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


# Pets face +Z in the design; Roblox models look down -Z.
TURN = ry(math.pi)


def pieces(prim):
    """Expands one primitive into Roblox parts: (name, size, pos, rot, color, material, shape)."""
    name, kind, size, pos, rot, color, mat = prim
    size = [v * STUDS_PER_METER for v in size]
    pos = apply(TURN, [v * STUDS_PER_METER for v in pos])
    r = matmul(TURN, matmul(rx(rot[0]), matmul(ry(rot[1]), rz(rot[2]))))
    if kind == "B":
        return [(name, size, pos, r, color, mat, SHAPE_BLOCK)]
    if kind == "C":
        # Roblox cylinders run along local X; the lathe axis is local Y.
        return [(name, size, pos, matmul(r, rz(math.pi / 2)), color, mat, SHAPE_CYLINDER)]
    # "E": a 4-sided pyramid (centred on its middle) as a wide base + narrow top.
    w, h, _ = size
    out = []
    for suffix, scale, height, dy in (("", 1.0, h * 0.55, -h * 0.225), ("_tip", 0.5, h * 0.45, h * 0.275)):
        offset = apply(r, [0, dy, 0])
        out.append((name + suffix, [w * scale, height, w * scale], [pos[i] + offset[i] for i in range(3)], r, color, mat, SHAPE_BLOCK))
    return out


def corners(size, pos, r):
    hx, hy, hz = (v / 2 for v in size)
    for sx in (-hx, hx):
        for sy in (-hy, hy):
            for sz in (-hz, hz):
                d = apply(r, [sx, sy, sz])
                yield [pos[i] + d[i] for i in range(3)]


def color_uint(hexstr):
    h = hexstr.lstrip("#")
    return 0xFF000000 | int(h, 16)


def part_xml(ref, name, size, pos, r, color, mat, shape):
    cf = "".join(f"<R{i}{j}>{r[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    top = SURFACE_STUDS if mat == "stud" else SURFACE_SMOOTH
    return (
        f'<Item class="Part" referent="RBX{ref}"><Properties>'
        f'<string name="Name">{escape(name)}</string>'
        f"<bool name=\"Anchored\">false</bool>"
        f'<CoordinateFrame name="CFrame"><X>{pos[0]:.4f}</X><Y>{pos[1]:.4f}</Y><Z>{pos[2]:.4f}</Z>{cf}</CoordinateFrame>'
        f'<Vector3 name="size"><X>{size[0]:.4f}</X><Y>{size[1]:.4f}</Y><Z>{size[2]:.4f}</Z></Vector3>'
        f'<Color3uint8 name="Color3uint8">{color_uint(color)}</Color3uint8>'
        f'<token name="Material">{MATERIAL[mat]}</token>'
        f'<token name="TopSurface">{top}</token><token name="BottomSurface">{SURFACE_SMOOTH}</token>'
        f'<token name="shape">{shape}</token>'
        f'<bool name="CanCollide">false</bool><bool name="Massless">true</bool><bool name="CastShadow">true</bool>'
        f"</Properties></Item>"
    )


def main():
    pets = json.load(open(SRC))
    ref = 0
    models = []
    for pet_id, data in pets.items():
        parts = [p for prim in data["prims"] for p in pieces(prim)]
        pts = [c for (_, size, pos, r, *_rest) in parts for c in corners(size, pos, r)]
        cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
        cz = (min(p[2] for p in pts) + max(p[2] for p in pts)) / 2
        y0 = min(p[1] for p in pts)
        items = []
        for name, size, pos, r, color, mat, shape in parts:
            ref += 1
            items.append(part_xml(ref, name, size, [pos[0] - cx, pos[1] - y0, pos[2] - cz], r, color, mat, shape))
        ref += 1
        height = max(p[1] for p in pts) - y0
        # Upright pivot at the feet. Without it Roblox takes a part's rotation as
        # the model pivot and the whole pet tips over when moved.
        pivot = (
            '<OptionalCoordinateFrame name="WorldPivotData"><CFrame><X>0</X><Y>0</Y><Z>0</Z>'
            "<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12>"
            "<R20>0</R20><R21>0</R21><R22>1</R22></CFrame></OptionalCoordinateFrame>"
        )
        models.append(
            f'<Item class="Model" referent="RBX{ref}"><Properties><string name="Name">{pet_id}</string>{pivot}</Properties>'
            + "".join(items)
            + "</Item>"
        )
        print(f"{pet_id}: {len(parts)} parts, {height:.2f} studs tall")
    ref += 1
    xml = (
        '<roblox version="4">'
        f'<Item class="Folder" referent="RBX{ref}"><Properties><string name="Name">Animals</string></Properties>'
        + "".join(models)
        + "</Item></roblox>"
    )
    open(OUT, "w").write(xml)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
