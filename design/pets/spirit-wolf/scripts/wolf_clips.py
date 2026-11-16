"""The six Spirit Wolf clips. Each function fills a Pose for time t (seconds).

Attack families (for the VFX pass):
  Attack_SpiritPounce   slash   - leaps, rakes both forepaws down, snaps
  Attack_CrystalHowl    pulse   - charges the antler crystals, howls a shockwave
  Attack_RuneSlam       geyser  - rears up, slams the ground, crystals erupt ahead
"""

import math

from wolf_lib import kf, wave

HIND_SYM = {"HL": -0.07, "HR": 0.07}  # the rest pose has the hind paws staggered


# ------------------------------------------------------------------ Idle
def idle(t, p):
    b = wave(t, 2.0)  # breath
    look = wave(t, 4.0, 0.1)
    p.t.z = -0.008 + 0.006 * b
    p.t.x = 0.008 * wave(t, 4.0, 0.25)
    p.rot("root", roll=0.8 * wave(t, 4.0, 0.25))
    p.rot("spine", pitch=-0.9 * b, yaw=1.2 * look)
    p.rot("chest", pitch=-0.7 * b, yaw=1.5 * look)
    p.rot("head", pitch=1.6 * b + 2.0 * wave(t, 4.0, 0.55), yaw=6.5 * look, roll=2.5 * wave(t, 4.0, 0.3))
    p.rot("muzzle", pitch=0.8 * wave(t, 2.0, 0.35))
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"antler_{side}_tip", roll=s * 0.8 * wave(t, 2.0, 0.2), pitch=0.6 * wave(t, 4.0, 0.4))
    p.tail(
        pitch=[1.5 + 2.0 * wave(t, 2.0, 0.3 + 0.1 * i) for i in range(4)],
        yaw=[a * wave(t, 4.0, 0.15 * i) for i, a in enumerate((5, 7, 9, 12))],
    )


# ------------------------------------------------------------------ Walk
WALK_T = 1.0
WALK_PHASE = {"HL": 0.0, "FL": 0.22, "HR": 0.5, "FR": 0.72}


def walk(t, p):
    stride, duty = 0.28, 0.62
    for leg, off in WALK_PHASE.items():
        ph = (t / WALK_T - off) % 1.0
        front = leg[0] == "F"
        L = p.legs[leg]
        L.dy = HIND_SYM.get(leg, 0.0)
        if ph < duty:
            u = ph / duty
            L.dy += -stride / 2 + stride * u
            L.paw = 18 * kf(u, [(0.72, 0), (1.0, 1)])
            L.m = (4 if front else -3) * kf(u, [(0.7, 0), (1.0, 1)])
        else:
            u = (ph - duty) / (1 - duty)
            L.dy += stride / 2 - stride * kf(u, [(0, 0), (1, 1)])
            L.dz = (0.105 if front else 0.085) * math.sin(math.pi * u) ** 0.9
            L.paw = (
                18 * (1 - kf(u, [(0, 0), (0.5, 1)]))
                + 24 * math.sin(math.pi * min(1.0, u / 0.6))
                - 12 * math.sin(math.pi * max(0.0, (u - 0.55) / 0.45))
            )
            L.m = (4 if front else -3) * (1 - kf(u, [(0, 0), (0.4, 1)])) + (26 if front else 14) * math.sin(math.pi * u)
            L.toe = 10 * math.sin(math.pi * u)
    c = 2 * math.pi * t / WALK_T
    p.t.z = -0.038 + 0.011 * math.cos(2 * c + 0.6)
    p.t.x = 0.012 * math.sin(c + 0.4)
    p.rot("root", pitch=1.3 * math.sin(2 * c + 1.2), roll=1.6 * math.sin(c + 0.4))
    p.rot("pelvis", yaw=3.5 * math.sin(c), roll=2.0 * math.sin(c + 0.9))
    p.rot("spine", yaw=-2.5 * math.sin(c + 0.3))
    p.rot("chest", yaw=-3.0 * math.sin(c + 1.5), roll=-1.5 * math.sin(c + 1.9))
    p.rot("head", pitch=1.0 + 2.6 * math.sin(2 * c + 2.3), yaw=2.4 * math.sin(c + 1.5), roll=1.5 * math.sin(c + 1.2))
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"antler_{side}_tip", pitch=1.0 * math.sin(2 * c + 1.4), roll=s * 0.6 * math.sin(2 * c + 1.0))
    p.tail(
        pitch=[v + 2.5 * math.sin(2 * c + 1.0 - 0.5 * i) for i, v in enumerate((7, 4, 3, 2))],
        yaw=[a * math.sin(c - 0.6 - 0.55 * i) for i, a in enumerate((6, 9, 12, 15))],
    )


