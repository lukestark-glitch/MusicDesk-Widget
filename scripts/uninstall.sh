#!/usr/bin/env bash
# Entfernt MusicDesk vollständig (App, Einstellungen, Login-Eintrag, Berechtigungen).
set -euo pipefail

APP="/Applications/MusicDesk.app"
BUNDLE_ID="com.musicdesk.widget"

echo "==> Beende MusicDesk ..."
pkill -x MusicDesk || true
# Warten, bis MusicDesk sauber beendet ist (max. 5 s), sonst hart beenden.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x MusicDesk >/dev/null || break
    sleep 0.5
done
pkill -9 -x MusicDesk 2>/dev/null || true
# Evtl. verwaisten Adapter-Prozess (perl) der systemweiten Quelle beenden.
pkill -f "MusicDesk.app/Contents/Resources/mediaremote-adapter.pl" 2>/dev/null || true

echo "==> Entferne alten Login-Eintrag (falls vorhanden) ..."
osascript -e 'tell application "System Events" to delete login item "MusicDesk"' >/dev/null 2>&1 || true
# Hinweis: Über SMAppService registrierte Anmeldeobjekte verschwinden automatisch,
# sobald die App gelöscht wurde.

echo "==> Lösche $APP ..."
rm -rf "$APP"

echo "==> Lösche Einstellungen ..."
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"

echo "==> Setze Automations-Berechtigung zurück ..."
tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true

echo ""
echo "MusicDesk wurde deinstalliert."
