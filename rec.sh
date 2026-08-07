#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${HF_TOKEN:-}" ]]; then
  TOKEN_CHECK_OUTPUT=$(.venv/bin/python -c "
from clew.config import Config
import sys
try:
    cfg = Config.load()
    sys.exit(0 if cfg.diarization.hf_token else 1)
except Exception as e:
    print(f'Config load failed: {e}', file=sys.stderr)
    sys.exit(2)
" 2>&1) && TOKEN_EXIT=0 || TOKEN_EXIT=$?

  if [[ $TOKEN_EXIT -eq 2 ]]; then
    echo "⚠️  Config validation failed:" >&2
    echo "$TOKEN_CHECK_OUTPUT" >&2
    exit 1
  elif [[ $TOKEN_EXIT -ne 0 ]]; then
    echo "⚠️  No HuggingFace token found."
    echo "   Put it in $HOME/.config/clew/config.toml under [diarization] as hf_token = \"hf_...\" (chmod 600),"
    echo "   or export HF_TOKEN=hf_xxxxx for a one-off run."
    echo "   Get one at https://huggingface.co/settings/tokens after accepting"
    echo "   https://huggingface.co/pyannote/speaker-diarization-community-1"
    exit 1
  fi
fi

MODE="${1:-call}"

case "$MODE" in
  call)
    echo "🎙️  Recording English call — Ctrl+C to stop. Output in ~/clew/"
    exec .venv/bin/clew --mic --diarize --language en
    ;;
  fr)
    echo "🎙️  Recording French call — Ctrl+C to stop."
    exec .venv/bin/clew --mic --diarize --language fr
    ;;
  auto)
    echo "🎙️  Recording, auto language — Ctrl+C to stop."
    exec .venv/bin/clew --mic --diarize
    ;;
  redo)
    DIR="${2:?usage: ./rec.sh redo <meeting-dir>}"
    echo "♻️  Re-processing $DIR from retained audio"
    exec .venv/bin/clew resume "$DIR" --diarize --language en --model large-v3
    ;;
  enroll)
    NAME="${2:?usage: ./rec.sh enroll \"Name\" clip.wav}"
    CLIP="${3:?usage: ./rec.sh enroll \"Name\" clip.wav}"
    exec .venv/bin/clew enroll --name "$NAME" "$CLIP"
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
