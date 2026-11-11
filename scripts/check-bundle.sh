#!/usr/bin/env bash
# Prüft ein vorhandenes MusicDesk.app-Bundle (Standard: dist/MusicDesk.app):
# Info.plist-Schlüssel, ausführbare Datei, Architekturen, Signatur.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="${1:-$ROOT/dist/MusicDesk.app}"
PLIST="$APP/Contents/Info.plist"
EXE="$APP/Contents/MacOS/MusicDesk"
ICON="$APP/Contents/Resources/AppIcon.icns"
PB=/usr/libexec/PlistBuddy

errors=0
fail() { echo "  FEHLER: $*" >&2; errors=$((errors + 1)); }
ok() { echo "  OK: $*"; }

echo "==> Prüfe Bundle: $APP"

if [[ ! -d "$APP" ]]; then
    echo "Fehler: Bundle nicht gefunden: $APP (zuerst scripts/build.sh ausführen)" >&2
    exit 1
fi

if [[ ! -f "$PLIST" ]]; then
    fail "Info.plist fehlt"
else
    if plutil -lint "$PLIST" >/dev/null; then ok "Info.plist ist gültig"; else fail "Info.plist ist ungültig"; fi

    check_key() {
        local key="$1" expected="$2" actual
        if ! actual="$("$PB" -c "Print :$key" "$PLIST" 2>/dev/null)"; then
            fail "Schlüssel $key fehlt"
            return
        fi
        if [[ -n "$expected" && "$actual" != "$expected" ]]; then
            fail "$key = '$actual' (erwartet '$expected')"
        else
            ok "$key = $actual"
        fi
    }

    check_key CFBundleIdentifier com.musicdesk.widget
    check_key CFBundleExecutable MusicDesk
    check_key CFBundleName MusicDesk
    check_key CFBundleDisplayName MusicDesk
    check_key CFBundlePackageType APPL
    check_key CFBundleShortVersionString ""
    check_key CFBundleVersion ""
    check_key CFBundleIconFile AppIcon
    check_key LSMinimumSystemVersion 13.0
    check_key LSUIElement true
    check_key NSHighResolutionCapable true
    check_key LSApplicationCategoryType public.app-category.music
    check_key NSAppleEventsUsageDescription ""
fi

if [[ -f "$EXE" && -x "$EXE" ]]; then
    ok "Ausführbare Datei vorhanden"
    archs="$(lipo -archs "$EXE" 2>/dev/null || true)"
    for required in arm64 x86_64; do
        if [[ " $archs " == *" $required "* ]]; then
            ok "Architektur $required"
        else
            fail "Architektur $required fehlt (gefunden: '${archs}')"
        fi
    done
else
    fail "Ausführbare Datei fehlt oder ist nicht ausführbar: $EXE"
fi

if [[ -f "$ICON" ]]; then ok "AppIcon.icns vorhanden"; else fail "AppIcon.icns fehlt"; fi

if codesign --verify --deep --strict --verbose=2 "$APP"; then
    ok "Signatur gültig"
else
    fail "Signaturprüfung fehlgeschlagen"
fi

if [[ "$errors" -gt 0 ]]; then
    echo "==> Bundle-Prüfung fehlgeschlagen ($errors Fehler)." >&2
    exit 1
fi
echo "==> Bundle-Prüfung erfolgreich."
