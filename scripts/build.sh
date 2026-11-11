#!/usr/bin/env bash
# Baut MusicDesk als Universal-Binary (arm64 + x86_64) und erzeugt
# dist/MusicDesk.app sowie dist/MusicDesk-<Version>.zip.
# Benötigt die Xcode Command Line Tools (kein Xcode-GUI) und CMake
# (für den mitgelieferten mediaremote-adapter; wird per Homebrew
# nachinstalliert, falls vorhanden).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_NAME="MusicDesk"
PRODUCT="MusicDesk"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
PLIST_SRC="$ROOT/Resources/Info.plist"
ICON_SRC="$ROOT/Resources/AppIcon.icns"
MIN_MACOS="13.0"
ADAPTER_SRC="$ROOT/ThirdParty/mediaremote-adapter"
ADAPTER_BUILD="$ROOT/.build/adapter"
ADAPTER_FW_NAME="MediaRemoteAdapter.framework"
ADAPTER_HELPER_NAME="MediaRemoteAdapterTestClient"
ADAPTER_SCRIPT_NAME="mediaremote-adapter.pl"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Fehler: build.sh muss auf macOS ausgeführt werden." >&2
    exit 1
fi

for tool in swift lipo codesign plutil ditto; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Fehler: '$tool' nicht gefunden. Bitte die Xcode Command Line Tools installieren (xcode-select --install)." >&2
        exit 1
    fi
done

# Prüft, ob ein Mach-O-Binary arm64 und x86_64 enthält.
require_universal() {
    local label="$1" file="$2" archs required
    if [[ ! -f "$file" ]]; then
        echo "Fehler: $label nicht gefunden: $file" >&2
        exit 1
    fi
    archs="$(lipo -archs "$file")"
    echo "==> Architekturen ($label): $archs"
    for required in arm64 x86_64; do
        if [[ " $archs " != *" $required "* ]]; then
            echo "Fehler: Architektur '$required' fehlt in $label ($archs)." >&2
            exit 1
        fi
    done
}

if ! command -v cmake >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "==> CMake fehlt – installiere es mit Homebrew ..."
        brew install cmake
    else
        echo "Fehler: 'cmake' nicht gefunden. Bitte CMake installieren (z. B. 'brew install cmake' oder https://cmake.org/download/)." >&2
        exit 1
    fi
fi

if [[ ! -f "$ADAPTER_SRC/CMakeLists.txt" ]]; then
    echo "Fehler: mediaremote-adapter-Quellen fehlen: $ADAPTER_SRC" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

echo "==> Baue $APP_NAME $VERSION (Release, Universal-Binary) ..."
swift --version

BINARY=""
if swift build -c release --arch arm64 --arch x86_64; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    BINARY="$BIN_DIR/$PRODUCT"
else
    echo "==> Multi-Arch-Build fehlgeschlagen (erfordert evtl. vollständiges Xcode)."
    echo "==> Fallback: getrennte Builds pro Architektur und Zusammenführen mit lipo ..."
    ARCH_BINS=()
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx$MIN_MACOS"
        echo "==> Baue für $triple ..."
        swift build -c release --triple "$triple"
        arch_bin_dir="$(swift build -c release --triple "$triple" --show-bin-path)"
        ARCH_BINS+=("$arch_bin_dir/$PRODUCT")
    done
    UNIVERSAL_DIR="$ROOT/.build/universal"
    mkdir -p "$UNIVERSAL_DIR"
    BINARY="$UNIVERSAL_DIR/$PRODUCT"
    lipo -create "${ARCH_BINS[@]}" -output "$BINARY"
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Fehler: Binary nicht gefunden: $BINARY" >&2
    exit 1
fi

require_universal "App-Binary" "$BINARY"

echo "==> Baue mediaremote-adapter (CMake, Release, Universal) ..."
cmake -S "$ADAPTER_SRC" -B "$ADAPTER_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS"
cmake --build "$ADAPTER_BUILD" --config Release

