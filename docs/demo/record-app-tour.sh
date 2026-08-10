#!/usr/bin/env bash
# Records docs/demo-app.gif: a window-only tour of the Clew library window
# running on SYNTHETIC demo data.
#
# Guardrails, in order of importance:
#   - The app instance runs with CLEW_HOME pointed at a throwaway home built
#     by make_demo_home.py, so it can never show real meetings. HOME alone is
#     NOT enough: FileManager.homeDirectoryForCurrentUser ignores it, which is
#     exactly why the CLEW_HOME override exists in the app.
#   - Only the demo window id is ever captured, never the screen.
#   - Every synthetic click re-resolves the window bounds first and aborts if
#     the window is gone; the cursor is restored with a move (never a click).
#   - The first still MUST be eyeballed before the GIF is committed: the check
#     that the window shows the three synthetic meetings is visual, no proxy.
#
# The tour steals the cursor for a few seconds and pops a window on the active
# display: run it only while nobody is using the machine.
#
# Usage, from the repo root:
#   bash docs/demo/record-app-tour.sh [work-dir]
#
# Requires: a built dist/Clew.app (SKIP_INSTALL=1 bash swift/build-app.sh),
# ffmpeg, and Accessibility permission for the terminal running this script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${1:-$(mktemp -d /tmp/clew-app-tour.XXXXXX)}"
FAKE_HOME="$WORK/demo-home"
DEMO_APP="$WORK/ClewDemo.app"
MOUSE="$WORK/demo-mouse"
OUT_GIF="$REPO_ROOT/docs/demo-app.gif"

cd "$REPO_ROOT"

echo "==> building synthetic demo home"
uv run --quiet python docs/demo/make_demo_home.py "$FAKE_HOME"
HOME="$FAKE_HOME" uv run --quiet clew backfill

echo "==> building mouse helper"
swiftc -O -o "$MOUSE" docs/demo/demo_mouse.swift

echo "==> preparing demo app copy (regular app, separate bundle id, no URL scheme)"
rm -rf "$DEMO_APP"
cp -R "$REPO_ROOT/dist/Clew.app" "$DEMO_APP"
plutil -replace LSUIElement -bool false "$DEMO_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "com.ownscribe.menubar.demo" "$DEMO_APP/Contents/Info.plist"
plutil -remove CFBundleURLTypes "$DEMO_APP/Contents/Info.plist" >/dev/null 2>&1 || true
codesign --force --deep -s - "$DEMO_APP"

echo "==> launching demo instance on the synthetic home"
open -n --env CLEW_HOME="$FAKE_HOME" --env CLEW_BIN="$REPO_ROOT/.venv/bin/clew" "$DEMO_APP"
sleep 3
PID="$(pgrep -f "ClewDemo.app" | head -1)"
[[ -n "$PID" ]] || { echo "demo instance did not start" >&2; exit 1; }
open "$DEMO_APP"   # LaunchServices activation orders the library window in
sleep 2

window_line() {
    swift "$REPO_ROOT/docs/demo/find_demo_window.swift" --bounds "$PID"
}

# Click a point relative to the window's top-left, then capture a still.
# Re-resolves the window bounds before every click and aborts if it vanished.
capture_state() {  # $1=relX $2=relY $3=outfile
    local line ox oy wid
    line="$(window_line)" || { echo "ABORT: demo window gone" >&2; return 1; }
    wid="${line%% *}"; ox="$(cut -d' ' -f2 <<<"$line")"; oy="$(cut -d' ' -f3 <<<"$line")"
    "$MOUSE" $((ox + $1)) $((oy + $2))
    sleep 1.5
    screencapture -x -o -l "$wid" "$3"
}

SAVED_POS="$("$MOUSE" pos)"
trap '"$MOUSE" ${SAVED_POS% *} ${SAVED_POS#* } move >/dev/null 2>&1 || true; kill "$PID" 2>/dev/null || true' EXIT

echo "==> touring the three meetings (cursor in use for ~10s)"
capture_state 405 178 "$WORK/state_2.png"   # Beta planning
capture_state 405 251 "$WORK/state_3.png"   # Design review
capture_state 405 103 "$WORK/state_1.png"   # back to Product sync

echo "==> assembling GIF (3 states, 2.8s each)"
ffmpeg -y -loglevel error -framerate 10/28 -i "$WORK/state_%d.png" \
    -vf "scale=1080:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
    -loop 0 "$OUT_GIF"

echo "==> done: $OUT_GIF"
echo "    MANDATORY: eyeball every frame before committing (real-data guardrail)"
