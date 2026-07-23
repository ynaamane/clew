"""Canary-1B-v2 (MLX) worker -- runs ONLY inside a `uv run --with mlx-audio` overlay.

mlx-audio's first Canary-capable release (0.4.1+) requires huggingface-hub>=1.0,
which conflicts with whisperx's declared huggingface-hub<1.0 ceiling (the ceiling
is stale -- whisperx works fine against huggingface-hub 1.x at runtime, per
m-bain/whisperX#1375 -- but the PACKAGE METADATA still declares the old bound,
and uv's resolver enforces declared bounds regardless of runtime reality). uv
locks one concrete version per package project-wide, so adding mlx-audio to
this project's own pyproject.toml would force EVERY user onto an unreleased
whisperx release candidate just to support this opt-in pilot engine. Running
this worker as a subprocess under `uv run --with "mlx-audio>=0.4.1"` layers
mlx-audio onto the existing project venv for this invocation only, without
ever touching pyproject.toml, uv.lock, or the venv other callers use.

Talks to its parent via stdin/stdout: reads a JSON request on stdin, writes a
JSON response to stdout. Never imported directly by ownscribe's own process --
CanaryMlxTranscriber invokes it via subprocess, matching the existing
ownscribe-audio (Swift) pattern of an isolated dependency surface.
"""

from __future__ import annotations

import json
import sys

_SAMPLE_RATE = 16000


def _run(audio_path: str, repo: str, language: str, max_segment_seconds: float, max_tokens: int) -> dict:
    import mlx.core as mx
    import whisperx
    from faster_whisper.vad import VadOptions, get_speech_timestamps
    from mlx_audio.stt import load

    model = load(repo)
    audio = whisperx.load_audio(audio_path)

    opts = VadOptions(max_speech_duration_s=max_segment_seconds)
    spans = get_speech_timestamps(audio, vad_options=opts, sampling_rate=_SAMPLE_RATE)

    segments = []
    for span in spans:
        span_start, span_end = span["start"], span["end"]
        chunk = audio[span_start:span_end]
        if chunk.shape[0] == 0:
            continue
        result = model.generate(
            chunk,
            source_lang=language,
            target_lang=language,
            max_tokens=max_tokens,
            dtype=mx.float32,
        )
        text = result.text.strip()
        if not text:
            continue
        segments.append(
            {
                "text": text,
                "start": span_start / float(_SAMPLE_RATE),
                "end": span_end / float(_SAMPLE_RATE),
            }
        )

    return {
        "segments": segments,
        "duration": audio.shape[0] / float(_SAMPLE_RATE),
        "language": language,
    }


def main() -> None:
    request = json.loads(sys.stdin.read())
    try:
        response = _run(
            audio_path=request["audio_path"],
            repo=request["repo"],
            language=request["language"],
            max_segment_seconds=request["max_segment_seconds"],
            max_tokens=request["max_tokens"],
        )
        json.dump({"ok": True, "result": response}, sys.stdout)
    except Exception as exc:
        json.dump({"ok": False, "error": f"{type(exc).__name__}: {exc}"}, sys.stdout)


if __name__ == "__main__":
    main()
