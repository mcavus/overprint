#!/bin/bash
#
# Signs the release DMG with the Sparkle EdDSA key and writes the appcast feed.
#
# Sparkle verifies this signature before installing anything, so the private key is what actually
# protects users. A stolen key means arbitrary code delivered as an "update"; keep it in secrets
# and nowhere else.
#
# Usage:  Scripts/appcast.sh 0.2.0
# Env:    SPARKLE_PRIVATE_KEY   the EdDSA private key (from Sparkle's generate_keys -x)
#         REPO                  owner/name, defaults to the GitHub Actions value
#
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: Scripts/appcast.sh <version>" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.release"
DMG="$BUILD_DIR/Overprint-${VERSION}.dmg"
APPCAST="$BUILD_DIR/appcast.xml"
REPO="${REPO:-${GITHUB_REPOSITORY:-mcavus/overprint}}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/Overprint-${VERSION}.dmg"

[ -f "$DMG" ] || { echo "error: no DMG at $DMG (run Scripts/release.sh first)" >&2; exit 1; }

LENGTH=$(stat -f%z "$DMG")
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

SIGNATURE=""
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  # sign_update ships inside the Sparkle package Xcode resolved during the build. Only search
  # roots that exist: a CI runner has no ~/Library/Developer/Xcode/DerivedData, and under
  # `set -euo pipefail` find's non-zero exit would kill the script here, before the friendly
  # error below could run.
  SEARCH_ROOTS=()
  for root in "$REPO_ROOT/.release/DerivedData/SourcePackages" "$HOME/Library/Developer/Xcode/DerivedData"; do
    [ -d "$root" ] && SEARCH_ROOTS+=("$root")
  done
  SIGN_TOOL=""
  if [ ${#SEARCH_ROOTS[@]} -gt 0 ]; then
    SIGN_TOOL=$( { find "${SEARCH_ROOTS[@]}" -name sign_update -type f 2>/dev/null || true; } | head -1)
  fi
  if [ -z "$SIGN_TOOL" ]; then
    echo "error: sign_update not found; build the app once so Sparkle resolves" >&2
    exit 1
  fi
  # Private temp file with a cleanup trap: a world-readable Sparkle key left on disk lets anyone
  # sign an "update" for every Overprint user.
  umask 077
  KEYFILE=$(mktemp)
  trap 'rm -f "$KEYFILE"' EXIT
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEYFILE"
  SIGNATURE=$("$SIGN_TOOL" "$DMG" -f "$KEYFILE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
  rm -f "$KEYFILE"
  [ -n "$SIGNATURE" ] || { echo "error: signing produced no signature" >&2; exit 1; }
else
  echo "warning: SPARKLE_PRIVATE_KEY not set, writing an unsigned appcast (updates will be rejected)" >&2
fi

cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Overprint</title>
    <link>https://github.com/${REPO}</link>
    <description>Updates for Overprint</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <link>https://github.com/${REPO}/releases/tag/v${VERSION}</link>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://github.com/${REPO}/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}" />
    </item>
  </channel>
</rss>
XML

echo "==> Wrote $APPCAST"
[ -n "$SIGNATURE" ] && echo "    signed" || echo "    UNSIGNED"
