#!/usr/bin/env bash
set -euo pipefail

APP_NAME="V-Paste"
SCHEME="V-Paste"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGING_DIR="$BUILD_DIR/release-staging"
DMG_STAGING_DIR="$BUILD_DIR/dmg-staging"
DIST_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"

rm -rf "$STAGING_DIR" "$DMG_STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DMG_STAGING_DIR" "$DIST_DIR"

xcodebuild clean build \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ONLY_ACTIVE_ARCH=NO

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
STAGED_APP="$STAGING_DIR/$APP_NAME.app"

if [ ! -d "$BUILT_APP" ]; then
  echo "Built app not found at $BUILT_APP" >&2
  exit 1
fi

/usr/bin/ditto "$BUILT_APP" "$STAGED_APP"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$STAGED_APP"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
ARTIFACT_BASENAME="$APP_NAME-$VERSION-$BUILD-macOS"
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASENAME.zip"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"

rm -f "$ZIP_PATH" "$DMG_PATH"
(
  cd "$STAGING_DIR"
  /usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
)

/usr/bin/ditto "$STAGED_APP" "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ -n "${CODESIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
fi

cat <<SUMMARY
Packaged V-Paste $VERSION ($BUILD)
App: $STAGED_APP
ZIP: $ZIP_PATH
DMG: $DMG_PATH
SUMMARY
