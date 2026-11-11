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
# Warten, bis MusicDesk sauber beendet ist (max. 5 s), sonst hart beenden.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x MusicDesk >/dev/null || break
    sleep 0.5
done
pkill -9 -x MusicDesk 2>/dev/null || true
# Evtl. verwaisten Adapter-Prozess (perl) der systemweiten Quelle beenden.
pkill -f "MusicDesk.app/Contents/Resources/mediaremote-adapter.pl" 2>/dev/null || true
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
echo "Hinweis: macOS fragt einmalig nach der Erlaubnis, Apple Music bzw. Spotify zu steuern – bitte mit \"OK\" bestätigen."
echo "Die Quelle \"Alles auf dem Mac\" (z. B. YouTube im Browser) braucht keine Erlaubnis."
