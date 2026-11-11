#!/usr/bin/env bash
# Baut MusicDesk als Universal-Binary (arm64 + x86_64) und erzeugt
# dist/MusicDesk.app sowie dist/MusicDesk-<Version>.zip.
# Benötigt nur die Xcode Command Line Tools (kein Xcode-GUI).
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

ARCHS="$(lipo -archs "$BINARY")"
echo "==> Architekturen im Binary: $ARCHS"
for required in arm64 x86_64; do
    if [[ " $ARCHS " != *" $required "* ]]; then
        echo "Fehler: Architektur '$required' fehlt im Binary ($ARCHS)." >&2
        exit 1
    fi
done

echo "==> Erstelle App-Bundle ..."
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$PRODUCT"
chmod +x "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Warnung: $ICON_SRC fehlt – App wird ohne Icon gebaut (python3 scripts/make_icon.py erzeugt es)." >&2
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist"

echo "==> Signiere ad hoc ..."
codesign --force --deep -s - "$APP"

echo "==> Erstelle ZIP ..."
ditto -c -k --keepParent "$APP" "$ZIP"

"$SCRIPT_DIR/check-bundle.sh" "$APP"

echo ""
echo "Fertig!"
echo "  App: $APP"
echo "  ZIP: $ZIP"
