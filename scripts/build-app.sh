#!/bin/zsh
# Builds build/Pane.app (release, arm64) and build/Pane-<version>-arm64.zip.
# Signs with the "Pane Local Signing" identity when present (see scripts/create-signing-cert.sh),
# otherwise ad-hoc.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

SIGNING_IDENTITY="Pane Local Signing"
SCRATCH="$ROOT/.build-release"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Pane.app"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ -z "$VERSION" ]]; then
  echo "error: VERSION file is empty" >&2
  exit 1
fi
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
ARCHIVE="$BUILD_DIR/Pane-$VERSION-arm64.zip"
YEAR="$(date +%Y)"

echo "==> Building Pane $VERSION ($BUILD_NUMBER) for arm64"
swift build -c release --arch arm64 --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --arch arm64 --scratch-path "$SCRATCH" --show-bin-path)"

rm -rf "$APP" "$ARCHIVE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pane" "$APP/Contents/MacOS/Pane"
cp "$ROOT/Sources/Pane/Resources/Pane.icns" "$APP/Contents/Resources/Pane.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Pane</string>
  <key>CFBundleIdentifier</key><string>com.karunpai.Pane</string>
  <key>CFBundleName</key><string>Pane</string>
  <key>CFBundleDisplayName</key><string>Pane</string>
  <key>CFBundleIconFile</key><string>Pane.icns</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © $YEAR Karun Pai. All rights reserved.</string>
  <key>NSAccessibilityUsageDescription</key><string>Pane uses Accessibility to move and resize the window you select.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Pane Shortcuts</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleTypeIconFile</key><string>Pane.icns</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key>
      <array><string>com.karunpai.pane.shortcuts</string></array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.karunpai.pane.shortcuts</string>
      <key>UTTypeDescription</key><string>Pane Shortcuts</string>
      <key>UTTypeIconFile</key><string>Pane.icns</string>
      <key>UTTypeConformsTo</key>
      <array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array><string>paneshortcuts</string></array>
        <key>public.mime-type</key>
        <array><string>application/x-pane-shortcuts+json</string></array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Don't use -v: a self-signed identity is listed as "not trusted" but still signs fine.
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$SIGNING_IDENTITY\""; then
  echo "==> Signing with \"$SIGNING_IDENTITY\""
  codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "==> Signing ad-hoc"
  echo "warning: no \"$SIGNING_IDENTITY\" identity found. Ad-hoc builds change identity every" >&2
  echo "warning: build, so macOS will ask you to re-grant Accessibility after each update." >&2
  echo "warning: Run scripts/create-signing-cert.sh once to fix this." >&2
  codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo "==> Built $APP"
echo "    $(lipo -archs "$APP/Contents/MacOS/Pane")  •  version $VERSION ($BUILD_NUMBER)"
echo "==> Packaged $ARCHIVE"
