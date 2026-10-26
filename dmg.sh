#!/bin/bash
# Crea dist/FloatyPIP-<versione>.dmg con app universale (Apple Silicon + Intel).
#   ./dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null; then
  echo "Mancano i Command Line Tools: lancia  xcode-select --install  e riprova."; exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
APP="build/FloatyPIP.app"
DMG="dist/FloatyPIP-$VERSION.dmg"
rm -rf build dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist

FRAMEWORKS=(-framework Cocoa -framework WebKit -framework Carbon -framework ServiceManagement)
for ARCH in arm64 x86_64; do
  echo "→ Compilo ${ARCH}…"
  swiftc -O -target "${ARCH}-apple-macos13.0" Sources/*.swift -o "build/FloatyPIP-$ARCH" "${FRAMEWORKS[@]}"
done
lipo -create build/FloatyPIP-arm64 build/FloatyPIP-x86_64 -output "$APP/Contents/MacOS/FloatyPIP"
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

echo "→ Creo il DMG…"
STAGE=build/dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applicazioni"
cat > "$STAGE/LEGGIMI - Come installare.txt" <<'EOF'
COME INSTALLARE FLOATYPIP

1. Trascina l'icona FloatyPIP sulla cartella "Applicazioni" qui accanto.
2. Apri la cartella Applicazioni e fai doppio clic su FloatyPIP.
3. Se macOS dice che non può verificare lo sviluppatore:
   - premi "Fine" (o "Annulla"),
   - apri Impostazioni di Sistema → Privacy e sicurezza,
   - scorri in basso e premi "Apri comunque" accanto a FloatyPIP,
   - conferma con la password del Mac.
   (Su macOS 14 o precedenti basta: tasto destro su FloatyPIP → Apri → Apri.)
4. FloatyPIP compare come icona in alto a destra nella barra dei menu.

Guida completa: https://github.com/fabiobarisone/FloatyPIP
EOF
hdiutil create -volname "FloatyPIP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "✓ Pronto: $DMG"
