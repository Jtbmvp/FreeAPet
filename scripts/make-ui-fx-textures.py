#!/usr/bin/env python3
"""White-on-transparent FX textures for the HUD: glow, rays, sparkle, ring, hex glow, hex lattice.

Tinted at runtime with ImageColor3, so one upload serves every colour.
Only needs numpy (Pillow is not installed here): PNGs are written by hand with zlib.
Usage: make-ui-fx-textures.py <out-dir>
"""
import struct
import sys
import zlib
from pathlib import Path

import numpy as np


def write_png(path: Path, alpha: np.ndarray) -> None:
    """Writes white RGB with the given 0..1 alpha."""
    h, w = alpha.shape
    rgba = np.full((h, w, 4), 255, dtype=np.uint8)
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)
    print(f"{path.name}: {w}x{h} {len(png)} bytes")


def grid(w: int, h: int):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    return (xs + 0.5 - w / 2) / (w / 2), (ys + 0.5 - h / 2) / (h / 2)


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def glow(size=256):
    x, y = grid(size, size)
    r = np.hypot(x, y)
    return np.clip(1 - r, 0, 1) ** 2.2


def rays(size=512, count=12):
    x, y = grid(size, size)
    r = np.hypot(x, y)
    angle = np.arctan2(y, x)
    wedge = 0.5 + 0.5 * np.cos(angle * count)
    wedge = smooth(0.35, 0.62, wedge)
    # Alternate long and short rays so the rotation reads as motion.
    long_short = 0.72 + 0.28 * np.cos(angle * count / 2) ** 2
    fade = np.clip(1 - r / long_short, 0, 1) ** 1.1
    return wedge * fade * smooth(0.02, 0.16, r)


def sparkle(size=128):
    x, y = grid(size, size)
    ax, ay = np.abs(x), np.abs(y)
    star = np.clip(1 - (np.sqrt(ax) + np.sqrt(ay)) / 1.0, 0, 1)
    core = np.clip(1 - np.hypot(x, y) / 0.42, 0, 1) ** 2
    return np.clip(star ** 0.8 * 1.6 + core * 0.8, 0, 1)


def ring(size=256, radius=0.82, width=0.07):
    x, y = grid(size, size)
    r = np.hypot(x, y)
    return np.exp(-(((r - radius) / width) ** 2)) * smooth(1.0, 0.94, r)


def hex_distance(x, y):
    """Distance to the edge of a pointy-top hexagon of inradius 1 (negative inside)."""
    ax, ay = np.abs(x), np.abs(y)
    return np.maximum(ax, ax * 0.5 + ay * (3**0.5 / 2)) - 1


def hex_glow(w=256, h=296):
    # Same 210:242 proportion as the node image; the hexagon fills 62% so the glow has room to fall off.
    x, y = grid(w, h)
    d = hex_distance(x / 0.62, y * (h / w) / 0.62)
    inside = d <= 0
    alpha = np.where(inside, 1.0, np.clip(1 - d / 0.6, 0, 1) ** 2.4)
    return alpha * smooth(1.0, 0.86, np.maximum(np.abs(x), np.abs(y)))


def hex_lattice(tile_w=432, tile_h=752, line=2.4):
    """Tileable honeycomb: 2 rows per tile, matching the node lattice (216 x 188 studs of canvas)."""
    ys, xs = np.mgrid[0:tile_h, 0:tile_w].astype(np.float64)
    xs += 0.5
    ys += 0.5
    step_x = tile_w
    step_y = tile_h / 2
    radius = step_x / 2  # inradius of a pointy-top hexagon whose width is one column
    best = np.full(xs.shape, np.inf)
    second = np.full(xs.shape, np.inf)
    for row in range(-1, 4):
        for col in range(-1, 3):
            cx = col * step_x + (row % 2) * step_x / 2
            cy = row * step_y
            dist = np.hypot(xs - cx, ys - cy)
            new_best = np.minimum(best, dist)
            second = np.minimum(second, np.maximum(best, dist))
            best = new_best
    # Voronoi border of the hexagon centres = the honeycomb's walls.
    wall = (second - best) / 2
    alpha = smooth(line * 1.4, line * 0.4, wall)
    # Soft rim so the walls feel lit rather than drawn.
    alpha = np.maximum(alpha, 0.28 * smooth(radius * 0.16, 0, wall))
    return alpha


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "build/ui-fx")
    out.mkdir(parents=True, exist_ok=True)
    write_png(out / "fx_glow.png", glow())
    write_png(out / "fx_rays.png", rays())
    write_png(out / "fx_sparkle.png", sparkle())
    write_png(out / "fx_ring.png", ring())
    write_png(out / "hex_glow.png", hex_glow())
    write_png(out / "hex_lattice.png", hex_lattice())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
