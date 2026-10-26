#!/bin/bash
# Compila "FloatyPIP.app".  Uso:
#   ./build.sh            → crea build/FloatyPIP.app
#   ./build.sh install    → la copia in /Applicazioni e la avvia
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null; then
  echo "Mancano i Command Line Tools: lancia  xcode-select --install  e riprova."; exit 1
fi

APP="build/FloatyPIP.app"
ARCH=$(uname -m)
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compilo ($ARCH)…"
swiftc -O -target "${ARCH}-apple-macos13.0" Sources/*.swift \
  -o "$APP/Contents/MacOS/FloatyPIP" \
  -framework Cocoa -framework WebKit -framework Carbon -framework ServiceManagement

cp Info.plist "$APP/Contents/"

echo "→ Icona…"
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Firma locale…"
codesign --force --deep -s - "$APP"

echo "✓ Pronta: $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x FloatyPIP 2>/dev/null || true
  pkill -x PiPDodge 2>/dev/null || true
  rm -rf "/Applications/PiP Dodge.app"
  sleep 1
  rm -rf "/Applications/FloatyPIP.app"
  cp -R "$APP" /Applications/
  sleep 1
  open "/Applications/FloatyPIP.app" || (sleep 2; open "/Applications/FloatyPIP.app")
  echo "✓ Installata in /Applications e avviata (icona nella barra menu)."
fi
