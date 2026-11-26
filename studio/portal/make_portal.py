# Portal de viagem (FreeAPet). Corre com:
#   blender -b --factory-startup --python make_portal.py -- <out_dir>
# 1 unidade = 1 stud. Z para cima. A boca do portal olha para -Y. Origem = chao, centro do portal.
# Cada objeto vira uma MeshPart no Roblox (cores/material postos no Studio):
#   Base (pedra clara), Arch (pedra lilas), Runes (Neon, cor do bioma), Crystals (vidro/neon),
#   RingOuter / RingInner (rodam), Swirl (espiral, roda), Vortex (funil de profundidade).
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

RC = 9.6        # altura do centro do anel
RI, RO = 5.5, 7.7   # raio interior / exterior do arco
D = 2.6         # profundidade do arco (Y)
N = 14          # blocos do arco
GAP = 0.16      # meia-junta angular (graus convertidos abaixo)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)


def mat(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    return m


def finish(name, bm, rgb, bevel=0.0, seg=2):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat(name, rgb))
    if bevel > 0:
        md = ob.modifiers.new("bevel", 'BEVEL')
        md.width = bevel
        md.segments = seg
        md.limit_method = 'ANGLE'
        md.angle_limit = math.radians(30)
    return ob


def hexa(bm, v):
    vs = [bm.verts.new(p) for p in v]
    for f in [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]:
        bm.faces.new([vs[i] for i in f])


def box(bm, c, s):
    x, y, z = c
    a, b, h = s[0] / 2, s[1] / 2, s[2] / 2
    hexa(bm, [(x - a, y - b, z - h), (x + a, y - b, z - h), (x + a, y - b, z + h), (x - a, y - b, z + h),
              (x - a, y + b, z - h), (x + a, y + b, z - h), (x + a, y + b, z + h), (x - a, y + b, z + h)])


def ring_pt(r, a, y):  # anel no plano XZ, centro (0, y, RC)
    return Vector((r * math.cos(a), y, RC + r * math.sin(a)))


def cyl(bm, center, r, h, n=16, axis='Z'):
    rot = Matrix.Identity(3) if axis == 'Z' else Matrix.Rotation(math.radians(90), 3, 'X')
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=n, radius1=r, radius2=r, depth=h)
    bmesh.ops.transform(bm, matrix=rot.to_4x4(), verts=res['verts'])
    bmesh.ops.translate(bm, vec=Vector(center), verts=res['verts'])


def gem(bm, center, r, h_up, h_dn, n=6, tilt=0.0, ax='Y'):
    """bipiramide hexagonal (cristal)"""
    c = Vector(center)
    R = Matrix.Rotation(tilt, 3, ax)
    top = bm.verts.new(c + R @ Vector((0, 0, h_up)))
    bot = bm.verts.new(c + R @ Vector((0, 0, -h_dn)))
    mid_lo = [bm.verts.new(c + R @ Vector((r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n), -h_dn * 0.25))) for i in range(n)]
    mid_hi = [bm.verts.new(c + R @ Vector((r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n), h_up * 0.45))) for i in range(n)]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([mid_hi[i], mid_hi[j], top])
        bm.faces.new([mid_lo[j], mid_lo[i], bot])
        bm.faces.new([mid_lo[i], mid_lo[j], mid_hi[j], mid_hi[i]])


# ---------- Base: dois degraus com studs ----------
bm = bmesh.new()
cyl(bm, (0, 0, 0.45), 10.0, 0.9, n=24)
cyl(bm, (0, 0, 1.25), 8.4, 0.7, n=24)
for i in range(28):  # studs no degrau de baixo
    a = 2 * math.pi * i / 28
    cyl(bm, (9.2 * math.cos(a), 9.2 * math.sin(a), 1.05), 0.42, 0.3, n=10)
for i in range(20):  # studs no topo, fora da passagem
    a = 2 * math.pi * i / 20
    p = Vector((7.4 * math.cos(a), 7.4 * math.sin(a), 1.75))
    if abs(p.x) > 3.2:
        cyl(bm, p, 0.38, 0.3, n=10)
base = finish("Base", bm, (0.93, 0.9, 0.86), bevel=0.1, seg=1)

# ---------- Arco: blocos (voussoirs) com chave maior ----------
bm = bmesh.new()
step = 2 * math.pi / N
for i in range(N):
    a0 = math.pi / 2 - step / 2 + i * step + math.radians(1.2)
    a1 = a0 + step - math.radians(2.4)
    key = i == 0
    ro = RO + (0.9 if key else (0.35 if i % 2 else 0))
    dd = D / 2 + (0.35 if key else 0)
    hexa(bm, [ring_pt(RI, a0, -dd), ring_pt(RI, a1, -dd), ring_pt(ro, a1, -dd), ring_pt(ro, a0, -dd),
              ring_pt(RI, a0, dd), ring_pt(RI, a1, dd), ring_pt(ro, a1, dd), ring_pt(ro, a0, dd)])
