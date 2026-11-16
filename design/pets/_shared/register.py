"""Rebuilds viewer/pets.json from every design/pets/<folder>/pet.json that has an exported GLB.

Runs on its own (python3 design/pets/_shared/register.py) and at the end of every pet build,
so the site lists new pets without editing anything by hand. The page polls pets.json and
refreshes itself when it changes.
"""

import glob
import json
import os

RARITY_ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]


def register_all(pets_dir):
    pets = []
    for meta_path in sorted(glob.glob(os.path.join(pets_dir, "*", "pet.json"))):
        folder = os.path.basename(os.path.dirname(meta_path))
        meta = json.load(open(meta_path, encoding="utf-8"))
        glb = os.path.join(pets_dir, folder, "export", meta["file"] + ".glb")
        if not os.path.exists(glb):
            continue
        clips_path = os.path.join(pets_dir, folder, "export", meta["file"] + "_clips.json")
        nclips = len(json.load(open(clips_path))["clips"]) if os.path.exists(clips_path) else 0
        exp = f"../{folder}/export/{meta['file']}"
        thumb = os.path.join(pets_dir, "viewer", "thumbs", meta["id"] + ".png")
        pets.append({
            "id": meta["id"], "name": meta["name"], "rarity": meta.get("rarity"), "biome": meta.get("biome"),
            "tags": meta.get("tags", []) + ([f"{nclips} animações"] if nclips else []),
            "model": exp + ".glb", "clips": exp + "_clips.json" if nclips else None,
            "thumb": f"thumbs/{meta['id']}.png" if os.path.exists(thumb) else None,
            "version": int(os.path.getmtime(glb)),
        })
    rank = {r: i for i, r in enumerate(RARITY_ORDER)}
    pets.sort(key=lambda p: (-rank.get(p["rarity"], -1), p["name"]))
    out = os.path.join(pets_dir, "viewer", "pets.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"rarities": RARITY_ORDER, "pets": pets}, fh, indent=2, ensure_ascii=False)
    print("REGISTERED", len(pets), "pets in", out)
    return pets


if __name__ == "__main__":
    register_all(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
