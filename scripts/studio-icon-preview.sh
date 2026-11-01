#!/usr/bin/env bash
# Copies assets/ui-upload/*.png into the local Studio content folder so
# rbxasset://freeapet/<key>.png works in Studio before the icons are
# uploaded. Studio-only preview: players never see these. Run again after
# Studio updates (Vinegar installs a new version folder).
set -euo pipefail
cd "$(dirname "$0")/.."
versions="$HOME/.var/app/org.vinegarhq.Vinegar/data/vinegar/versions"
for dir in "$versions"/*/; do
	if [ -f "$dir/RobloxStudioBeta.exe" ]; then
		mkdir -p "$dir/content/freeapet"
		cp assets/ui-upload/*.png "$dir/content/freeapet/"
		mkdir -p "$dir/content/freeapet/map"
		cp assets/map-textures/*.png "$dir/content/freeapet/map/"
		echo "Copied icons to $dir/content/freeapet"
	fi
done
