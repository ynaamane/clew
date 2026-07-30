#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-/tmp/ui-render}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

mkdir -p "$OUT"

cd "$REPO_ROOT/swift"

OWNSCRIBE_RENDER_UI=1 OWNSCRIBE_RENDER_OUTPUT="$OUT" swift test --filter DesignRenderTests 2>&1 | tee "$OUT/render.log"

if [[ -f "$OUT/library-light.png" ]] && [[ -f "$OUT/library-dark.png" ]]; then
  printf '\n✓ SUCCESS: %s/library-light.png and %s/library-dark.png\n' "$OUT" "$OUT"
  exit 0
else
  printf '\n✗ FAILED: PNGs not created. See %s/render.log\n' "$OUT" >&2
  exit 1
fi
