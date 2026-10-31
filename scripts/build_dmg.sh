#!/bin/bash
# Builds a Release rawpreview.app (Apple Silicon + Intel) and packs it into a
# drag-to-install DMG at build/rawpreview-<version>.dmg.
#
#     scripts/build_dmg.sh
#
# Without a paid Apple Developer account the app is ad-hoc signed. Friends
# must allow it once: open it, then System Settings → Privacy & Security →
# Open Anyway (or `xattr -dr com.apple.quarantine /Applications/rawpreview.app`).
#
# With a paid account, sign with Developer ID and notarize so it opens
# without warnings:
#
#     xcrun notarytool store-credentials rawpreview-notary   # once
#     SIGN_IDENTITY="Developer ID Application" NOTARY_PROFILE=rawpreview-notary \
#         scripts/build_dmg.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="rawpreview"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
STAGING="$BUILD_DIR/dmg-staging"

# xcode-select may point at the Command Line Tools, which lack xcodebuild.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -n "$SIGN_IDENTITY" ]]; then
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

echo "==> Building $APP_NAME (Release, universal)"
rm -rf "$DERIVED"
xcodebuild \
    -project "$ROOT/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" \
    ONLY_ACTIVE_ARCH=NO \
    "${SIGN_ARGS[@]}" \
    build | grep -E "^(error|warning: .*sign|\*\*)" || true

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
    echo "Build failed: $APP not found (rerun xcodebuild without the grep filter for details)" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Packing $DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Notarizing (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG"
echo "    Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "    Minimum macOS: $(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")"
