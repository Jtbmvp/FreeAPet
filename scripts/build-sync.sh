#!/usr/bin/env bash
# Builds one .rbxm per code folder so they can be imported into Studio
# through the Studio MCP (import_rbxm) when the Rojo plugin is not available.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for name in Shared Server Client; do
	rojo build "sync/$name.project.json" -o "build/$name.rbxm"
done
echo "Built: build/Shared.rbxm build/Server.rbxm build/Client.rbxm"
