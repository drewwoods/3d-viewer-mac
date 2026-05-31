#!/bin/bash
# Builds a release .app bundle and a distributable .dmg.
# Usage: ./scripts/package.sh [version]   (default version: 1.0.0)
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="3D Viewer"
EXECUTABLE="ThreeDViewer"
BUNDLE_ID="local.ThreeDViewer"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/ThreeDViewer-$VERSION.dmg"

cd "$(dirname "$0")/.."

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$EXECUTABLE" "$APP/Contents/MacOS/"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>3D Model</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>public.geometry-definition-format</string>
      <string>public.polygon-file-format</string>
      <string>public.standard-tesselated-geometry-format</string>
      <string>com.pixar.universal-scene-description</string>
      <string>com.pixar.universal-scene-description-mobile</string>
      <string>public.scenekit.scene</string>
      <string>org.khronos.collada.digital-asset-exchange</string>
      <string>public.alembic</string>
    </array>
  </dict></array>
</dict></plist>
PLIST

# Ad-hoc sign so the app launches without "damaged" errors on the build machine.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> Building $DMG"
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done"
echo "    App: $APP"
echo "    DMG: $DMG"
