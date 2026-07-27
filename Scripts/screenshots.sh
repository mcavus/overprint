#!/bin/bash
#
# Retakes the README screenshots in docs/.
#
# The screenshots go stale whenever the UI changes, and hand-taking them drifts: a different window
# size, a different post selected, a half-finished draft in the editor. This script pins everything
# that can be pinned (the demo content, the window size, the capture style, the output path) so the
# only variable left is the two or three clicks it cannot make for you.
#
# Usage:
#   Scripts/screenshots.sh setup     reset the demo site, seed Recents, relaunch the app
#   Scripts/screenshots.sh launch    capture the launch window       -> docs/screenshot-launch.png
#   Scripts/screenshots.sh hero      capture Write mode              -> docs/screenshot-hero.png
#   Scripts/screenshots.sh write     capture the Ask Claude popover  -> docs/screenshot-write.png
#   Scripts/screenshots.sh build     capture Build mode              -> docs/screenshot-build.png
#
# Run `setup` once, then each capture after putting the app in the state it names.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS="$REPO_ROOT/docs"
DEMO_PARENT="$HOME/Overprint Demo"
DEMO="$DEMO_PARENT/Field Notes"
EXAMPLE="$REPO_ROOT/OverprintKit/Sources/OverprintKit/Resources/Examples/starter"
APP_ID="com.mcavus.Overprint"
APP_PATH="/Applications/Overprint.app"

# Window size in POINTS. On a Retina display the captured PNG is twice this, plus the drop shadow.
# Changing it changes every screenshot's dimensions, so change it once and retake all three.
WIN_W=1200
WIN_H=800

# --- window capture -----------------------------------------------------------------------------
# `screencapture -l` needs a CGWindowID, which neither AppleScript nor the shell can produce. A
# ten-line Swift helper can, and swiftc is already a prerequisite for building the app at all. It is
# compiled to a cache dir rather than committed, so no binary lands in the repo.
HELPER_DIR="${TMPDIR:-/tmp}/overprint-shots"
HELPER="$HELPER_DIR/winid"

build_helper() {
  [ -x "$HELPER" ] && return 0
  mkdir -p "$HELPER_DIR"
  cat > "$HELPER_DIR/winid.swift" <<'SWIFT'
import CoreGraphics
import Foundation

// Prints the CGWindowID of the largest on-screen window owned by the named app.
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] else { exit(1) }

var best = (id: 0, area: 0.0)
for window in list {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.localizedCaseInsensitiveContains(target) else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = (bounds["Width"] as? Double) ?? 0
    let height = (bounds["Height"] as? Double) ?? 0
    // Skip the small helper windows SwiftUI keeps around (popovers, shadows, tooltips).
    guard width >= 400, height >= 300 else { continue }
    let area = width * height
    if area > best.area { best = (window[kCGWindowNumber as String] as? Int ?? 0, area) }
}
guard best.id != 0 else {
    FileHandle.standardError.write(Data("no on-screen window found for \"\(target)\"\n".utf8))
    exit(1)
}
print(best.id)
SWIFT
  swiftc -O "$HELPER_DIR/winid.swift" -o "$HELPER"
}

# Resize the front window so every screenshot has identical dimensions.
#
# Needs Automation permission (System Settings > Privacy & Security > Automation > your terminal >
# System Events), which is separate from Screen Recording. Without it the capture still works, it
# just uses whatever size the window already has, so this warns rather than aborting. The shots stay
# consistent with each other either way, as long as you do not resize the window between them.
size_window() {
  if ! osascript <<OSA >/dev/null 2>&1
tell application "System Events"
  tell process "Overprint"
    set frontmost to true
    set position of window 1 to {120, 80}
    set size of window 1 to {$WIN_W, $WIN_H}
  end tell
end tell
OSA
  then
    echo "    note: could not resize the window (needs Automation > System Events permission)." >&2
    echo "          Capturing at its current size instead." >&2
    osascript -e 'tell application "Overprint" to activate' >/dev/null 2>&1 || true
  fi
}

capture() {
  local out="$1"
  local mode="${2:-resize}"
  build_helper
  [ "$mode" = "nosize" ] || size_window
  sleep 1   # let the resize settle and the preview relayout before the shutter
  local id
  id="$("$HELPER" Overprint)"
  # No -o: the drop shadow is part of the existing assets' look.
  screencapture -x -l"$id" "$out"
  echo "==> Wrote $out ($(sips -g pixelWidth -g pixelHeight "$out" | tail -2 | tr -d ' \n' | sed 's/pixelWidth:/w=/;s/pixelHeight:/ h=/'))"
}

require_app() {
  pgrep -x Overprint >/dev/null || {
    echo "error: Overprint is not running. Run 'Scripts/screenshots.sh setup' first." >&2
    exit 1
  }
}

case "${1:-}" in
setup)
  echo "==> Resetting the demo site at $DEMO"
  rm -rf "$DEMO_PARENT"
  mkdir -p "$DEMO_PARENT"
  cp -R "$EXAMPLE" "$DEMO"
  # Build once so the preview has something to serve the instant the site opens.
  swift run --package-path "$REPO_ROOT/OverprintKit" overprint build "$DEMO" >/dev/null

  echo "==> Seeding Recents so the demo site is the top row"
  osascript -e 'quit app "Overprint"' 2>/dev/null || true
  sleep 1
  # RecentsStore stores "recents.v1" as JSON-encoded Data, not a string, so this has to go in as
  # -data (hex). lastOpened is a Swift Date, which JSONEncoder writes with the default
  # .deferredToDate strategy: seconds since the 2001 reference date, not the Unix epoch.
  RECENTS_JSON="$(printf '[{"path":"%s","name":"Field Notes","lastOpened":%s}]' \
    "$DEMO" "$(( $(date +%s) - 978307200 ))")"
  defaults write "$APP_ID" "recents.v1" -data "$(printf '%s' "$RECENTS_JSON" | xxd -p | tr -d '\n')"
  defaults write "$APP_ID" "showLaunchAtStart" -bool true

  # Launch by explicit path, never `open -a Overprint`. Xcode registers every DerivedData build
  # with LaunchServices, so the name resolves to whichever copy was registered last, and you end up
  # screenshotting a stale Debug build without noticing.
  if [ ! -d "$APP_PATH" ]; then
    echo "error: no app at $APP_PATH. Build and install one first:" >&2
    echo "  SKIP_NOTARIZE=1 Scripts/release.sh 0.1.0" >&2
    echo "  cp -R .release/DerivedData/Build/Products/Release/Overprint.app /Applications/" >&2
    exit 1
  fi
  open "$APP_PATH"
  echo
  echo "Now click 'Field Notes' in Recents. The app opens in Write mode with the newest post"
  echo "selected and the preview server already running, which is the hero shot."
  echo "Then: Scripts/screenshots.sh hero"
  ;;

launch)
  require_app
  echo "Expecting: the launch window, with 'Field Notes' at the top of Recents."
  # The launch window is a fixed size the app itself sets; resizing it would distort the layout.
  capture "$DOCS/screenshot-launch.png" nosize
  ;;

hero)
  require_app
  capture "$DOCS/screenshot-hero.png"
  ;;

write)
  require_app
  echo "Expecting: Write mode with the 'Ask Claude' popover open over the current draft."
  capture "$DOCS/screenshot-write.png"
  ;;

build)
  require_app
  echo "Expecting: Build mode showing a completed assistant turn and the live preview."
  capture "$DOCS/screenshot-build.png"
  ;;

*)
  sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac
