"""Canary-1B-v2 (MLX) transcription -- A/B pilot engine, not the default.

Runs mlx-audio in a subprocess overlay (see canary_mlx_worker.py) rather than
importing it in-process, so installing this engine never touches the base
project's dependency floors.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from clew.config import CanaryConfig, TranscriptionConfig
from clew.progress import NullProgress
from clew.transcription.base import Transcriber
from clew.transcription.models import Segment, TranscriptResult

_DEFAULT_LANGUAGE = "fr"
_WORKER_MODULE = "clew.transcription.canary_mlx_worker"


class CanaryMlxTranscriber(Transcriber):
    """Transcribes audio using NVIDIA Canary-1B-v2 via mlx-audio (Apple Silicon native).

    Segment-level only: Canary's decoder has no word-level alignment output the
    way whisperx's forced-aligner does, so `Segment.words` is always empty here.
    Diarization/speaker assignment for this engine is segment-overlap based,
    not word-level -- an accepted pilot-scope limitation (see NOTES.md Task#8).

    Canary has no language auto-detection: `transcription_config.language` is
    used as both source and target language when set (transcription, never
    translation); when unset it falls back to `_DEFAULT_LANGUAGE` rather than
    silently defaulting to mlx-audio's own "en".
    """

    def __init__(
        self,
        transcription_config: TranscriptionConfig,
        canary_config: CanaryConfig,
        progress: NullProgress | None = None,
    ) -> None:
        self._canary_config = canary_config
        self._language = transcription_config.language or _DEFAULT_LANGUAGE
        self._progress = progress or NullProgress()

    @property
    def last_speaker_embeddings(self) -> dict[str, list[float]]:
        return {}

    def prepare_models(self, language: str | None = None) -> None:
        if language:
            self._language = language

    def transcribe(self, audio_path: Path, diarize: bool | None = None) -> TranscriptResult:
        progress = self._progress
        progress.begin("transcribing")
        try:
            response = self._run_worker(audio_path)
            progress.complete("transcribing")
        except Exception:
            progress.fail("transcribing")
            raise

        if not response["ok"]:
            raise RuntimeError(f"Canary worker failed: {response['error']}")

        result = response["result"]
        segments = [Segment(text=seg["text"], start=seg["start"], end=seg["end"]) for seg in result["segments"]]
        return TranscriptResult(segments=segments, language=result["language"], duration=result["duration"])

    def _run_worker(self, audio_path: Path) -> dict:
        request = {
            "audio_path": str(audio_path),
            "repo": self._canary_config.repo,
            "language": self._language,
            "max_segment_seconds": self._canary_config.max_segment_seconds,
            "max_tokens": self._canary_config.max_tokens_per_segment,
        }
        process = subprocess.run(
            ["uv", "run", "--with", "mlx-audio>=0.4.1", "python", "-m", _WORKER_MODULE],
            input=json.dumps(request),
            capture_output=True,
            text=True,
        )
        if process.returncode != 0:
            raise RuntimeError(f"Canary worker process exited {process.returncode}: {process.stderr}")
        try:
            return json.loads(process.stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Canary worker returned non-JSON output: {process.stdout!r}") from exc


def is_available() -> bool:
    """True if `uv` is on PATH -- the only hard prerequisite for the overlay subprocess."""
    try:
        return subprocess.run(["uv", "--version"], capture_output=True).returncode == 0
    except FileNotFoundError:
        return False
