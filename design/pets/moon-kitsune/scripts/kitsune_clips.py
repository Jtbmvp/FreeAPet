"""The six Moon Kitsune clips. Each function fills a Pose for time t (seconds).

Attack families (for the VFX pass):
  Attack_FoxfireVolley  projectile - fans the tails, whips them forward: one foxfire orb per tail
  Attack_LunarCrescent  slash      - hops into a full spin, the tails trace a crescent arc
  Attack_EclipseNova    radial     - opens the tails into a moon disc, slams down a nova
"""

import math

from kitsune_rig import TAILS
from petrig import kf, wave


def tails(p, fn):
    """fn(index, side, segment) -> (pitch, yaw, roll) added to that tail segment."""
    for i, (alias, (bones, side)) in enumerate(TAILS.items()):
        for s in range(len(bones)):
            p.rot(f"{alias}{s}", *fn(i, side, s))


def ears(p, pitch=0.0, roll=0.0):
    for side, s in (("L", 1), ("R", -1)):
        p.rot(f"ear_{side}", pitch=pitch, roll=-s * roll)
        p.rot(f"ear_{side}_tip", pitch=0.5 * pitch)


# ------------------------------------------------------------------ Idle
def idle(t, p):
    b = wave(t, 2.0)
    look = wave(t, 4.0, 0.1)
    p.t.z = -0.006 + 0.005 * b
    p.rot("root", roll=0.7 * wave(t, 4.0, 0.25))
    p.rot("spine2", pitch=-0.8 * b)
    p.rot("chest", pitch=-0.8 * b, yaw=1.2 * look)
    p.rot("neck2", yaw=3 * look)
    p.rot("head", pitch=1.5 * b + 2 * wave(t, 4.0, 0.55), yaw=5 * look, roll=4 * wave(t, 4.0, 0.3))
    flick = kf(t, [(1.3, 0), (1.38, 1, "out"), (1.55, 0)]) + kf(t, [(3.1, 0), (3.17, 1, "out"), (3.3, 0)])
    p.rot("ear_L", roll=-10 * kf(t, [(1.3, 0), (1.38, 1, "out"), (1.55, 0)]))
    p.rot("ear_R", roll=10 * kf(t, [(3.1, 0), (3.17, 1, "out"), (3.3, 0)]))
    ears(p, pitch=1.5 * b - 2 * flick)
    tails(p, lambda i, side, s: (
        (2.5 + 2 * wave(t, 2.0, 0.3 + 0.07 * i)) * (s + 1) * 0.6,
        (5 + 1.5 * s) * wave(t, 4.0, 0.11 * i + 0.12 * s),
        side * 3 * wave(t, 4.0, 0.25 + 0.11 * i)))


# ------------------------------------------------------------------ Walk
WALK_T = 0.9
WALK_PHASE = {"HL": 0.0, "FL": 0.24, "HR": 0.5, "FR": 0.74}


def walk(t, p):
    stride, duty = 0.22, 0.6
    for leg, off in WALK_PHASE.items():
        ph = (t / WALK_T - off) % 1.0
        front = leg[0] == "F"
        L = p.legs[leg]
        if ph < duty:
            u = ph / duty
            L.dy = -stride / 2 + stride * u
            L.paw = 20 * kf(u, [(0.7, 0), (1.0, 1)]) if front else 0
        else:
            u = (ph - duty) / (1 - duty)
            L.dy = stride / 2 - stride * kf(u, [(0, 0), (1, 1)])
            L.dz = (0.085 if front else 0.07) * math.sin(math.pi * u) ** 0.9
            if front:
                L.paw = 20 * (1 - kf(u, [(0, 0), (0.5, 1)])) + 45 * math.sin(math.pi * min(1.0, u / 0.65)) \
                    - 10 * math.sin(math.pi * max(0.0, (u - 0.6) / 0.4))
    c = 2 * math.pi * t / WALK_T
    p.t.z = -0.02 + 0.009 * math.cos(2 * c + 0.6)
    p.t.x = 0.01 * math.sin(c + 0.4)
    p.rot("root", pitch=1.2 * math.sin(2 * c + 1.2), roll=1.5 * math.sin(c + 0.4))
    p.rot("pelvis", yaw=3 * math.sin(c), roll=2 * math.sin(c + 0.9))
    p.rot("chest", yaw=-3 * math.sin(c + 1.5), roll=-1.5 * math.sin(c + 1.9))
    p.rot("head", pitch=1 + 2.5 * math.sin(2 * c + 2.3), yaw=2.5 * math.sin(c + 1.5), roll=2 * math.sin(c + 1.2))
    ears(p, pitch=2 * math.sin(2 * c + 1.0))
    tails(p, lambda i, side, s: (
        (3 + 2.5 * math.sin(2 * c + 1.0 - 0.4 * i)) * (0.5 + s),
        (5 + 3 * s) * math.sin(c - 0.6 - 0.3 * i - 0.6 * s),
        side * 2 * math.sin(2 * c + 0.3 * i)))


