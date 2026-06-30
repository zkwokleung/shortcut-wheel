#!/bin/bash
# Builds a universal, ad-hoc-signed Release .app and packages it into a .dmg.
# No Apple account required: the app is built unsigned, then ad-hoc signed with
# `codesign --sign -` (mandatory for arm64 to even run; users clear quarantine on
# first launch — see README). Usage: ./scripts/package-dmg.sh [vX.Y.Z]
set -euo pipefail

SCHEME="ShortcutWheel"
TAG="${1:-v0.0.0}"
VERSION="${TAG#v}"
BUILD_DIR="build"
DIST_DIR="dist"

cd "$(dirname "$0")/.."

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Building universal Release ($VERSION)"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
echo "==> Architectures:"
lipo -archs "$APP/Contents/MacOS/$SCHEME"

echo "==> Building DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST_DIR/$SCHEME-$VERSION.dmg"
hdiutil create \
  -volname "$SCHEME $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"
rm -rf "$STAGE"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "==> Done: $DMG"
