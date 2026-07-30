#!/usr/bin/env bash
# Capture visual + accessibility evidence for ONE app window, for design review.
# Never captures the screen: resolves the window id by OWNER first, then -l.
set -euo pipefail

OWNER="${1:-MeetingScribe}"
OUT="${2:-/tmp/ui-evidence}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -x "$HERE/ui-evidence" ]]; then
  swiftc -O "$HERE/main.swift" -o "$HERE/ui-evidence"
fi

mkdir -p "$OUT"
INFO="$("$HERE/ui-evidence" "$OWNER" "$OUT")" || {
  printf 'No on-screen window owned by %s.\n' "$OWNER" >&2
  printf 'MeetingScribe is a menu-bar app: open its window with Cmd-0 first.\n' >&2
  exit 2
}
printf '%s\n' "$INFO"

WINDOW_ID="$(printf '%s\n' "$INFO" | awk '/^WINDOW_ID/ {print $2}')"
[[ -n "$WINDOW_ID" ]] || { printf 'could not resolve a window id\n' >&2; exit 3; }

screencapture -x -o -l "$WINDOW_ID" "$OUT/window.png"
printf 'SCREENSHOT %s\n' "$OUT/window.png"
