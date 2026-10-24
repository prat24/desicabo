#!/usr/bin/env bash
# Build the web version of the game into build/web, ready to copy to a server.
# Needs the Godot 4.7 Web export templates (Editor → Manage Export Templates).
#   deploy/build_web.sh
#   GODOT=/path/to/godot deploy/build_web.sh
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."

rm -rf build/web
mkdir -p build/web
# Keeps the Godot editor from importing the build's own PNGs as game assets.
touch build/.gdignore

"$GODOT" --headless --path . --export-release "Web" build/web/index.html

if [[ ! -f build/web/index.wasm || ! -f build/web/index.pck ]]; then
	echo "Export failed — see the Godot output above." >&2
	exit 1
fi

# Compressed copies of the big files; Caddy sends these to browsers that take
# gzip, which cuts the download to about a quarter.
find build/web -type f \( -name '*.wasm' -o -name '*.pck' -o -name '*.js' -o -name '*.html' \) \
	-exec gzip -9 --keep --force {} \;

ls -lh build/web
