"""WhisperX-based transcription with optional diarization."""

from __future__ import annotations

import contextlib
import logging
import math
import os
import warnings
from pathlib import Path

import click

from clew.config import DiarizationConfig, TranscriptionConfig
from clew.progress import (
    DownloadProgressEvent,
    DownloadProgressWriter,
    NullProgress,
    ProgressWriter,
    download_event_fraction,
    format_download_progress,
)
from clew.transcription.base import Transcriber
from clew.transcription.models import Segment, TranscriptResult, Word

_SAMPLE_RATE = 16000

logger = logging.getLogger(__name__)


def _is_degenerate_embedding(values: list[float]) -> bool:
    """True for a zero-norm or non-finite centroid.

    pyannote zero-pads a cluster's embedding when it cannot compute a real one
    for it (too little audio attributed to that speaker). Such a vector scores
    0.0 against every enrolled voiceprint (cosine_similarity's own zero-norm
    guard), so silently matching against it makes that speaker permanently
    un-nameable and indistinguishable from a genuine no-match.
    """
    norm = math.sqrt(sum(v * v for v in values))
    return norm == 0.0 or not math.isfinite(norm)


def _resolve_diarization_device(configured: str) -> str:
    """Resolve the configured diarization.device setting to a real torch device.

    "cpu" always wins, even when MPS is available -- the explicit escape hatch.
    "auto" (default) and "mps" both prefer MPS but degrade to CPU when it isn't
    available on this machine, exactly like the zero-norm centroid guard: never
    crash, just fall back and log why. Any unrecognized value (typo, stale
    config) is treated as "auto" rather than crashing the pipeline.
    """
    if configured == "cpu":
        return "cpu"

    import torch

    if torch.backends.mps.is_available():
        return "mps"

    if configured == "mps":
        logger.warning(
            "diarization.device is set to 'mps' but MPS is not available on this machine; falling back to CPU."
        )
    return "cpu"


