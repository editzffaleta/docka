#!/bin/bash
# Monta o Docka.app e o instalador DMG.
#
# Uso: ./scripts/make_dmg.sh [versao]   (padrão: 1.0.0)
#
# Sem variáveis extras → assinatura ad-hoc (usuário precisa de clique-direito → Abrir).
# Com uma conta Apple Developer, exporte antes de rodar e o script assina com
# Developer ID, notariza na Apple e grampeia o carimbo — zero avisos do Gatekeeper:
#
#   export DOCKA_SIGN_ID="Developer ID Application: Seu Nome (TEAMID)"
#   export DOCKA_NOTARY_PROFILE="docka-notary"
#
# O perfil de notarização é criado uma única vez com:
#   xcrun notarytool store-credentials docka-notary \
#     --apple-id seu@email.com --team-id TEAMID --password <senha-de-app>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP="dist/Docka.app"
SIGN_ID="${DOCKA_SIGN_ID:-}"
NOTARY_PROFILE="${DOCKA_NOTARY_PROFILE:-}"

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

if [[ -n "$SIGN_ID" ]]; then
    echo "▸ assinando com Developer ID…"
    codesign --force --deep --options runtime --timestamp \
        -s "$SIGN_ID" "$APP"
else
    echo "▸ assinando (ad-hoc — usuários precisarão de clique-direito → Abrir)…"
    codesign --force --deep -s - "$APP" 2>/dev/null
fi

echo "▸ criando DMG…"
DMG="dist/Docka-${VERSION}.dmg"
DMGROOT="dist/dmg"
mkdir -p "$DMGROOT"
cp -R "$APP" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"
hdiutil create -volname "Docka" -srcfolder "$DMGROOT" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMGROOT"

if [[ -n "$SIGN_ID" && -n "$NOTARY_PROFILE" ]]; then
    echo "▸ assinando o DMG…"
    codesign --force --timestamp -s "$SIGN_ID" "$DMG"

    echo "▸ enviando para notarização (pode levar alguns minutos)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "▸ grampeando o carimbo de notarização…"
    xcrun stapler staple "$APP"
    xcrun stapler staple "$DMG"
    echo "✓ notarizado — abre sem nenhum aviso do Gatekeeper"
elif [[ -n "$SIGN_ID" ]]; then
    echo "⚠ assinado com Developer ID, mas sem notarização (defina DOCKA_NOTARY_PROFILE)"
fi

echo "✓ $DMG pronto"
ls -lh "$DMG"