# ------------------------------------------------------------------ Attack 1: Spirit Pounce (slash)
def spirit_pounce(t, p):
    p.t.y = kf(t, [(0, 0), (0.40, 0.14), (0.56, -0.30, "in"), (0.66, -0.52, "out"), (0.96, -0.50),
                   (1.10, -0.26, "in"), (1.26, -0.02, "out"), (1.6, 0)])
    p.t.z = kf(t, [(0, 0), (0.40, -0.15), (0.54, 0.15, "out"), (0.66, -0.13, "in"), (0.80, -0.07), (0.96, -0.10),
                   (1.11, 0.03, "out"), (1.27, -0.08, "in"), (1.45, 0), (1.6, 0)])
    p.rot("root", pitch=kf(t, [(0, 0), (0.40, -7), (0.54, -15), (0.66, 11, "in"), (0.80, 4), (0.96, 3),
                               (1.11, -5), (1.27, 3), (1.6, 0)]))
    p.rot("spine", pitch=kf(t, [(0, 0), (0.40, 6), (0.54, -9), (0.66, 9, "in"), (0.9, 1), (1.6, 0)]))
    p.rot("chest", pitch=kf(t, [(0, 0), (0.40, 4), (0.54, -6), (0.66, 6, "in"), (0.9, 0), (1.6, 0)]))
    p.rot("head", pitch=kf(t, [(0, 0), (0.40, 14), (0.54, -20, "out"), (0.64, 24, "in3"), (0.80, 6), (0.96, 8),
                               (1.2, -3), (1.6, 0)]),
          roll=kf(t, [(0.5, 0), (0.64, -9), (0.85, 3), (1.1, 0)]))
    p.rot("muzzle", pitch=kf(t, [(0.3, 0), (0.54, -9), (0.64, 7, "in3"), (0.9, 0)]))
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"antler_{side}", roll=s * kf(t, [(0, 0), (0.40, -3), (0.56, 7, "out"), (0.66, -5, "in"), (0.9, 2), (1.2, 0)]))
        p.rot(f"antler_{side}_tip", pitch=kf(t, [(0.4, 0), (0.56, -6), (0.68, 9, "in"), (0.9, -3), (1.2, 0)]))
    tl = kf(t, [(0, 0), (0.40, 1), (0.56, 0.7), (0.68, 1.5, "in"), (0.96, 0.9), (1.27, 0.9), (1.6, 0)])
    sw = kf(t, [(0.6, 0), (0.7, 1), (1.3, 0)]) * math.sin((t - 0.6) * 14)
    p.tail(pitch=[tl * v for v in (26, 16, 10, 6)], yaw=[sw * v for v in (3, 6, 9, 12)])
    for leg in ("FL", "FR"):
        d = 0.0 if leg == "FL" else 0.035  # right paw rakes a beat later: a one-two slash
        L = p.legs[leg]
        tt = t - (d if t < 0.9 else 0.0)
        L.dy = kf(tt, [(0, 0), (0.40, 0), (0.47, -0.05), (0.56, -0.44, "out"), (0.64, -0.64, "in"), (0.98, -0.64),
                       (1.10, -0.32, "in"), (1.24, 0, "out"), (1.6, 0)])
        L.dz = kf(tt, [(0, 0), (0.40, 0), (0.50, 0.26, "out"), (0.575, 0.40), (0.64, 0, "in3"), (0.98, 0),
                       (1.10, 0.10, "out"), (1.24, 0, "in"), (1.6, 0)])
        L.dx = (1 if leg == "FL" else -1) * kf(tt, [(0.44, 0), (0.575, 0.07), (0.64, -0.03, "in"), (1.0, -0.03), (1.24, 0)])
        L.paw = kf(tt, [(0.40, 0), (0.50, 40), (0.575, -35), (0.64, 0, "in"), (0.98, 0), (1.10, 25), (1.24, 0)])
        L.m = kf(tt, [(0.40, 0), (0.50, 30), (0.575, -30), (0.64, 0, "in"), (0.98, 0), (1.10, 22), (1.24, 0)])
        L.toe = kf(tt, [(0.5, 0), (0.575, -20), (0.64, 12, "in"), (0.8, 0)])
    for leg in ("HL", "HR"):
        L = p.legs[leg]
        L.dy = kf(t, [(0, 0), (0.45, 0), (0.56, -0.12, "in"), (0.70, -0.50, "out"), (0.98, -0.50),
                      (1.13, -0.22, "in"), (1.27, 0, "out"), (1.6, 0)])
        L.dz = kf(t, [(0, 0), (0.45, 0), (0.57, 0.20, "out"), (0.70, 0, "in"), (0.98, 0), (1.13, 0.09, "out"),
                      (1.27, 0, "in"), (1.6, 0)])
        L.paw = kf(t, [(0.36, 0), (0.45, 22), (0.57, 45), (0.70, 0, "in"), (0.98, 0), (1.13, 22), (1.27, 0)])
        L.m = kf(t, [(0.45, 0), (0.57, 22), (0.70, 0, "in"), (1.6, 0)])