ADAPTER_FW="$(find "$ADAPTER_BUILD" -type d -name "$ADAPTER_FW_NAME" -prune -print | head -n 1)"
ADAPTER_HELPER="$(find "$ADAPTER_BUILD" -type f -name "$ADAPTER_HELPER_NAME" -perm -u+x -print | head -n 1)"
if [[ -z "$ADAPTER_FW" || ! -d "$ADAPTER_FW" ]]; then
    echo "Fehler: $ADAPTER_FW_NAME wurde nicht gebaut (in $ADAPTER_BUILD)." >&2
    exit 1
fi
if [[ -z "$ADAPTER_HELPER" || ! -f "$ADAPTER_HELPER" ]]; then
    echo "Fehler: $ADAPTER_HELPER_NAME wurde nicht gebaut (in $ADAPTER_BUILD)." >&2
    exit 1
fi

echo "==> Erstelle App-Bundle ..."
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BINARY" "$APP/Contents/MacOS/$PRODUCT"
chmod +x "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Warnung: $ICON_SRC fehlt – App wird ohne Icon gebaut (python3 scripts/make_icon.py erzeugt es)." >&2
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# mediaremote-adapter: Perl-Skript, Framework (Symlinks bleiben erhalten), Test-Client.
APP_FW="$APP/Contents/Frameworks/$ADAPTER_FW_NAME"
APP_HELPER="$APP/Contents/Helpers/$ADAPTER_HELPER_NAME"
APP_ADAPTER_SCRIPT="$APP/Contents/Resources/$ADAPTER_SCRIPT_NAME"
cp "$ADAPTER_SRC/bin/$ADAPTER_SCRIPT_NAME" "$APP_ADAPTER_SCRIPT"
chmod 755 "$APP_ADAPTER_SCRIPT"
ditto "$ADAPTER_FW" "$APP_FW"
cp "$ADAPTER_HELPER" "$APP_HELPER"
chmod 755 "$APP_HELPER"

require_universal "MediaRemoteAdapter.framework" "$APP_FW/MediaRemoteAdapter"
require_universal "$ADAPTER_HELPER_NAME" "$APP_HELPER"

plutil -lint "$APP/Contents/Info.plist"

echo "==> Signiere ad hoc (von innen nach außen) ..."
codesign --force -s - "$APP_FW"
codesign --force -s - "$APP_HELPER"
codesign --force --deep -s - "$APP"

# Informativ: funktioniert der Adapter auf diesem Mac? (bricht den Build nie ab)
echo "==> Adapter-Test (informativ) ..."
adapter_status=0
/usr/bin/perl "$APP_ADAPTER_SCRIPT" "$APP_FW" "$APP_HELPER" test >/dev/null 2>&1 &
adapter_pid=$!
for _ in $(seq 1 100); do
    kill -0 "$adapter_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$adapter_pid" 2>/dev/null; then
    kill "$adapter_pid" 2>/dev/null || true
    wait "$adapter_pid" 2>/dev/null || true
    echo "    Adapter-Test: Zeitüberschreitung (informativ, Build läuft weiter)."
else
    wait "$adapter_pid" || adapter_status=$?
    if [[ "$adapter_status" -eq 0 ]]; then
        echo "    Adapter-Test: OK (Exit-Code 0) – Quelle \"Alles auf dem Mac\" verfügbar."
    else
        echo "    Adapter-Test: Exit-Code $adapter_status (informativ, Build läuft weiter;"
        echo "    MusicDesk fällt dann automatisch auf Apple Music/Spotify zurück)."
    fi
fi

echo "==> Erstelle ZIP ..."
ditto -c -k --keepParent "$APP" "$ZIP"

"$SCRIPT_DIR/check-bundle.sh" "$APP"

echo ""
echo "Fertig!"
echo "  App: $APP"
echo "  ZIP: $ZIP"