# pes laterais (contrafortes) que abracam o anel
for s in (-1, 1):
    box(bm, (s * 7.6, 0, 3.4), (3.4, D + 1.2, 3.6))
    box(bm, (s * 7.9, 0, 5.6), (2.4, D + 0.6, 0.9))
box(bm, (0, 0, 1.95), (6.0, D + 0.8, 0.9))  # plinto debaixo do anel
arch = finish("Arch", bm, (0.72, 0.66, 0.86), bevel=0.3, seg=3)

# ---------- Runas (relevo na face da frente e de tras de cada bloco) ----------
bm = bmesh.new()


def glyph(kind, a, y, s):
    """desenha uma runa no plano tangente do bloco, na face y"""
    c = ring_pt((RI + RO) / 2, a, y)
    t = Vector((-math.sin(a), 0, math.cos(a)))  # tangente
    n = Vector((math.cos(a), 0, math.sin(a)))   # radial
    dy = Vector((0, -0.18 * s, 0))
    def quad(p0, p1, w):
        d = (p1 - p0).normalized()
        o = Vector((-d.z, 0, d.x)) * w / 2
        pts = [p0 - o, p1 - o, p1 + o, p0 + o]
        hexa(bm, [p for p in pts] + [p + dy for p in pts])
    if kind == 0:   # losango
        pts = [c + n * 0.55, c + t * 0.4, c - n * 0.55, c - t * 0.4]
        hexa(bm, pts + [p + dy for p in pts])
    elif kind == 1:  # barra com dois tracos
        quad(c - n * 0.6, c + n * 0.6, 0.18)
        quad(c - t * 0.35 + n * 0.25, c + t * 0.35 + n * 0.25, 0.16)
        quad(c - t * 0.35 - n * 0.25, c + t * 0.35 - n * 0.25, 0.16)
    else:            # chevron
        quad(c - t * 0.45 - n * 0.35, c + n * 0.45, 0.18)
        quad(c + n * 0.45, c + t * 0.45 - n * 0.35, 0.18)


for i in range(1, N):
    a = math.pi / 2 + i * step
    glyph(i % 3, a, -D / 2 + 0.01, 1)
    glyph((i + 1) % 3, a, D / 2 - 0.01, -1)
# olho na chave (losango grande)
for s, y in ((1, -D / 2 - 0.34), (-1, D / 2 + 0.34)):
    c = ring_pt(RO - 0.3, math.pi / 2, y)
    pts = [c + Vector((0, 0, 0.9)), c + Vector((0.6, 0, 0)), c + Vector((0, 0, -0.9)), c + Vector((-0.6, 0, 0))]
    hexa(bm, pts + [p + Vector((0, -0.2 * s, 0)) for p in pts])
# faixas nos pes
for s in (-1, 1):
    box(bm, (s * 7.6, -(D + 1.2) / 2 - 0.08, 3.6), (2.0, 0.18, 0.28))
    box(bm, (s * 7.6, -(D + 1.2) / 2 - 0.08, 2.9), (1.2, 0.18, 0.28))
runes = finish("Runes", bm, (0.55, 0.95, 1.0))

# ---------- Cristais ----------
bm = bmesh.new()
gem(bm, (0, 0, RC + RO + 2.6), 0.95, 2.4, 1.4)
gem(bm, (-1.2, 0, RC + RO + 1.5), 0.55, 1.4, 0.8, tilt=math.radians(28))
gem(bm, (1.2, 0, RC + RO + 1.5), 0.55, 1.4, 0.8, tilt=math.radians(-28))
for s in (-1, 1):
    gem(bm, (s * 7.9, 0, 7.0), 0.5, 1.2, 0.5)
crystals = finish("Crystals", bm, (0.75, 0.95, 1.0))


# ---------- Aneis ----------
def torus(bm, R, r, y, segs=64, ring=8):
    res = bmesh.ops.create_circle(bm, segments=ring, radius=r)
    prof = res['verts']
    # perfil no plano XY local -> varrer a volta do eixo Y
    verts_rows = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        row = []
        for v in prof:
            p = Vector((R + v.co.x, v.co.y, 0))
            q = Vector((p.x * math.cos(a), y + p.y, RC + p.x * math.sin(a)))
            row.append(bm.verts.new(q))
        verts_rows.append(row)
    for v in prof:
        bm.verts.remove(v)
    for k in range(segs):
        r0, r1 = verts_rows[k], verts_rows[(k + 1) % segs]
        for j in range(ring):
            jj = (j + 1) % ring
            bm.faces.new([r0[j], r1[j], r1[jj], r0[jj]])


bm = bmesh.new()
torus(bm, 8.05, 0.26, -1.9)
for i in range(8):
    a = 2 * math.pi * i / 8
    p = ring_pt(8.05, a, -1.9)
    gem(bm, p, 0.5, 0.55, 0.55, n=4, tilt=a, ax='Y')
ring_outer = finish("RingOuter", bm, (1.0, 0.85, 0.45))

