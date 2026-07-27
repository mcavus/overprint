#!/bin/bash
#
# Builds, signs, notarizes, and packages Overprint as a drag-to-Applications DMG.
#
# Usage:
#   Scripts/release.sh 0.2.0
#
# Required environment (set these locally or as GitHub Actions secrets):
#   SIGN_IDENTITY     e.g. "Developer ID Application: Your Company (TEAMID)"
#   TEAM_ID           the 10-character Apple Developer Team ID
#   NOTARY_KEY_ID     App Store Connect API key id
#   NOTARY_KEY_ISSUER App Store Connect issuer id (a UUID)
#   NOTARY_KEY_PATH   path to the .p8 private key file
#
# Optional:
#   SKIP_NOTARIZE=1   build and sign only, for a local dry run without Apple credentials
#
# Notarization is what removes the "unidentified developer" warning. Signing alone is not enough.
#
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: Scripts/release.sh <version>   (for example 0.2.0)" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.release"
APP_NAME="Overprint"
DMG="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# CURRENT_PROJECT_VERSION must be set alongside MARKETING_VERSION, and must match the
# <sparkle:version> that Scripts/appcast.sh writes. Sparkle compares the feed against the installed
# app's CFBundleVersion (which is $(CURRENT_PROJECT_VERSION)), NOT CFBundleShortVersionString. The
# project checks in CURRENT_PROJECT_VERSION = 1, so leaving it alone ships every release as build
# "1", and Sparkle reads 1 > 0.2.0 and offers nothing. Users would be stranded on whatever they
# first installed, with no way out but a manual re-download.
echo "==> Building $APP_NAME $VERSION (universal)"
xcodebuild \
  -project "$REPO_ROOT/Overprint/Overprint.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  ${SIGN_IDENTITY:+CODE_SIGN_IDENTITY="$SIGN_IDENTITY"} \
  ${TEAM_ID:+DEVELOPMENT_TEAM="$TEAM_ID"} \
  ${SIGN_IDENTITY:+CODE_SIGN_STYLE=Manual} \
  build

APP="$BUILD_DIR/DerivedData/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "error: build produced no app at $APP" >&2; exit 1; }

# The CLI is built here rather than in an Xcode build phase. Doing it in Xcode meant a full
# two-architecture SwiftPM build on every Release build, and Xcode's user script sandbox blocks
# SwiftPM anyway. Building it here also lets us control the signing order below.
echo "==> Building overprint CLI (universal)"
swift build \
  --package-path "$REPO_ROOT/OverprintKit" \
  --scratch-path "$BUILD_DIR/cli" \
  --configuration release \
  --product overprint \
  --arch arm64 --arch x86_64

CLI_BIN="$(swift build \
  --package-path "$REPO_ROOT/OverprintKit" \
  --scratch-path "$BUILD_DIR/cli" \
  --configuration release \
  --product overprint \
  --arch arm64 --arch x86_64 \
  --show-bin-path)/overprint"
[ -f "$CLI_BIN" ] || { echo "error: CLI binary not found at $CLI_BIN" >&2; exit 1; }

# It goes in Contents/MacOS/ because Xcode and codesign only treat the executable directories as
# nested code, and an unsigned Mach-O elsewhere in the bundle fails notarization.
#
# The name MUST NOT be "overprint": macOS filesystems are case-insensitive, so that path is the
# same file as the app's own executable "Overprint", and copying over it replaces the app with the
# CLI. The installed symlink is still called `overprint`, so users never see this name.
CLI_DEST="$APP/Contents/MacOS/overprint-cli"
cp -f "$CLI_BIN" "$CLI_DEST"
chmod +x "$CLI_DEST"

# Guard against ever reintroducing the collision: same inode means same file.
APP_BIN="$APP/Contents/MacOS/$APP_NAME"
[ "$(stat -f%i "$APP_BIN")" != "$(stat -f%i "$CLI_DEST")" ] \
  || { echo "error: the CLI overwrote the app executable (case-insensitive name clash)" >&2; exit 1; }

# Adding a file always invalidates the bundle signature, so the app must be re-signed even in a
# dry run. Falling back to ad-hoc keeps SKIP_NOTARIZE runs representative instead of producing an
# unsigned bundle that fails verification for a reason that would never occur in a real release.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> Signing with Developer ID (inside out: nested code first, then the bundle)"
  SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
else
  echo "==> No SIGN_IDENTITY, signing ad-hoc (not distributable)"
  SIGN_ARGS=(--force --sign -)
fi
codesign "${SIGN_ARGS[@]}" "$CLI_DEST"
codesign "${SIGN_ARGS[@]}" "$APP"

echo "==> Verifying the bundle"
[ -f "$CLI_DEST" ] || { echo "error: CLI missing from bundle" >&2; exit 1; }
lipo -archs "$CLI_DEST"
codesign --verify --deep --strict --verbose=2 "$APP"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "flags=.*runtime" \
    || { echo "error: hardened runtime is not enabled; notarization would fail" >&2; exit 1; }
fi

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  echo "==> Notarizing (this takes a few minutes)"
  ZIP="$BUILD_DIR/${APP_NAME}.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_KEY_ISSUER" \
    --wait
  # Stapling puts the ticket inside the app so Gatekeeper works offline.
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  rm -f "$ZIP"
else
  echo "==> SKIP_NOTARIZE=1, skipping notarization"
fi

echo "==> Building DMG"
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # gives the drag-to-install window
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"
rm -rf "$STAGE"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  # The DMG is a separate artifact and needs its own signature and ticket.
  [ -n "${SIGN_IDENTITY:-}" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_KEY_ISSUER" \
    --wait
  xcrun stapler staple "$DMG"
fi

echo
echo "==> Done: $DMG"
shasum -a 256 "$DMG"
