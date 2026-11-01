#!/usr/bin/env bash
# Builds assets/map-textures/<ArtFolder>.png: the map's baked stud texture for
# a floor colour, tiled 2x2 (studs at the normal Roblox size instead of 2x)
# and with greens slightly desaturated. Source images come from the
# Blender-baked map GLB. Needs ImageMagick.
# Usage: scripts/make-map-textures.sh path/to/FreeAPet_Map_ready.glb
set -euo pipefail
cd "$(dirname "$0")/.."
glb="${1:?path to FreeAPet_Map_ready.glb}"
tmp="$(mktemp -d)"
python3 -I scripts/extract-glb-images.py "$glb" "$tmp"
mkdir -p assets/map-textures
for name in $(grep -oE '^\s+[A-Za-z0-9_]+ =' src/shared/Config/MapTextures.luau | tr -d ' ='); do
	suffix="${name#*_}"
	src="$(ls "$tmp" | grep -E "^[0-9]+_map_${suffix}\.001\.png$" | head -1)"
	[ -z "$src" ] && { echo "missing $name"; continue; }
	sat=100
	case "$name" in *lawn* | *green* | Forest_c_*) sat=82 ;; esac
	magick "$tmp/$src" -write mpr:t +delete -size 256x256 tile:mpr:t -modulate 100,$sat,100 -depth 8 "assets/map-textures/$name.png"
done
rm -rf "$tmp"
echo "Wrote assets/map-textures/"
