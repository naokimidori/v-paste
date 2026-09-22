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
  echo "==> 使用代码签名证书进行签名: $CODESIGN_IDENTITY"
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$STAGED_APP"
else
  if [ "${STRICT_RELEASE:-0}" = "1" ]; then
    echo "错误: STRICT_RELEASE=1 模式下必须配置 CODESIGN_IDENTITY 进行正式签名。" >&2
    exit 1
  fi
  echo "==> [警告] 未配置 CODESIGN_IDENTITY，使用系统默认临时签名 (ad-hoc) 打包本地预览版。" >&2
  echo "==> [警告] 遵循安全审查规范，不手工注入弱 designated requirement。此产物仅供本地开发调试，严禁作为正式发布版本分发！" >&2
  /usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    "$STAGED_APP"
fi

echo "==> 验证代码签名状态与 Designated Requirement:"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
/usr/bin/codesign -d -r- "$STAGED_APP" || true

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
VERSION="${VERSION:-2.0.0}"
BUILD="${BUILD:-4}"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  ARTIFACT_BASENAME="$APP_NAME-$VERSION-macOS"
else
  ARTIFACT_BASENAME="$APP_NAME-$VERSION-macOS-preview"
fi
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASENAME.zip"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"

rm -f "$ZIP_PATH" "$DMG_PATH"
(
  cd "$STAGING_DIR"
  /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_NAME.app" "$ZIP_PATH"
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

SIGN_TYPE="${CODESIGN_IDENTITY:-本地临时预览签名 (Ad-Hoc)}"

cat <<SUMMARY
========================================
Packaged V-Paste $VERSION ($BUILD)
签名模式: $SIGN_TYPE
App: $STAGED_APP
ZIP: $ZIP_PATH
DMG: $DMG_PATH
========================================
SUMMARY
