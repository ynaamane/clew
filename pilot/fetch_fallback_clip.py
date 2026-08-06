"""Fetch and prepare the public FR/EN code-switching fallback clip for the pilot.

Runnable without any user-provided audio, per the ticket's requirement. Downloads a
30.5s window from FEBLOC (French-English Bilingual Loved Ones Corpus,
Gosselin, University of Ottawa, CC-BY 4.0, https://febloc.ca), a real
recorded conversation with genuine intra-sentential French/English
code-switching and a millisecond-aligned CHAT-format ground-truth
transcript -- verified downloadable and license-checked directly against
OSF's API before use (no restrictive data-use agreement, no third party
beyond OSF's own public hosting).

The window (1490.158s-1520.634s into FEBLOC-pair01-anon.wav) was hand-picked
by reading the real .cha transcript for a dense, self-contained cluster of
intra-sentential switches at a natural utterance boundary -- not the first
or a random window, since a code-switch pilot needs actual switches to
measure anything.
"""

from __future__ import annotations

import json
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cha_parser import parse_cha, utterances_in_window

_FEBLOC_WAV_URL = "https://osf.io/download/6a5d5f1b96bc5e640ae14767/"
_FEBLOC_TRANSCRIPT_URL = "https://osf.io/download/6a5d5ef16fcadfd678d53f75/"
_WINDOW_START_S = 1490.158
_WINDOW_END_S = 1520.634


def _run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{result.stderr}")


def fetch_and_prepare(output_dir: Path) -> dict:
    """Download FEBLOC, extract the target window, build the reference transcript.

    Returns a dict with keys: clip_path, reference_path, window_start_s,
    window_end_s, utterance_count.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    full_wav = output_dir / "febloc_pair01_full.wav"
    transcript_path = output_dir / "febloc_pair01.cha"
    clip_path = output_dir / "fallback_clip.wav"
    reference_path = output_dir / "fallback_reference.json"

    if not full_wav.exists():
        _run(["curl", "-sL", "--retry", "3", "--retry-delay", "2", "-o", str(full_wav), _FEBLOC_WAV_URL])
    if not transcript_path.exists():
        _run(["curl", "-sL", "--retry", "3", "--retry-delay", "2", "-o", str(transcript_path), _FEBLOC_TRANSCRIPT_URL])

    _run(
        [
            "ffmpeg", "-y",
            "-i", str(full_wav),
            "-ss", str(_WINDOW_START_S),
            "-to", str(_WINDOW_END_S),
            "-ac", "1", "-ar", "16000",
            str(clip_path),
            "-loglevel", "error",
        ]
    )

    utterances = parse_cha(transcript_path.read_text())
    window = utterances_in_window(utterances, int(_WINDOW_START_S * 1000), int(_WINDOW_END_S * 1000))

    reference = {
        "source": "FEBLOC pair01 (CC-BY 4.0, https://febloc.ca)",
        "window_start_s": _WINDOW_START_S,
        "window_end_s": _WINDOW_END_S,
        "utterances": [
            {
                **asdict(u),
                "start_s": (u.start_ms / 1000.0) - _WINDOW_START_S,
                "end_s": (u.end_ms / 1000.0) - _WINDOW_START_S,
            }
            for u in window
        ],
    }
    reference_path.write_text(json.dumps(reference, indent=2, ensure_ascii=False))

    return {
        "clip_path": str(clip_path),
        "reference_path": str(reference_path),
        "window_start_s": _WINDOW_START_S,
        "window_end_s": _WINDOW_END_S,
        "utterance_count": len(window),
    }


def main() -> None:
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "data"
    result = fetch_and_prepare(output_dir)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
