#!/bin/bash
# Builds OrbitNotes.app (universal: Apple Silicon + Intel) and packages it as a DMG.
# Usage: ./scripts/build_dmg.sh [version]      e.g. ./scripts/build_dmg.sh 1.0.0
set -euo pipefail

APP=OrbitNotes
VERSION="${1:-1.0.0}"
cd "$(dirname "$0")/.."

echo "▶ Building $APP $VERSION (release, universal)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP"

echo "▶ Assembling app bundle…"
rm -rf dist
BUNDLE="dist/$APP.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$BUNDLE/Contents/Info.plist"
echo "APPL????" > "$BUNDLE/Contents/PkgInfo"

if [ -f Resources/icon.png ]; then
  ICONSET="dist/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) Resources/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "▶ Signing (ad-hoc)…"
codesign --force --deep --sign - "$BUNDLE"

echo "▶ Creating DMG…"
STAGE="dist/dmg"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/$APP-$VERSION.dmg"
hdiutil create -volname "Orbit Notes" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✅ Done: $DMG"