# ------------------------------------------------------------------ Attack 1: Foxfire Volley (projectile)
def foxfire_volley(t, p):
    charge = kf(t, [(0, 0), (0.62, 1, "out")])
    whip = kf(t, [(0.62, 0), (0.78, 1, "in3"), (0.95, 0.85), (1.8, 0)])
    charge *= 1 - kf(t, [(0.62, 0), (0.8, 1)])
    hold = kf(t, [(0.25, 0), (0.45, 1), (0.62, 1), (0.7, 0)])
    quiver = hold * math.sin(t * 2 * math.pi * 9)
    p.t.z = -0.07 * charge - 0.03 * whip
    p.t.y = 0.03 * charge - 0.07 * whip
    p.rot("root", pitch=-3 * charge + 6 * whip)
    p.rot("spine2", pitch=4 * charge - 4 * whip)
    p.rot("chest", pitch=-6 * charge + 6 * whip)
    p.rot("head", pitch=-14 * charge + 18 * whip + 1.0 * quiver, roll=kf(t, [(0.6, 0), (0.8, -6), (1.2, 0)]))
    ears(p, pitch=-14 * charge + 8 * whip, roll=12 * charge)
    tails(p, lambda i, side, s: (
        (-10 * charge + 34 * whip) * (0.6 + 0.4 * s) + 2.0 * quiver,
        side * 4 * quiver * 0.3,
        side * (18 * charge - 8 * whip) * (1.0 - 0.3 * s)))
    for leg in ("FL", "FR"):
        p.legs[leg].dy = -0.05 * whip
        p.legs[leg].paw = -12 * whip


# ------------------------------------------------------------------ Attack 2: Lunar Crescent (slash)
FOLD = {
    "FL": [(-35, 0, 0), (75, 0, 0), (35, 0, 0)], "FR": [(-35, 0, 0), (75, 0, 0), (35, 0, 0)],
    "HL": [(40, 0, 0), (-70, 0, 0)], "HR": [(40, 0, 0), (-70, 0, 0)],
}


def lunar_crescent(t, p):
    crouch = kf(t, [(0, 0), (0.30, 1, "out"), (0.38, 0, "in")]) + kf(t, [(0.80, 0), (0.88, 0.8, "out"), (1.25, 0)])
    air = kf(t, [(0.32, 0), (0.56, 1, "out"), (0.82, 0, "in")])
    spin = kf(t, [(0.40, 0), (0.80, 360, "s")])
    rate = kf(t, [(0.40, 0), (0.60, 1), (0.80, 0)])
    p.t.z = -0.09 * crouch + 0.2 * air
    p.rot("root", yaw=spin, pitch=4 * crouch, roll=-8 * rate)
    p.rot("chest", yaw=-10 * rate, pitch=-4 * air)
    p.rot("head", pitch=8 * crouch - 6 * air, yaw=-12 * rate + kf(t, [(0.85, 0), (1.0, 8), (1.4, 0)]))
    ears(p, pitch=-12 * air, roll=10 * air)
    tails(p, lambda i, side, s: (
        -6 * air * (0.5 + s),
        -38 * rate * (0.7 + 0.5 * s) + side * 6 * crouch,
        side * 22 * air * (1 - 0.3 * s)))
    w = kf(t, [(0.36, 0), (0.44, 1), (0.78, 1), (0.84, 0)])
    for leg, fk in FOLD.items():
        L = p.legs[leg]
        L.w, L.fk = w, fk
        L.paw = 10 * crouch if leg[0] == "F" else 0


# ------------------------------------------------------------------ Attack 3: Eclipse Nova (radial)
def eclipse_nova(t, p):
    charge = kf(t, [(0, 0), (0.75, 1, "out"), (0.95, 0, "in")])
    lift = kf(t, [(0.70, 0), (0.85, 1, "out"), (0.97, 0, "in3")])
    slam = kf(t, [(0.90, 0), (0.98, 1, "in3"), (1.25, 0.75), (2.2, 0)])
    hold = kf(t, [(0.3, 0), (0.5, 1), (0.75, 1), (0.85, 0)])
    hum = hold * math.sin(t * 2 * math.pi * 7)
    shake = kf(t, [(0.98, 1), (1.35, 0)]) * math.sin((t - 0.98) * 2 * math.pi * 12)
    p.t.z = -0.05 * charge - 0.08 * slam + 0.004 * shake
    p.t.y = 0.04 * charge - 0.03 * slam
    p.rot("root", pitch=-7 * charge - 6 * lift + 7 * slam)
    p.rot("spine2", pitch=-4 * charge + 4 * slam)
    p.rot("chest", pitch=-8 * charge + 6 * slam + 0.6 * hum)
    p.rot("head", pitch=-32 * charge + 30 * slam + 1.5 * hum + 1.5 * shake, roll=1.5 * shake)
    ears(p, pitch=-10 * charge + 6 * slam, roll=-8 * charge + 14 * slam)
    open_ = kf(t, [(0.1, 0), (0.75, 1, "out"), (0.98, 1.35, "out"), (1.5, 0.4), (2.2, 0)])
    tails(p, lambda i, side, s: (
        (-16 * open_ + 12 * slam) * (0.6 + 0.4 * s) + 1.5 * hum + 2 * shake,
        side * 2 * hum,
        side * 26 * open_ * (1 - 0.25 * s) * (0.45 if i >= 6 else 1.0)))
    for leg in ("FL", "FR"):
        L = p.legs[leg]
        L.dz = 0.17 * lift
        L.dy = 0.05 * lift - 0.05 * slam
        L.dx = (1 if leg == "FL" else -1) * 0.03 * slam
        L.paw = 35 * lift - 15 * slam


