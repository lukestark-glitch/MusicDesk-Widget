#!/usr/bin/env bash
# Baut MusicDesk und installiert es nach /Applications.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_APP="$ROOT/dist/MusicDesk.app"
DEST_APP="/Applications/MusicDesk.app"

"$SCRIPT_DIR/build.sh"

echo "==> Beende laufendes MusicDesk (falls aktiv) ..."
pkill -x MusicDesk || true
sleep 1

echo "==> Installiere nach $DEST_APP ..."
if [[ -e "$DEST_APP" ]]; then
    rm -rf "$DEST_APP"
fi
ditto "$SRC_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "==> Starte MusicDesk ..."
open "$DEST_APP"

echo ""
echo "MusicDesk wurde installiert: $DEST_APP"
echo "Hinweis: Beim ersten Start fragt macOS nach der Erlaubnis, Apple Music zu steuern – bitte mit \"OK\" bestätigen."
