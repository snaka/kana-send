#!/usr/bin/env bash
# Build a Release .app and package it into an unsigned .dmg.
# Output: dist/kana-send-<version>.dmg
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="kana-send.xcodeproj"
SCHEME="kana-send"
APP_NAME="kana-send"
CONFIG="Release"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"

# Version: extract CFBundleShortVersionString from project.yml
VERSION="$(awk -F'"' '/CFBundleShortVersionString/ {print $2}' project.yml | head -1)"
VERSION="${VERSION:-0.0.0}"

DMG_BASENAME="${APP_NAME}-${VERSION}"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}.dmg"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Building $CONFIG"
rm -rf "$BUILD_DIR"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'generic/platform=macOS' \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    >/dev/null

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: $APP_PATH not found" >&2
    exit 1
fi

echo "==> Staging DMG contents"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    >/dev/null

echo ""
echo "Built: $DMG_PATH"
echo "Size:  $(du -h "$DMG_PATH" | cut -f1)"