bm = bmesh.new()
torus(bm, 5.05, 0.16, -1.25, ring=6)
for i in range(12):
    a = 2 * math.pi * i / 12
    c = ring_pt(5.05, a, -1.25)
    R = Matrix.Rotation(-a, 3, 'Y')
    pts = [c + R @ Vector(v) for v in ((-0.18, -0.12, -0.32), (0.18, -0.12, -0.32), (0.18, -0.12, 0.32), (-0.18, -0.12, 0.32))]
    hexa(bm, pts + [p + Vector((0, 0.24, 0)) for p in pts])
ring_inner = finish("RingInner", bm, (1.0, 0.95, 0.75))

# ---------- Espiral (5 bracos afunilados) ----------
bm = bmesh.new()
ARMS, STEPS, RMAX = 5, 26, 5.45
for k in range(ARMS):
    base_a = 2 * math.pi * k / ARMS
    left, right = [], []
    for s in range(STEPS + 1):
        u = s / STEPS
        r = 0.35 + u * (RMAX - 0.35)
        a = base_a + u * 2.6
        w = 0.95 * (1 - u) ** 0.8 + 0.08
        c = Vector((r * math.cos(a), 0, r * math.sin(a)))
        tang = Vector((-math.sin(a), 0, math.cos(a)))
        left.append(c + tang * w / 2)
        right.append(c - tang * w / 2)
    for s in range(STEPS):
        p = [left[s], left[s + 1], right[s + 1], right[s]]
        f = [Vector((q.x, -0.5, q.z + RC)) for q in p]
        b = [Vector((q.x, -0.42, q.z + RC)) for q in p]
        hexa(bm, f + b)
cyl(bm, (0, -0.46, RC), 0.75, 0.1, n=16, axis='Y')
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
swirl = finish("Swirl", bm, (1.0, 1.0, 1.0))

# ---------- Funil do vortice (profundidade) ----------
bm = bmesh.new()
SEG, RINGS = 40, 8
rows = []
for j in range(RINGS + 1):
    u = j / RINGS
    r = RI + 0.1 - (RI - 0.5) * (u ** 0.7)
    y = -0.2 + 3.6 * u
    twist = u * 1.2
    rows.append([bm.verts.new(Vector((r * math.cos(2 * math.pi * i / SEG + twist), y, RC + r * math.sin(2 * math.pi * i / SEG + twist)))) for i in range(SEG)])
for j in range(RINGS):
    for i in range(SEG):
        ii = (i + 1) % SEG
        bm.faces.new([rows[j][i], rows[j][ii], rows[j + 1][ii], rows[j + 1][i]])
cap = bm.verts.new(Vector((0, 3.6, RC)))
for i in range(SEG):
    bm.faces.new([rows[RINGS][i], rows[RINGS][(i + 1) % SEG], cap])
me = bpy.data.meshes.new("Vortex")
bm.to_mesh(me)
bm.free()
vortex = bpy.data.objects.new("Vortex", me)
bpy.context.collection.objects.link(vortex)
vortex.data.materials.append(mat("Vortex", (0.35, 0.2, 0.6)))
# normais viradas para quem olha de frente (-Y): para dentro do funil
for p in me.polygons:
    if p.normal.dot(Vector((0, -1, 0))) < 0 and p.normal.dot(Vector((p.center.x, 0, p.center.z - RC))) > 0:
        p.flip()
me.update()

all_objs = [base, arch, runes, crystals, ring_outer, ring_inner, swirl, vortex]
report = []
for o in all_objs:
    dg = bpy.context.evaluated_depsgraph_get()
    m = o.evaluated_get(dg).to_mesh()
    m.calc_loop_triangles()
    report.append(f"{o.name}: tris={len(m.loop_triangles)} dims={tuple(round(d, 2) for d in o.dimensions)}")
open(os.path.join(OUT, "portal_stats.txt"), "w").write("\n".join(report))
print("\n".join(report))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "portal.blend"))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "portal.fbx"), use_selection=True,
                         apply_unit_scale=True, apply_scale_options='FBX_SCALE_NONE',
                         axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE',
                         use_mesh_modifiers=True, add_leaf_bones=False, bake_space_transform=True)
try:
    bpy.ops.wm.obj_export(filepath=os.path.join(OUT, "portal.obj"), export_selected_objects=True,
                          forward_axis='NEGATIVE_Z', up_axis='Y', export_materials=True)
except Exception as e:
    print("obj export failed", e)

# ---------- renders ----------
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.display.shading.show_shadows = True
sc.render.resolution_x, sc.render.resolution_y = 1100, 900
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
bpy.context.active_object.data.materials.append(mat("Ground", (0.55, 0.75, 0.5)))
cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam


def shot(name, loc, target, lens=35):
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam_data.lens = lens
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


shot("render_front.png", (0, -42, 9), (0, 0, 9))
shot("render_34.png", (-26, -32, 16), (0, 0, 8.5))
shot("render_back.png", (22, 30, 12), (0, 0, 8.5))
print("DONE")
