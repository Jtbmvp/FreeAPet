"""Moon Kitsune rig map (Meshy SmartRig, 43 bones). Faces -Y, +X is its left."""

BONES = {
    "root": "Bone_000", "pelvis": "Bone_001",
    "spine1": "Bone_004", "spine2": "Bone_003", "spine3": "Bone_002",
    "chest": "Bone_021", "neck1": "Bone_020", "neck2": "Bone_026", "head": "Bone_025", "crown": "Bone_024",
    "ear_L": "Bone_040", "ear_L_tip": "Bone_039", "ear_R": "Bone_042", "ear_R_tip": "Bone_041",
    "tailbase": "Bone_023", "tailhub": "Bone_022",
}
# 8 tails: alias -> (bones from base to tip). Side: +1 left, -1 right, 0 centre.
TAILS = {
    "tA": (["Bone_019", "Bone_018", "Bone_017"], 0),
    "tB": (["Bone_014", "Bone_013"], 1), "tC": (["Bone_016", "Bone_015"], -1),
    "tD": (["Bone_038", "Bone_037"], -1),
    "tE": (["Bone_036", "Bone_035"], 1), "tF": (["Bone_034", "Bone_033"], -1),
    "tG": (["Bone_010", "Bone_009"], 1), "tH": (["Bone_012", "Bone_011"], -1),
}
for _a, (_bs, _s) in TAILS.items():
    for _i, _b in enumerate(_bs):
        BONES[f"{_a}{_i}"] = _b

LEGS = {
    "FL": [["Bone_032", "Bone_031", "Bone_030"]],
    "FR": [["Bone_029", "Bone_028", "Bone_027"]],
    "HL": [["Bone_006", "Bone_005"]],
    "HR": [["Bone_008", "Bone_007"]],
}
GUESS = {"FL": (0.15, -0.3), "FR": (0.15, -0.3), "HL": (-0.15, 0.3), "HR": (-0.15, 0.3)}
# The tail hub hangs off the front spine bone in the rig: make it ride the pelvis.
FOLLOW = {"Bone_023": "Bone_001"}
