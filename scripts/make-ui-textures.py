#!/usr/bin/env python3
"""Draws the stud-style UI textures (SVG -> PNG with rsvg-convert).

stud_tile - one stud per 64x64 tile, white highlight and dark shadow on a
            transparent background, so it can be tiled over any colour
            (ImageLabel ScaleType Tile) to give panels and buttons studs.
Writes assets/ui-icons-custom/src/*.svg, assets/ui-icons-custom/*.png and a
copy in assets/ui-upload (named by UI key).

Usage: python3 -I scripts/make-ui-textures.py
"""

import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUD = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <rect x="14" y="14" width="36" height="36" rx="5" fill="#FFFFFF" fill-opacity="0.10"/>
  <path d="M14 47 L14 19 Q14 14 19 14 L47 14 L44 18 L20 18 Q18 18 18 20 L18 44 Z" fill="#FFFFFF" fill-opacity="0.30"/>
  <path d="M50 17 L50 45 Q50 50 45 50 L17 50 L20 46 L44 46 Q46 46 46 44 L46 20 Z" fill="#000000" fill-opacity="0.22"/>
</svg>
"""


def main():
    custom = os.path.join(ROOT, "assets", "ui-icons-custom")
    upload = os.path.join(ROOT, "assets", "ui-upload")
    os.makedirs(os.path.join(custom, "src"), exist_ok=True)
    os.makedirs(upload, exist_ok=True)
    for name, svg, size in (("stud_tile", STUD, 64),):
        src = os.path.join(custom, "src", f"{name}.svg")
        png = os.path.join(custom, f"{name}.png")
        with open(src, "w") as f:
            f.write(svg)
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", png, src], check=True)
        shutil.copy(png, os.path.join(upload, f"{name}.png"))
        print("wrote", png)


if __name__ == "__main__":
    main()
