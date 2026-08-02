#!/bin/bash
# Builds the app icon from overprint-logos/overprint-mark.png.
#
# The mark sits on a white rounded square on Apple's macOS icon grid: on a 1024 canvas the plate is
# 824 wide, inset 100, corner radius 185. Without a plate the icon is transparent, so the Dock and
# Finder show their own surface through it.
#
# Needs ImageMagick. Run from the repo root, then rebuild the app.
set -euo pipefail

MARK=overprint-logos/overprint-mark.png
SET=overprint-logos/AppIcon.iconset
ICNS=Overprint/Overprint/Resources/AppIcon.icns
MARK_WIDTH=570

command -v magick >/dev/null || { echo "ImageMagick not found: brew install imagemagick" >&2; exit 1; }
[ -f "$MARK" ] || { echo "missing $MARK" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

magick -size 1024x1024 xc:transparent -fill white \
  -draw "roundrectangle 100,100 923,923 185,185" PNG32:"$work/plate.png"
magick "$MARK" -resize ${MARK_WIDTH}x${MARK_WIDTH} PNG32:"$work/mark.png"
magick "$work/plate.png" "$work/mark.png" -gravity center -composite PNG32:"$work/master.png"

rm -rf "$SET"
mkdir -p "$SET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  size=${spec%% *}; name=${spec#* }
  magick "$work/master.png" -resize ${size}x${size} PNG32:"$SET/$name.png"
done

iconutil -c icns "$SET" -o "$ICNS"
echo "wrote $ICNS and $SET"
