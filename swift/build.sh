#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin"

mkdir -p "$BIN_DIR"

echo "Building ownscribe-audio..."
(cd "$SCRIPT_DIR" && swift build -c release --product ownscribe-audio)

cp "$SCRIPT_DIR/.build/release/ownscribe-audio" "$BIN_DIR/ownscribe-audio"

echo "Built: $BIN_DIR/ownscribe-audio"
