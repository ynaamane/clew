#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG_FILE="$HOME/.config/ownscribe/config.toml"

if [[ -z "${HF_TOKEN:-}" ]] && ! grep -qE '^[[:space:]]*hf_token[[:space:]]*=[[:space:]]*"[^"]+"' "$CONFIG_FILE" 2>/dev/null; then
  echo "⚠️  No HuggingFace token found."
  echo "   Put it in $CONFIG_FILE under [diarization] as hf_token = \"hf_...\" (chmod 600),"
  echo "   or export HF_TOKEN=hf_xxxxx for a one-off run."
  echo "   Get one at https://huggingface.co/settings/tokens after accepting"
  echo "   https://huggingface.co/pyannote/speaker-diarization-community-1"
  exit 1
fi

MODE="${1:-call}"

case "$MODE" in
  call)
    echo "🎙️  Recording English call — Ctrl+C to stop. Output in ~/ownscribe/"
    exec .venv/bin/ownscribe --mic --diarize --language en
    ;;
  fr)
    echo "🎙️  Recording French call — Ctrl+C to stop."
    exec .venv/bin/ownscribe --mic --diarize --language fr
    ;;
  auto)
    echo "🎙️  Recording, auto language — Ctrl+C to stop."
    exec .venv/bin/ownscribe --mic --diarize
    ;;
  redo)
    DIR="${2:?usage: ./rec.sh redo <meeting-dir>}"
    echo "♻️  Re-processing $DIR from retained audio"
    exec .venv/bin/ownscribe resume "$DIR" --diarize --language en --model large-v3
    ;;
  enroll)
    NAME="${2:?usage: ./rec.sh enroll \"Name\" clip.wav}"
    CLIP="${3:?usage: ./rec.sh enroll \"Name\" clip.wav}"
    exec .venv/bin/ownscribe enroll --name "$NAME" "$CLIP"
    ;;
  *)
    echo "usage:"
    echo "  ./rec.sh          # record an English call (Ctrl+C to stop)"
    echo "  ./rec.sh fr       # record a French call"
    echo "  ./rec.sh auto     # record, auto-detect language"
    echo "  ./rec.sh redo DIR # re-transcribe a past meeting from kept audio"
    echo "  ./rec.sh enroll \"Sam\" clip.wav   # teach a colleague's voice"
    exit 1
    ;;
esac