# ------------------------------------------------------------------ Fainted
def fainted(t, p):
    hitr = kf(t, [(0, 0), (0.12, 1, "out"), (0.45, 0.2), (0.9, 0)])
    stag = kf(t, [(0.2, 0), (0.5, 1), (0.95, 1), (1.3, 0)])
    sway = stag * math.sin((t - 0.2) * 2 * math.pi / 0.62)
    front = kf(t, [(0.85, 0), (1.22, 1, "in"), (1.34, 0.93, "out"), (1.46, 1, "in"), (2.5, 1)])
    back = kf(t, [(1.05, 0), (1.48, 1, "in"), (1.60, 0.94, "out"), (1.72, 1, "in"), (2.5, 1)])
    down = 0.5 * (front + back)
    hd = kf(t, [(1.0, 0), (1.42, 1, "in"), (1.52, 0.86, "out"), (1.64, 1, "in"), (2.5, 1)])
    p.t.z = -0.04 * hitr - 0.02 * stag * (1 - down) - 0.22 * down
    p.t.y = 0.06 * hitr + 0.02 * stag * (1 - down)
    p.t.x = 0.035 * sway * (1 - down) + 0.02 * down
    p.rot("root", pitch=-4 * hitr + 10 * (front - back), roll=5 * sway * (1 - down) + 3 * down)
    p.rot("chest", pitch=-4 * hitr + 4 * front, yaw=6 * down)
    p.rot("head", pitch=-22 * hitr + 10 * stag * (1 - hd) + 30 * hd, yaw=-10 * hitr + 6 * sway * (1 - hd) + 16 * hd,
          roll=-4 * sway * (1 - hd) + 26 * hd)
    ears(p, pitch=-8 * hitr - 16 * hd, roll=20 * hd)
    limp = kf(t, [(1.0, 0), (1.5, 1), (2.5, 1)])
    tails(p, lambda i, side, s: (
        (8 * hitr) * (1 - limp) - limp * (14 if i < 6 else -12) * (0.6 + 0.4 * s),
        6 * sway * (1 - limp) + limp * 10,
        side * (6 * hitr - (10 if i < 6 else 20) * limp)))
    for leg in ("FL", "FR"):
        L = p.legs[leg]
        L.dy = -0.18 * front + (0.015 if leg == "FL" else -0.015) * sway
        L.dx = (1 if leg == "FL" else -1) * 0.04 * front
        L.paw = -70 * front
    for leg in ("HL", "HR"):
        L = p.legs[leg]
        L.dy = -0.06 * back + (-0.015 if leg == "HL" else 0.015) * sway
        L.dx = (1 if leg == "HL" else -1) * 0.06 * back


NOTES = {
    "Idle": "Respira, mexe as orelhas e ondula as oito caudas, cada uma com o seu atraso.",
    "Walk": "Passo leve a quatro tempos, no lugar. Marcadores step_* para sons de passos.",
    "Attack_FoxfireVolley": "Abre as caudas em leque a carregar e chicoteia-as para a frente. VFX: uma chama de "
                            "raposa na ponta de cada cauda durante a carga, disparadas no release.",
    "Attack_LunarCrescent": "Encolhe-se, salta e dá uma volta completa no ar com as caudas a arrastar. VFX: arco "
                            "de lua crescente a seguir as caudas, corte no impact (aterragem).",
    "Attack_EclipseNova": "Olha para a lua e abre as caudas num disco; ergue as patas e esmaga o chão. VFX: disco "
                          "lunar atrás das caudas durante a carga, nova radial no impact.",
    "Fainted": "Recua com o golpe, cambaleia e deita-se com as caudas caídas; fica na pose final.",
}

CLIPS = [
    ("Idle", idle, 4.0, True, {}, None),
    ("Walk", walk, WALK_T, True, {"step_HL": 0.0, "step_FL": 0.22, "step_HR": 0.45, "step_FR": 0.67}, None),
    ("Attack_FoxfireVolley", foxfire_volley, 1.8, False, {"release": 0.74, "impact": 0.95}, "projectile"),
    ("Attack_LunarCrescent", lunar_crescent, 1.6, False, {"release": 0.38, "impact": 0.82}, "slash"),
    ("Attack_EclipseNova", eclipse_nova, 2.2, False, {"release": 0.85, "impact": 0.98}, "radial"),
    ("Fainted", fainted, 2.5, False, {"ground": 1.46}, None),
]
