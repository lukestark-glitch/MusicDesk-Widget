#!/usr/bin/env bash
# Entfernt MusicDesk vollständig (App, Einstellungen, Login-Eintrag, Berechtigungen).
set -euo pipefail

APP="/Applications/MusicDesk.app"
BUNDLE_ID="com.musicdesk.widget"

echo "==> Beende MusicDesk ..."
pkill -x MusicDesk || true

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
