#!/usr/bin/env python3
"""Draws the research tree's hexagon tiles (pointy-top) in the UI pack style.

hex_fill  - white hexagon with soft shading and a top shine; tinted per
            category in game (ImageColor3), so it stays white/grey.
hex_frame - white border with the pack's dark navy outline, drawn untinted
            over the fill.
Writes SVG sources to assets/ui-icons-custom/src and PNGs (rsvg-convert) to
assets/ui-icons-custom and assets/ui-upload (named by UI key).

Usage: python3 -I scripts/make-hex-tiles.py
"""

import math
import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 512
C = SIZE / 2
NAVY = "#1B2236"


def points(radius, dy=0.0):
    pts = []
    for i in range(6):
        a = math.radians(60 * i - 90)
        pts.append(f"{C + radius * math.cos(a):.1f},{C + dy + radius * math.sin(a):.1f}")
    return " ".join(pts)


def path(radius):
    return "M" + " L".join(points(radius).split(" ")) + " Z"


FILL = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <defs>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#B4B4B4"/>
    </linearGradient>
    <radialGradient id="shine" cx="0.5" cy="0.28" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <polygon points="{points(238)}" fill="url(#shade)"/>
  <polygon points="{points(238)}" fill="url(#shine)"/>
</svg>
"""

FRAME = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">
  <path d="{path(250)} {path(242)}" fill="{NAVY}" fill-rule="evenodd"/>
  <path d="{path(242)} {path(222)}" fill="#FFFFFF" fill-rule="evenodd"/>
  <path d="{path(222)} {path(216)}" fill="{NAVY}" fill-opacity="0.35" fill-rule="evenodd"/>
</svg>
"""


def main():
    custom = os.path.join(ROOT, "assets", "ui-icons-custom")
    upload = os.path.join(ROOT, "assets", "ui-upload")
    os.makedirs(os.path.join(custom, "src"), exist_ok=True)
    os.makedirs(upload, exist_ok=True)
    for name, svg in (("hex_fill", FILL), ("hex_frame", FRAME)):
        src = os.path.join(custom, "src", f"{name}.svg")
        png = os.path.join(custom, f"{name}.png")
        with open(src, "w") as f:
            f.write(svg)
        subprocess.run(["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE), "-o", png, src], check=True)
        shutil.copy(png, os.path.join(upload, f"{name}.png"))
        print("wrote", png)


if __name__ == "__main__":
    main()