# ------------------------------------------------------------------ Attack 2: Crystal Howl (pulse)
def crystal_howl(t, p):
    charge = kf(t, [(0, 0), (0.70, 1, "out"), (0.92, 0, "in")])
    up = kf(t, [(0.70, 0), (0.92, 1, "back"), (1.75, 1), (2.4, 0)])
    hold = kf(t, [(0.9, 0), (1.0, 1), (1.6, 1), (1.85, 0)])
    buzz = charge * charge * math.sin(t * 2 * math.pi * 11)
    trem = hold * math.sin(t * 2 * math.pi * 8.5)
    p.t.z = -0.085 * charge - 0.06 * up + 0.004 * trem
    p.t.y = 0.05 * charge - 0.035 * up
    p.rot("root", pitch=2.5 * charge - 5.0 * up)
    p.rot("spine", pitch=9 * charge - 8 * up)
    p.rot("chest", pitch=6 * charge - 6 * up + 0.5 * trem)
    p.rot("head", pitch=30 * charge - 27 * up + 1.2 * trem,
          yaw=hold * 6 * math.sin((t - 0.95) * 2 * math.pi / 0.9) + 0.8 * buzz,
          roll=hold * 3 * math.sin((t - 0.95) * 2 * math.pi / 0.9 + 1.0))
    p.rot("muzzle", pitch=3 * charge - 7 * up + 1.0 * trem)
    p.rot("nose", pitch=-4 * up)
    flare = kf(t, [(0.70, 0), (0.92, 1, "back"), (1.7, 0.8), (2.2, 0)])
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"antler_{side}", roll=s * (-4 * charge + 10 * flare + 1.2 * buzz + 1.0 * trem), pitch=-3 * charge + 14 * up)
        p.rot(f"antler_{side}_tip", roll=s * (-5 * charge + 12 * flare + 2.0 * buzz + 1.6 * trem), pitch=4 * flare)
    tl = 0.55 * charge + up
    p.tail(pitch=[tl * v + (hold * 2.0 * math.sin(t * 2 * math.pi * 8.5 - 0.6 * i)) for i, v in enumerate((30, 22, 16, 12))],
           yaw=[hold * a * math.sin((t - 0.95) * 2 * math.pi / 0.9 - 0.4 * i) for i, a in enumerate((3, 5, 7, 9))])
    for leg in ("FL", "FR"):  # forepaws brace wider as the howl leaves
        L = p.legs[leg]
        L.dx = (1 if leg == "FL" else -1) * 0.03 * up
        L.dy = -0.03 * up


