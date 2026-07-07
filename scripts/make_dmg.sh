#!/bin/bash
# Monta o Docka.app e o instalador DMG.
# Uso: ./scripts/make_dmg.sh [versao]   (padrão: 1.0.0)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP="dist/Docka.app"

echo "▸ compilando (release)…"
swift build -c release 2>&1 | tail -1

echo "▸ montando bundle…"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Docka "$APP/Contents/MacOS/"
cp -R .build/release/Docka_Docka.bundle "$APP/Contents/Resources/"

echo "▸ gerando AppIcon.icns a partir da logo…"
ICONSET="dist/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Sources/Docka/Assets/logo.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Sources/Docka/Assets/logo.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Docka</string>
    <key>CFBundleIdentifier</key><string>com.editzffaleta.docka</string>
    <key>CFBundleName</key><string>Docka</string>
    <key>CFBundleDisplayName</key><string>Docka</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Bruno Zafriel — MIT</string>
</dict>
</plist>
PLIST

echo "▸ assinando (ad-hoc)…"
codesign --force --deep -s - "$APP" 2>/dev/null

echo "▸ criando DMG…"
DMGROOT="dist/dmg"
mkdir -p "$DMGROOT"
cp -R "$APP" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"
hdiutil create -volname "Docka" -srcfolder "$DMGROOT" -ov -format UDZO \
    "dist/Docka-${VERSION}.dmg" >/dev/null
rm -rf "$DMGROOT"

echo "✓ dist/Docka-${VERSION}.dmg pronto"
ls -lh "dist/Docka-${VERSION}.dmg"
