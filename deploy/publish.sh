#!/usr/bin/env bash
# Copy the web build (from deploy/build_web.sh) to a server with rsync over SSH.
#   deploy/publish.sh user@host:/srv/desicabo/web
set -euo pipefail

DEST="${1:-}"
if [[ "$DEST" != *:* ]]; then
	echo "usage: deploy/publish.sh user@host:/path/to/web" >&2
	exit 1
fi
cd "$(dirname "$0")/.."

if [[ ! -f build/web/index.html ]]; then
	echo "No build yet — run deploy/build_web.sh first." >&2
	exit 1
fi

# --delete drops files the new build no longer has; browsers pick up the new
# build on their next visit (the example Caddyfile tells them to check each time).
# Short flags: macOS ships openrsync, which does not take every long form.
rsync -rtv --delete build/web/ "${DEST%/}/"