# ------------------------------------------------------------------ Attack 3: Rune Slam (geyser)
def rune_slam(t, p):
    rear = kf(t, [(0, 0), (0.14, -0.10), (0.46, 1, "out"), (0.60, 1.04), (0.74, 0, "in3"), (1.9, 0)])
    hit = kf(t, [(0.62, 0), (0.74, 1, "in3"), (0.92, 0.72), (1.12, 0.8), (1.55, 0.12), (1.9, 0)])
    shake = kf(t, [(0.74, 1), (1.15, 0)]) * math.sin((t - 0.74) * 2 * math.pi * 12)
    p.t.z = -0.05 * rear - 0.115 * hit + 0.006 * shake
    p.t.y = 0.09 * rear - 0.05 * hit
    p.rot("root", pitch=-34 * rear + 5 * hit)
    p.rot("spine", pitch=-13 * rear + 11 * hit)
    p.rot("chest", pitch=-6 * rear + 8 * hit)
    p.rot("head", pitch=24 * rear + 26 * hit + 1.5 * shake, roll=1.5 * shake)
    p.rot("muzzle", pitch=-5 * rear + 5 * hit)
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"antler_{side}", roll=s * (8 * rear - 6 * hit + 1.5 * shake))
        p.rot(f"antler_{side}_tip", roll=s * (9 * rear - 8 * hit + 2.5 * shake), pitch=-5 * rear + 8 * hit)
    p.tail(pitch=[max(0.0, rear) * a + 34 * hit * k + 2 * shake for a, k in zip((44, 14, 8, 5), (1.0, 0.7, 0.5, 0.35))],
           yaw=[3 * shake * k for k in (0.4, 0.7, 1.0, 1.3)])
    for leg in ("FL", "FR"):
        L = p.legs[leg]
        s = 1 if leg == "FL" else -1
        L.dz = kf(t, [(0, 0), (0.12, 0), (0.46, 0.62, "out"), (0.60, 0.70), (0.74, 0, "in3"), (1.9, 0)])
        L.dy = kf(t, [(0, 0), (0.12, 0), (0.46, 0.20, "out"), (0.60, 0.22), (0.74, -0.14, "in3"), (1.25, -0.14),
                      (1.45, -0.06, "in"), (1.62, 0, "out"), (1.9, 0)])
        L.dz += kf(t, [(1.25, 0), (1.45, 0.07, "out"), (1.62, 0, "in")]) if leg == "FL" else kf(t, [(1.35, 0), (1.55, 0.07, "out"), (1.72, 0, "in")])
        if leg == "FR":
            L.dy = kf(t, [(0, 0), (0.12, 0), (0.46, 0.20, "out"), (0.60, 0.22), (0.74, -0.14, "in3"), (1.35, -0.14),
                          (1.55, -0.06, "in"), (1.72, 0, "out"), (1.9, 0)])
        L.dx = s * kf(t, [(0.12, 0), (0.5, -0.03), (0.74, 0.05, "in"), (1.3, 0.05), (1.7, 0)])
        L.paw = kf(t, [(0.10, 0), (0.30, 50), (0.60, 35), (0.70, -25), (0.74, 0, "in"), (1.9, 0)])
        L.m = kf(t, [(0.10, 0), (0.30, 40), (0.60, 28), (0.70, -22), (0.74, 0, "in"), (1.9, 0)])
        L.toe = kf(t, [(0.3, 0), (0.6, 18), (0.74, 0)])
    for leg in ("HL", "HR"):
        L = p.legs[leg]
        L.paw = kf(t, [(0.2, 0), (0.5, 6), (0.74, 0)])


