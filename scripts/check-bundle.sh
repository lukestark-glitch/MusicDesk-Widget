#!/usr/bin/env bash
# Prüft ein vorhandenes MusicDesk.app-Bundle (Standard: dist/MusicDesk.app):
# Info.plist-Schlüssel, ausführbare Datei, mediaremote-adapter,
# Architekturen, Signatur.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="${1:-$ROOT/dist/MusicDesk.app}"
PLIST="$APP/Contents/Info.plist"
EXE="$APP/Contents/MacOS/MusicDesk"
ICON="$APP/Contents/Resources/AppIcon.icns"
ADAPTER_SCRIPT="$APP/Contents/Resources/mediaremote-adapter.pl"
ADAPTER_FW="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
ADAPTER_FW_BIN="$ADAPTER_FW/MediaRemoteAdapter"
ADAPTER_HELPER="$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
PB=/usr/libexec/PlistBuddy

errors=0
fail() { echo "  FEHLER: $*" >&2; errors=$((errors + 1)); }
ok() { echo "  OK: $*"; }

check_archs() {
    local label="$1" file="$2" archs required
    archs="$(lipo -archs "$file" 2>/dev/null || true)"
    for required in arm64 x86_64; do
        if [[ " $archs " == *" $required "* ]]; then
            ok "$label: Architektur $required"
        else
            fail "$label: Architektur $required fehlt (gefunden: '${archs}')"
        fi
    done
}

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
    check_archs "MusicDesk" "$EXE"
else
    fail "Ausführbare Datei fehlt oder ist nicht ausführbar: $EXE"
fi

if [[ -f "$ICON" ]]; then ok "AppIcon.icns vorhanden"; else fail "AppIcon.icns fehlt"; fi

# mediaremote-adapter (Quelle "Alles auf dem Mac")
if [[ -f "$ADAPTER_SCRIPT" ]]; then
    ok "mediaremote-adapter.pl vorhanden"
    if perl -c "$ADAPTER_SCRIPT" >/dev/null 2>&1; then
        ok "mediaremote-adapter.pl: Perl-Syntax gültig"
    else
        fail "mediaremote-adapter.pl: Perl-Syntaxfehler"
    fi
else
    fail "mediaremote-adapter.pl fehlt: $ADAPTER_SCRIPT"
fi

if [[ -d "$ADAPTER_FW" && -e "$ADAPTER_FW_BIN" ]]; then
    ok "MediaRemoteAdapter.framework vorhanden"
    check_archs "MediaRemoteAdapter.framework" "$ADAPTER_FW_BIN"
    if codesign --verify --strict "$ADAPTER_FW" 2>/dev/null; then
        ok "MediaRemoteAdapter.framework: Signatur gültig"
    else
        fail "MediaRemoteAdapter.framework: Signaturprüfung fehlgeschlagen"
    fi
else
    fail "MediaRemoteAdapter.framework fehlt oder unvollständig: $ADAPTER_FW"
fi

if [[ -f "$ADAPTER_HELPER" && -x "$ADAPTER_HELPER" ]]; then
    ok "MediaRemoteAdapterTestClient vorhanden"
    check_archs "MediaRemoteAdapterTestClient" "$ADAPTER_HELPER"
    if codesign --verify --strict "$ADAPTER_HELPER" 2>/dev/null; then
        ok "MediaRemoteAdapterTestClient: Signatur gültig"
    else
        fail "MediaRemoteAdapterTestClient: Signaturprüfung fehlgeschlagen"
    fi
else
    fail "MediaRemoteAdapterTestClient fehlt oder ist nicht ausführbar: $ADAPTER_HELPER"
fi

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