def _performance_core_count() -> int | None:
    import subprocess

    try:
        out = subprocess.run(
            ["sysctl", "-n", "hw.perflevel0.physicalcpu"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        )
        return int(out.stdout.strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def default_cpu_threads() -> int:
    return _performance_core_count() or os.cpu_count() or 1


class WhisperXTranscriber(Transcriber):
    """Transcribes audio using WhisperX (faster-whisper + optional pyannote diarization)."""

    def __init__(
        self,
        transcription_config: TranscriptionConfig,
        diarization_config: DiarizationConfig | None = None,
        progress: NullProgress | None = None,
    ) -> None:
        self._tx_config = transcription_config
        self._diar_config = diarization_config
        self._progress = progress or NullProgress()
        self._model = None
        self._align_models: dict[str, tuple[object, object]] = {}
        self._diarize_model = None
        self._last_speaker_embeddings: dict[str, list[float]] = {}

    @property
    def last_speaker_embeddings(self) -> dict[str, list[float]]:
        return self._last_speaker_embeddings

    def _load_model(self):
        import whisperx

        device = "cpu"
        compute_type = "int8"
        asr_options = {}
        if self._tx_config.initial_prompt:
            asr_options["initial_prompt"] = self._tx_config.initial_prompt
        if self._tx_config.hotwords:
            asr_options["hotwords"] = self._tx_config.hotwords
        threads = self._tx_config.cpu_threads or default_cpu_threads()
        self._model = whisperx.load_model(
            self._tx_config.model,
            device,
            compute_type=compute_type,
            language=self._tx_config.language or None,
            asr_options=asr_options or None,
            threads=threads,
        )

    def _configure_runtime_env(self) -> None:
        os.environ.setdefault("TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD", "1")
        if self._diar_config is None or not self._diar_config.telemetry:
            os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
            os.environ.setdefault("PYANNOTE_METRICS_ENABLED", "0")

    def _set_detail(self, key: str, text: str | None) -> None:
        set_detail = getattr(self._progress, "set_detail", None)
        if callable(set_detail):
            set_detail(key, text)

    def _set_prepare_detail(self, text: str | None) -> None:
        self._set_detail("preparing_models", text)

    def _on_download_progress(self, step_key: str, stage_label: str, event: DownloadProgressEvent) -> None:
        fraction = download_event_fraction(event)
        if fraction is not None:
            self._progress.update(step_key, fraction)
        formatted = format_download_progress(event, include_percent=fraction is None)
        if formatted:
            self._set_detail(step_key, f"{stage_label}: {formatted}")
        elif fraction is None and event.percent is not None:
            self._set_detail(step_key, f"{stage_label}: {int(event.percent)}%")

    def _capture_download_output(self, step_key: str, stage_label: str, fn, *args, **kwargs):
        writer = DownloadProgressWriter(lambda event: self._on_download_progress(step_key, stage_label, event))
        self._set_detail(step_key, stage_label)
        with contextlib.ExitStack() as stack:
            stack.enter_context(contextlib.redirect_stdout(writer))
            stack.enter_context(contextlib.redirect_stderr(writer))
            result = fn(*args, **kwargs)
        writer.flush()
        return result

    def _prepare_transcription_models(
        self,
        *,
        language: str | None,
        step_key: str,
        show_deferred_align_note: bool = False,
    ) -> None:
        if self._model is None:
            self._capture_download_output(
                step_key,
                f"Loading Whisper model ({self._tx_config.model})",
                self._load_model,
            )

        if language:
            self._load_align_model(language, step_key=step_key)
        elif show_deferred_align_note:
            self._set_detail(
                step_key,
                "Whisper model ready. Alignment model will load after language detection.",
            )

    def _load_align_model(self, language: str, *, step_key: str = "preparing_models") -> tuple[object, object]:
        import whisperx

        if language in self._align_models:
            return self._align_models[language]

        align_model, align_metadata = self._capture_download_output(
            step_key,
            f"Loading alignment model ({language})",
            whisperx.load_align_model,
            language_code=language,
            device="cpu",
        )
        self._align_models[language] = (align_model, align_metadata)
        return align_model, align_metadata

    def _load_diarization_pipeline(self, *, step_key: str = "preparing_models"):
        from whisperx.diarize import DiarizationPipeline

        if self._diarize_model is not None:
            return self._diarize_model

        self._diarize_model = self._capture_download_output(
            step_key,
            "Loading diarization pipeline",
            DiarizationPipeline,
            token=self._diar_config.hf_token,
            device=_resolve_diarization_device(self._diar_config.device),
        )
        return self._diarize_model

    def prepare_models(self, language: str | None = None) -> None:
        self._configure_runtime_env()
        progress = self._progress
        progress.begin("preparing_models")
        try:
            if self._model is not None:
                self._set_prepare_detail(f"Whisper model ready ({self._tx_config.model})")

            align_language = language or self._tx_config.language or None
            self._prepare_transcription_models(
                language=align_language,
                step_key="preparing_models",
                show_deferred_align_note=True,
            )

            if self._diar_config and self._diar_config.enabled and self._diar_config.hf_token:
                self._load_diarization_pipeline()

            progress.complete("preparing_models")
        except Exception:
            progress.fail("preparing_models")
            raise

    def transcribe(self, audio_path: Path, diarize: bool | None = None) -> TranscriptResult:
        import shutil

        if not shutil.which("ffmpeg"):
            click.echo(
                "Error: ffmpeg is not installed. WhisperX requires ffmpeg for audio decoding.\n"
                "Install with: brew install ffmpeg",
                err=True,
            )
            raise SystemExit(1)

        # --- Telemetry toggle (must happen before importing whisperx) ---
        self._configure_runtime_env()

        want_diarize = diarize if diarize is not None else bool(self._diar_config and self._diar_config.enabled)

        hf_token_warning: str | None = None
        if want_diarize and self._diar_config and not self._diar_config.hf_token:
            hf_token_warning = (
                "Diarization requested but no HF token configured. "
                "Set HF_TOKEN env var or hf_token in config. Skipping."
            )

        # Suppress all noise from whisperx / pyannote / torch / lightning
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            # Suppress named loggers that bypass root (whisperx has propagate=False)
            for name in ("whisperx", "lightning", "pytorch_lightning"):
                logging.getLogger(name).setLevel(logging.WARNING)
            result = self._transcribe_inner(audio_path, want_diarize=want_diarize)

        if hf_token_warning:
            click.echo(hf_token_warning, err=True)

        return result

    def _transcribe_inner(self, audio_path: Path, want_diarize: bool) -> TranscriptResult:
        import whisperx

        progress = self._progress

        devnull = open(os.devnull, "w")  # noqa: SIM115
        try:
            # Outer redirect: catch all stray print() from pyannote/lightning
            with contextlib.redirect_stdout(devnull):
                progress.begin("transcribing")

                self._prepare_transcription_models(
                    language=self._tx_config.language or None,
                    step_key="transcribing",
                    show_deferred_align_note=False,
                )
                self._set_detail("transcribing", None)

                audio = whisperx.load_audio(str(audio_path))

                tx_writer = ProgressWriter(
                    lambda frac: progress.update("transcribing", frac),
                    offset=0.0,
                    scale=0.5,
                )
                align_writer = ProgressWriter(
                    lambda frac: progress.update("transcribing", frac),
                    offset=0.5,
                    scale=0.5,
                )

                # Nested redirect overrides devnull → captures progress
                with contextlib.redirect_stdout(tx_writer):
                    result = self._model.transcribe(audio, batch_size=16, print_progress=True, combined_progress=True)

                language = result.get("language", "")

                align_model, align_metadata = self._load_align_model(language, step_key="transcribing")
                with contextlib.redirect_stdout(align_writer):
                    result = whisperx.align(
                        result["segments"],
                        align_model,
                        align_metadata,
                        audio,
                        device="cpu",
                        return_char_alignments=False,
                        print_progress=True,
                        combined_progress=True,
                    )

                progress.complete("transcribing")

                # --- Optional diarization ---
                if want_diarize and self._diar_config and self._diar_config.hf_token:
                    result = self._diarize(audio, result)
        finally:
            devnull.close()

        # --- Convert to our data models ---
        segments = []
        for seg in result.get("segments", []):
            words = []
            for w in seg.get("words", []):
                words.append(
                    Word(
                        text=w.get("word", ""),
                        start=w.get("start", 0.0),
                        end=w.get("end", 0.0),
                        speaker=w.get("speaker"),
                        score=w.get("score", 0.0),
                    )
                )
            segments.append(
                Segment(
                    text=seg.get("text", ""),
                    start=seg.get("start", 0.0),
                    end=seg.get("end", 0.0),
                    speaker=seg.get("speaker"),
                    words=words,
                )
            )

        duration = audio.shape[0] / float(_SAMPLE_RATE)
        return TranscriptResult(segments=segments, language=language, duration=duration)

    def _diarize(self, audio, result):
        import pandas as pd
        import torch
        import whisperx

        progress = self._progress
        progress.begin("diarizing")
        diarize_model = self._load_diarization_pipeline(step_key="diarizing")

        # Build audio_data dict the same way whisperx does internally
        audio_data = {
            "waveform": torch.from_numpy(audio[None, :]),
            "sample_rate": _SAMPLE_RATE,
        }

        diarize_kwargs = {}
        if self._diar_config.min_speakers > 0:
            diarize_kwargs["min_speakers"] = self._diar_config.min_speakers
        if self._diar_config.max_speakers > 0:
            diarize_kwargs["max_speakers"] = self._diar_config.max_speakers

        # Call pyannote pipeline directly with progress hook
        diarization = diarize_model.model(audio_data, hook=progress.diarization_hook, **diarize_kwargs)

        progress.complete("diarizing")

        self._last_speaker_embeddings = self._extract_cluster_embeddings(diarization)

        # Convert to DataFrame (replicating whisperx/diarize.py logic)
        diarize_df = pd.DataFrame(
            diarization.speaker_diarization.itertracks(yield_label=True),
            columns=["segment", "label", "speaker"],
        )
        diarize_df["start"] = diarize_df["segment"].apply(lambda x: x.start)
        diarize_df["end"] = diarize_df["segment"].apply(lambda x: x.end)

        return whisperx.assign_word_speakers(diarize_df, result)

    @staticmethod
    def _extract_cluster_embeddings(diarization) -> dict[str, list[float]]:
        embeddings = getattr(diarization, "speaker_embeddings", None)
        if embeddings is None:
            return {}
        labels = diarization.speaker_diarization.labels()
        result: dict[str, list[float]] = {}
        for i, label in enumerate(labels):
            values = embeddings[i].tolist()
            if _is_degenerate_embedding(values):
                logger.warning(
                    "Diarized speaker %s has a degenerate (zero-norm) embedding; "
                    "excluding it from voiceprint matching for this run.",
                    label,
                )
                continue
            result[label] = values
        return result