# ------------------------------------------------------------------ Fainted
def fainted(t, p):
    hitr = kf(t, [(0, 0), (0.12, 1, "out"), (0.45, 0.2), (0.9, 0)])
    stag = kf(t, [(0.2, 0), (0.5, 1), (0.95, 1), (1.3, 0)])
    sway = stag * math.sin((t - 0.2) * 2 * math.pi / 0.62)
    front = kf(t, [(0.85, 0), (1.22, 1, "in"), (1.34, 0.93, "out"), (1.46, 1, "in"), (2.6, 1)])
    back = kf(t, [(1.05, 0), (1.48, 1, "in"), (1.60, 0.94, "out"), (1.72, 1, "in"), (2.6, 1)])
    sigh = kf(t, [(1.9, 0), (2.15, 1), (2.45, 0)])
    down = 0.5 * (front + back)
    p.t.z = -0.05 * hitr - 0.03 * stag * (1 - down) - 0.31 * down + 0.004 * sigh
    p.t.y = 0.07 * hitr + 0.03 * stag * (1 - down) - 0.03 * down
    p.t.x = 0.045 * sway * (1 - down) + 0.03 * down
    p.rot("root", pitch=-4 * hitr + 15 * (front - back), roll=5 * sway * (1 - down) + 6 * down)
    p.rot("pelvis", roll=4 * back)
    p.rot("spine", pitch=-5 * hitr + 5 * (front - back), yaw=4 * down)
    p.rot("chest", pitch=4 * front, yaw=6 * down, roll=5 * down)
    hd = kf(t, [(1.0, 0), (1.42, 1, "in"), (1.52, 0.86, "out"), (1.64, 1, "in"), (2.6, 1)])
    p.rot("head", pitch=-24 * hitr + 12 * stag * (1 - hd) + 34 * hd - 1.5 * sigh,
          yaw=-10 * hitr + 7 * sway * (1 - hd) + 16 * hd, roll=-4 * sway * (1 - hd) + 24 * hd)
    p.rot("muzzle", pitch=-5 * hitr + 5 * hd)
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"antler_{side}", roll=s * (5 * hitr - 3 * hd))
        p.rot(f"antler_{side}_tip", roll=s * (6 * hitr) + 5 * hd, pitch=-6 * hitr + 5 * hd)
    limp = kf(t, [(1.0, 0), (1.42, 1), (2.6, 1)])
    twitch = kf(t, [(2.0, 0), (2.1, 1), (2.3, 0)])
    p.tail(pitch=[(8 * hitr + 3 * stag) * (1 - limp) + limp * v + twitch * w for v, w in zip((29, 6, 0, -6), (0, 2, 5, 9))],
           yaw=[(6 * sway * (1 - limp)) + limp * v for v in (10, 14, 16, 18)])
    for leg in ("FL", "FR"):  # sphinx fold: elbows down, forearms flat ahead
        L = p.legs[leg]
        s = 1 if leg == "FL" else -1
        L.dy = -0.19 * front + (0.02 * sway if leg == "FL" else -0.02 * sway)
        L.dx = s * 0.05 * front
        L.dz = -0.015 * front
        L.m = -86 * front
        L.paw = -45 * front
    for leg in ("HL", "HR"):  # hocks on the ground, paws flat and forward
        L = p.legs[leg]
        s = 1 if leg == "HL" else -1
        L.dy = (-0.05 - HIND_SYM[leg] * 0.5) * back + (-0.02 * sway if leg == "HL" else 0.02 * sway)
        L.dx = s * 0.07 * back
        L.dz = -0.11 * back
        L.m = -84 * back
        L.paw = -45 * back


NOTES = {
    "Idle": "Respira, olha em volta e abana a cauda devagar. Patas sempre plantadas.",
    "Walk": "Passo a quatro tempos, no lugar (sem deslocar a raiz). Marcadores step_* para sons de passos.",
    "Attack_SpiritPounce": "Encolhe-se, salta e rasga com as duas patas dianteiras antes de morder. VFX: rastos de garras "
                           "violeta nas patas, estilhaços de cristal na aterragem (impact).",
    "Attack_CrystalHowl": "Baixa a cabeça para carregar os cristais das hastes e solta um uivo. VFX: brilho crescente nas "
                          "hastes durante a carga, onda de choque radial no release/impact.",
    "Attack_RuneSlam": "Empina-se e esmaga o chão com as patas e as hastes. VFX: a runa do ombro acende no topo (release), "
                       "espigões de cristal irrompem à frente no impact.",
    "Fainted": "Recua com o golpe, cambaleia e cai de barriga; fica na pose final (não faz loop).",
}

CLIPS = [
    # name, function, duration (s), loop, markers (s), family
    ("Idle", idle, 4.0, True, {}, None),
    ("Walk", walk, WALK_T, True, {"step_HL": 0.0, "step_FL": 0.22, "step_HR": 0.5, "step_FR": 0.72}, None),
    ("Attack_SpiritPounce", spirit_pounce, 1.6, False, {"release": 0.42, "impact": 0.64}, "slash"),
    ("Attack_CrystalHowl", crystal_howl, 2.4, False, {"release": 0.86, "impact": 1.0}, "pulse"),
    ("Attack_RuneSlam", rune_slam, 1.9, False, {"release": 0.62, "impact": 0.74}, "geyser"),
    ("Fainted", fainted, 2.6, False, {"ground": 1.46}, None),
]
