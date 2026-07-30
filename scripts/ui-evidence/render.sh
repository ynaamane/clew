#!/usr/bin/env bash
# Off-screen design-review harness — renders LibraryWindow in both appearances.
# Works with the screen LOCKED. Never makes a visible window.
# Usage: bash render.sh /path/to/output/dir
set -euo pipefail

OUT="${1:-/tmp/ui-render}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

# Isolation: copy a few meetings into /tmp, never touch live ~/ownscribe
MEETINGS_COPY="/tmp/ownscribe-render-isolated"
LIVE_MEETINGS="$HOME/ownscribe"

if [[ ! -d "$LIVE_MEETINGS" ]]; then
  printf 'No meetings at %s — nothing to render.\n' "$LIVE_MEETINGS" >&2
  exit 2
fi

# Copy up to 3 meetings for rendering (read-only access to originals is fine per task spec)
rm -rf "$MEETINGS_COPY"
mkdir -p "$MEETINGS_COPY"
find "$LIVE_MEETINGS" -mindepth 1 -maxdepth 1 -type d | head -3 | while read -r dir; do
  cp -R "$dir" "$MEETINGS_COPY/"
done

cd "$REPO_ROOT/swift"

# Build the Package modules first (provides OwnscribeCapture module)
swift build > /dev/null 2>&1

BUILD_DIR="$(swift build --show-bin-path)"

# Now compile MenuBar sources + renderer with access to the OwnscribeCapture module
swiftc -O \
  -target arm64-apple-macos26.0 \
  -swift-version 5 \
  -I "$BUILD_DIR/Modules" \
  -L "$BUILD_DIR" \
  -module-name RenderOffscreen \
  Sources/OwnscribeMenuBar/*.swift \
  "$HERE/render-offscreen.swift" \
  -o "$HERE/render-offscreen" \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework AppKit \
  -framework SwiftUI \
  -Xlinker "$BUILD_DIR"/OwnscribeCapture.build/*.o 2>&1 | head -50

if [[ ! -x "$HERE/render-offscreen" ]]; then
  printf 'Compilation failed — no binary produced.\n' >&2
  exit 3
fi

mkdir -p "$OUT"
"$HERE/render-offscreen" "$OUT" "$MEETINGS_COPY"
RC=$?

if [[ $RC -eq 0 ]]; then
  printf 'SUCCESS: %s/library-light.png and %s/library-dark.png\n' "$OUT" "$OUT"
else
  printf 'Rendering failed (exit %d).\n' "$RC" >&2
fi

exit $RC
