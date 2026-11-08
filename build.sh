#!/bin/bash
# Builds the ready-to-use installer and its ZIP into dist/
#   dist/KytyPS5 Installer & Updater.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src/installer.template.sh"
COVER="$ROOT/assets/cover.jpg"
DIST="$ROOT/dist"
NAME="KytyPS5 Installer & Updater"

rm -rf "$DIST"
STAGE="$DIST/stage"
mkdir -p "$STAGE/roms/ports/images"
python3 - "$SRC" "$STAGE/roms/ports/$NAME.sh" "$COVER" <<'PY'
import base64, sys, textwrap
src, out, cover = sys.argv[1:4]
poster = "\n".join(textwrap.wrap(base64.b64encode(open(cover, "rb").read()).decode(), 76))
t = open(src).read().replace("@@POSTER@@", poster)
open(out, "w", newline="\n").write(t)
PY
chmod +x "$STAGE/roms/ports/$NAME.sh"
bash -n "$STAGE/roms/ports/$NAME.sh"
cp "$COVER" "$STAGE/roms/ports/images/$NAME.jpg"
cp "$ROOT/README.md" "$STAGE/README.txt"
cp "$ROOT/LIESMICH.md" "$STAGE/LIESMICH.txt"
(cd "$STAGE" && zip -qr "$DIST/$NAME.zip" README.txt LIESMICH.txt roms)
rm -rf "$STAGE"
echo "built: dist/$NAME.zip"
