"""Pipeline orchestration: record -> transcribe -> summarize -> output."""

from __future__ import annotations

import logging
import re
import select
import signal
import sys
import termios
import time
import tty
from datetime import datetime
from pathlib import Path

import click

from ownscribe.config import Config
from ownscribe.correction import correct_transcript
from ownscribe.progress import (
    DownloadProgressEvent,
    PipelineProgress,
    download_event_fraction,
    format_download_progress,
)
from ownscribe.summarization import create_summarizer

# A standard WAV file header (RIFF + fmt + data chunk header) is 44 bytes.
# Files at or below this size contain no audio frames.
_WAV_HEADER_SIZE = 44


def _check_audio_silence(audio_path: Path) -> None:
    """Check if the recorded audio is silent and warn the user."""
    try:
        import numpy as np
        import soundfile as sf
    except ImportError:
        return  # Skip check if deps not available

    try:
        # Read up to 5 seconds
        info = sf.info(audio_path)
        frames_to_read = min(int(info.samplerate * 5), info.frames)
        data, _ = sf.read(audio_path, frames=frames_to_read, dtype="float32")
        peak = float(np.max(np.abs(data)))
    except Exception:
        return  # Don't block pipeline on check failure

    if peak < 1e-6:
        click.echo(
            "\nError: Recorded audio is completely silent (peak amplitude ~0).\n"
            "This usually means Screen Recording permission is missing.\n"
            "Fix: System Settings > Privacy & Security > Screen Recording "
            "— enable your terminal app, then restart it.\n",
            err=True,
        )
        raise SystemExit(1)


_RMS_SILENCE_THRESHOLD = 1e-5


def _track_rms(audio_path: Path) -> float | None:
    """Compute RMS amplitude over the first 5s of audio_path, or None if unreadable."""
    try:
        import numpy as np
        import soundfile as sf
    except ImportError:
        return None

    try:
        info = sf.info(audio_path)
        frames_to_read = min(int(info.samplerate * 5), info.frames)
        data, _ = sf.read(audio_path, frames=frames_to_read, dtype="float32")
        return float(np.sqrt(np.mean(np.square(data))))
    except Exception:
        return None


def _check_dual_track_silence(system_path: Path, mic_path: Path) -> None:
    """Warn (without blocking) if either retained track is silent, naming which one."""
    system_rms = _track_rms(system_path)
    mic_rms = _track_rms(mic_path)

    system_silent = system_rms is not None and system_rms < _RMS_SILENCE_THRESHOLD
    mic_silent = mic_rms is not None and mic_rms < _RMS_SILENCE_THRESHOLD

    if system_silent and mic_silent:
        click.echo(
            "\nWarning: Both system audio and microphone tracks are silent "
            "(RMS ~0). Check Screen Recording AND Microphone permissions.",
            err=True,
        )
    elif system_silent:
        click.echo(
            "\nWarning: System audio track is silent (RMS ~0), microphone is not. "
            "Check Screen Recording permission — remote speakers may be missing "
            "from the transcript.",
            err=True,
        )
    elif mic_silent:
        click.echo(
            "\nWarning: Microphone track is silent (RMS ~0), system audio is not. "
            "Check Microphone permission — your own segments may be missing "
            "from the transcript.",
            err=True,
        )


def _get_output_dir(config: Config) -> Path:
    """Create and return a timestamped output directory."""
    base = config.output.resolved_dir
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M")
    out_dir = base / timestamp
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir


def _get_output_audio_dir(config: Config, out_dir: Path) -> Path:
    """Create and return the audio directory for a run, mirroring out_dir's name."""
    audio_dir = config.output.resolved_audio_dir / out_dir.name
    audio_dir.mkdir(parents=True, exist_ok=True)
    return audio_dir


def _rename_output_dir(directory: Path, title_slug: str) -> Path:
    """Append title slug to directory name. Returns the new path."""
    new_dir = directory.parent / f"{directory.name}_{title_slug}"
    try:
        directory.rename(new_dir)
        return new_dir
    except Exception:
        logging.getLogger(__name__).warning("Could not rename output directory", exc_info=True)
        return directory


def _create_recorder(config: Config):
    """Create the appropriate audio recorder based on config."""
    if config.audio.backend == "coreaudio" and not config.audio.device:
        from ownscribe.audio.coreaudio import CoreAudioRecorder

        recorder = CoreAudioRecorder(
            mic=config.audio.mic,
            mic_device=config.audio.mic_device,
            capture_mode=config.audio.capture_mode,
            silence_timeout=config.audio.silence_timeout,
            capture_backend=config.audio.capture_backend,
            echo_cancellation=config.audio.echo_cancellation,
        )
        if recorder.is_available():
            return recorder
        click.echo("Core Audio helper not found, falling back to sounddevice.")

    from ownscribe.audio.sounddevice_recorder import SoundDeviceRecorder

    device = config.audio.device or None
    # Try to parse as int (device index)
    if isinstance(device, str) and device.isdigit():
        device = int(device)
    return SoundDeviceRecorder(device=device, silence_timeout=config.audio.silence_timeout)


def _create_transcriber(config: Config, progress=None):
    """Create the configured transcriber (whisperx default, or canary_mlx for the A/B pilot)."""
    if config.transcription.engine == "canary_mlx":
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber, is_available

        if not is_available():
            click.echo(
                "Error: [transcription] engine = 'canary_mlx' requires `uv` on PATH "
                "(used to run the mlx-audio overlay subprocess). Install uv or switch "
                "back to engine = 'whisperx'.",
                err=True,
            )
            raise SystemExit(1)
        return CanaryMlxTranscriber(config.transcription, config.canary, progress=progress)

    from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

    diar_config = config.diarization if config.diarization.enabled else None
    return WhisperXTranscriber(config.transcription, diar_config, progress=progress)


_OWNER_SPEAKER_LABEL = "Owner"


def _find_dual_tracks(audio_path: Path) -> tuple[Path, Path] | None:
    """Return (system_path, mic_path) next to audio_path if both were retained, else None."""
    system_path = audio_path.parent / "system.wav"
    mic_path = audio_path.parent / "mic.wav"
    if system_path.exists() and mic_path.exists():
        return system_path, mic_path
    return None


def _dual_track_paths(audio_path: Path) -> tuple[Path, ...]:
    """Return every retained-track/sidecar path next to audio_path that actually exists."""
    candidates = (
        audio_path.parent / "system.wav",
        audio_path.parent / "mic.wav",
        audio_path.parent / "track_alignment.json",
    )
    return tuple(p for p in candidates if p.exists())


def _read_mic_start_offset(audio_path: Path) -> float:
    """Read mic_start_offset_seconds from track_alignment.json next to audio_path, or 0.0."""
    import json

    sidecar_path = audio_path.parent / "track_alignment.json"
    try:
        data = json.loads(sidecar_path.read_text())
        return float(data.get("mic_start_offset_seconds", 0.0))
    except (OSError, ValueError, TypeError):
        return 0.0


def _shift_result(result, offset: float):
    """Return a copy of result with every segment/word start/end shifted by offset seconds."""
    from dataclasses import replace

    shifted_segments = []
    for seg in result.segments:
        shifted_words = [replace(w, start=w.start + offset, end=w.end + offset) for w in seg.words]
        shifted_segments.append(
            replace(seg, start=seg.start + offset, end=seg.end + offset, words=shifted_words)
        )
    return replace(result, segments=shifted_segments)


def _tag_speaker(result, speaker_label: str):
    """Return a copy of result with every segment's speaker set to speaker_label."""
    from dataclasses import replace

    tagged_segments = [replace(seg, speaker=speaker_label) for seg in result.segments]
    return replace(result, segments=tagged_segments)


def _merge_dual_track_results(system_result, mic_result, mic_offset: float):
    """Merge a diarized system-track result with an owner-tagged mic-track result into one timeline."""
    from dataclasses import replace

    tagged_mic = _tag_speaker(_shift_result(mic_result, mic_offset), _OWNER_SPEAKER_LABEL)
    all_segments = sorted(
        [*system_result.segments, *tagged_mic.segments],
        key=lambda seg: seg.start,
    )
    duration = max(system_result.duration, mic_result.duration + mic_offset)
    return replace(system_result, segments=all_segments, duration=duration)


def _relabel_speakers_with_voiceprints(result, cluster_embeddings: dict[str, list[float]]):
    """Rename diarized cluster labels (e.g. SPEAKER_00) to enrolled names where matched."""
    from dataclasses import replace

    from ownscribe.speakers.base import VoiceprintDB
    from ownscribe.speakers.matching import assign_speaker_names

    if not isinstance(cluster_embeddings, dict) or not cluster_embeddings:
        return result

    db = VoiceprintDB.load()
    if not db.voiceprints:
        return result

    assignments = assign_speaker_names(cluster_embeddings, db)
    relabeled_segments = [
        replace(seg, speaker=assignments.get(seg.speaker, seg.speaker)) for seg in result.segments
    ]
    return replace(result, segments=relabeled_segments)


def _transcribe_and_identify(transcriber, audio_path: Path):
    """Transcribe a track and relabel any diarized clusters with enrolled speaker names."""
    result = transcriber.transcribe(audio_path)
    return _relabel_speakers_with_voiceprints(result, transcriber.last_speaker_embeddings)


def _transcribe_dual_track(transcriber, system_path: Path, mic_path: Path, mic_offset: float):
    """Transcribe system.wav (diarized+identified per config) and mic.wav (owner, never diarized), merged."""
    system_result = _transcribe_and_identify(transcriber, system_path)
    mic_result = transcriber.transcribe(mic_path, diarize=False)
    return _merge_dual_track_results(system_result, mic_result, mic_offset)


def _download_summarization_model(
    model_name: str,
    progress: PipelineProgress,
    step_key: str,
) -> Path:
    """Download the summarization GGUF model, feeding progress into the TUI."""
    from ownscribe.summarization.llama_cpp_summarizer import _ensure_model

    def _on_progress(event: DownloadProgressEvent) -> None:
        fraction = download_event_fraction(event)
        if fraction is not None:
            progress.update(step_key, fraction)
        formatted = format_download_progress(event, include_percent=fraction is None)
        if formatted:
            progress.set_detail(step_key, formatted)

    return _ensure_model(model_name, on_progress=_on_progress)


def _format_output(config: Config, transcript_result, summary_text: str | None = None) -> tuple[str, str | None]:
    """Format transcript and optional summary. Returns (transcript_str, summary_str)."""
    if config.output.format == "json":
        from ownscribe.output.json_output import format_transcript_json

        return format_transcript_json(transcript_result), summary_text
    else:
        from ownscribe.output.markdown import format_summary, format_transcript

        tx = format_transcript(transcript_result)
        sm = format_summary(summary_text) if summary_text else None
        return tx, sm


def _slugify(text: str, max_length: int = 50) -> str:
    """Convert text to a filesystem-safe slug."""
    slug = text.lower().strip()
    slug = re.sub(r"[^a-z0-9\s-]", "", slug)
    slug = re.sub(r"[\s]+", "-", slug)
    slug = re.sub(r"-+", "-", slug)
    slug = slug.strip("-")
    return slug[:max_length].rstrip("-")


def _generate_title_slug(summary: str, summarizer) -> str:
    """Generate a title slug from a summary. Returns empty string on failure."""
    try:
        title = summarizer.generate_title(summary)
        return _slugify(title)
    except Exception:
        logging.getLogger(__name__).warning("Could not generate title", exc_info=True)
        return ""


def run_pipeline(config: Config) -> None:
    """Run the full pipeline: record, transcribe, summarize, output."""
    out_dir = _get_output_dir(config)
    audio_dir = _get_output_audio_dir(config, out_dir)
    audio_path = audio_dir / "recording.wav"

    # 1. Record
    recorder = _create_recorder(config)

    from ownscribe.audio.coreaudio import CoreAudioRecorder

    can_mute = isinstance(recorder, CoreAudioRecorder) and config.audio.mic
    is_tty = sys.stdin.isatty()

    hints = []
    if can_mute and is_tty:
        hints.append("Press 'm' to mute/unmute mic.")
    silence_timeout = config.audio.silence_timeout
    if silence_timeout > 0:
        mins, secs = divmod(int(silence_timeout), 60)
        if mins > 0 and secs > 0:
            hints.append(f"Auto-stops after {mins}m {secs}s of silence.")
        elif mins > 0:
            hints.append(f"Auto-stops after {mins}m of silence.")
        else:
            hints.append(f"Auto-stops after {silence_timeout}s of silence.")
    hints.append("Press Ctrl+C to stop.")
    click.echo(f"Starting recording... {' '.join(hints)}\n")
    recorder.start(audio_path)

    start_time = time.time()
    stop_event = False

    def on_interrupt(sig, frame):
        nonlocal stop_event
        stop_event = True

    original_handler = signal.getsignal(signal.SIGINT)
    signal.signal(signal.SIGINT, on_interrupt)

    old_termios = None
    if can_mute and is_tty:
        old_termios = termios.tcgetattr(sys.stdin)
        tty.setcbreak(sys.stdin.fileno())

    warned_no_data = False
    try:
        while not stop_event and recorder.is_recording:
            elapsed = time.time() - start_time
            mins, secs = divmod(int(elapsed), 60)
            mute_indicator = "  [MIC MUTED]" if recorder.is_muted else ""
            click.echo(
                f"\r  Recording: {mins:02d}:{secs:02d}{mute_indicator}\033[K",
                nl=False,
            )
            if (
                not warned_no_data
                and elapsed >= 3
                and audio_path.exists()
                and audio_path.stat().st_size <= _WAV_HEADER_SIZE
            ):
                click.echo(
                    "\n\n  Warning: No audio data received yet.\n",
                    err=True,
                )
                warned_no_data = True
            if old_termios is not None:
                readable, _, _ = select.select([sys.stdin], [], [], 0.5)
                if readable:
                    ch = sys.stdin.read(1)
                    if ch in ("m", "M"):
                        recorder.toggle_mute()
                    elif ch == "\x03":
                        stop_event = True
            else:
                time.sleep(0.5)
    finally:
        if old_termios is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_termios)
        signal.signal(signal.SIGINT, original_handler)

    recorder.stop()
    if getattr(recorder, "silence_timed_out", False):
        click.echo("\n\nRecording auto-stopped after silence timeout.")
    else:
        click.echo("\n\nStopping recording...")

    if not audio_path.exists() or audio_path.stat().st_size <= _WAV_HEADER_SIZE:
        click.echo(
            "Error: No audio was captured. Make sure audio is playing on your system, "
            "or use --device to capture mic-only.",
            err=True,
        )
        raise SystemExit(1)

    click.echo(f"Audio saved to {audio_path}\n")

    # Check for silent audio before spending time on transcription
    # Skip if the recorder already reported a silence warning (CoreAudio helper)
    dual_tracks = _find_dual_tracks(audio_path)
    if dual_tracks:
        _check_dual_track_silence(*dual_tracks)
    elif not getattr(recorder, "silence_warning", False):
        _check_audio_silence(audio_path)

    # 2. Transcribe
    _do_transcribe_and_summarize(config, audio_path, out_dir)


def run_transcribe(config: Config, audio_file: str) -> None:
    """Transcribe an audio file and save the transcript alongside the input."""
    audio_path = Path(audio_file).resolve()
    _check_audio_silence(audio_path)
    out_dir = audio_path.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    _do_transcribe_and_summarize(config, audio_path, out_dir, summarize=False)


def run_warmup(config: Config) -> None:
    """Prefetch transcription/diarization models without processing audio."""
    diar_enabled = config.diarization.enabled and bool(config.diarization.hf_token)
    hf_token_warning = config.diarization.enabled and not config.diarization.hf_token
    local_sum = config.summarization.enabled and config.summarization.backend == "local"

    with PipelineProgress(
        diarize=False,
        summarize=False,
        transcribe=False,
        include_prepare=True,
        download_summarizer=local_sum,
    ) as progress:
        try:
            transcriber = _create_transcriber(config, progress=progress)
        except ImportError:
            click.echo(
                "Error: WhisperX is not installed. Install with:\n  uv pip install 'ownscribe[transcription]'",
                err=True,
            )
            raise SystemExit(1) from None

        transcriber.prepare_models(language=config.transcription.language or None)

        if local_sum:
            progress.begin("downloading_model")
            try:
                _download_summarization_model(config.summarization.model, progress, "downloading_model")
                progress.complete("downloading_model")
            except Exception as exc:
                progress.fail("downloading_model")
                click.echo(f"Error: {exc}", err=True)
                raise SystemExit(1) from None

    click.echo(f"Whisper model ready: {config.transcription.model}")
    if config.transcription.language:
        click.echo(f"Alignment model ready: {config.transcription.language}")
    else:
        click.echo("Alignment model not preloaded (language auto-detect).")

    if diar_enabled:
        click.echo("Diarization pipeline ready.")
    elif hf_token_warning:
        click.echo(
            "Warning: Diarization enabled but no HF token configured. Skipping diarization warmup.",
            err=True,
        )

    if local_sum:
        click.echo(f"Summarization model ready: {config.summarization.model}")


def run_summarize(config: Config, transcript_file: str) -> None:
    """Summarize a transcript file and save the summary alongside the input."""
    transcript_path = Path(transcript_file).resolve()
    transcript_text = transcript_path.read_text()

    try:
        summarizer = create_summarizer(config)
    except ImportError as exc:
        click.echo(f"Error: {exc}", err=True)
        raise SystemExit(1) from None
    if not summarizer.is_available():
        if config.summarization.backend == "local":
            click.echo(
                f"Error: Local summarization model '{config.summarization.model}' is not available.",
                err=True,
            )
        else:
            click.echo(
                f"Error: {config.summarization.backend} is not reachable at {config.summarization.host}. "
                "Is the server running?",
                err=True,
            )
        raise SystemExit(1)

    from ownscribe.output.markdown import format_summary

    out_dir = transcript_path.parent
    local_sum = config.summarization.backend == "local"

    try:
        with PipelineProgress(
            transcribe=False,
            diarize=False,
            summarize=True,
            download_summarizer=local_sum,
        ) as progress:
            progress.begin("summarizing")
            if local_sum:
                progress.begin("downloading_model")
                try:
                    _download_summarization_model(
                        config.summarization.model,
                        progress,
                        "downloading_model",
                    )
                    progress.complete("downloading_model")
                except Exception:
                    progress.fail("downloading_model")
                    click.echo(
                        f"Error: Failed to download summarization model '{config.summarization.model}'.\n"
                        "Check your internet connection and try again.",
                        err=True,
                    )
                    raise SystemExit(1) from None
            summary = summarizer.summarize(transcript_text)
            title_slug = _generate_title_slug(summary, summarizer)
            progress.complete("summarizing")
    finally:
        summarizer.close()

    summary_md = format_summary(summary)
    summary_path = out_dir / "summary.md"
    summary_path.write_text(summary_md)

    if title_slug:
        out_dir, old_out_dir = _rename_output_dir(out_dir, title_slug), out_dir
        # If a separate audio_dir is configured, rename like out_dir, but only
        # if audio_dir actually exists -- run_summarize can run on a transcript
        # regardless of a recording -- and if out_dir was renamed successfully.
        # Require the transcript to live in the output tree so summarizing a
        # transcript elsewhere cannot rename an unrelated audio directory whose
        # name happens to match.
        if (
            config.output.uses_separate_audio_dir
            and old_out_dir.parent == config.output.resolved_dir
        ):
            audio_dir = config.output.resolved_audio_dir / old_out_dir.name
            if audio_dir.is_dir() and out_dir != old_out_dir:
                _rename_output_dir(audio_dir, title_slug)

    summary_path = out_dir / "summary.md"

    click.echo(f"\n{summary_md}")
    click.echo(f"Summary saved to {summary_path}")


def _do_transcribe_and_summarize(
    config: Config,
    audio_path: Path,
    out_dir: Path,
    summarize: bool = True,
) -> None:
    """Shared logic for transcribe + optional summarize."""
    diar_enabled = config.diarization.enabled and bool(config.diarization.hf_token)
    sum_enabled = summarize and config.summarization.enabled
    correction_enabled = config.correction.enabled

    summary = None
    summary_str = None
    title_slug = ""
    sum_unavailable = False
    sum_failed = False
    correction_unavailable = False
    correction_failed = False

    local_sum = sum_enabled and config.summarization.backend == "local"
    needs_llm = sum_enabled or correction_enabled

    with PipelineProgress(
        diarize=diar_enabled,
        summarize=sum_enabled,
        download_summarizer=local_sum,
    ) as progress:
        try:
            transcriber = _create_transcriber(config, progress=progress)
        except ImportError:
            click.echo(
                "Error: WhisperX is not installed. Install with:\n  uv pip install 'ownscribe[transcription]'",
                err=True,
            )
            raise SystemExit(1) from None

        dual_tracks = _find_dual_tracks(audio_path)
        if dual_tracks:
            system_path, mic_path = dual_tracks
            mic_offset = _read_mic_start_offset(audio_path)
            result = _transcribe_dual_track(transcriber, system_path, mic_path, mic_offset)
        else:
            result = _transcribe_and_identify(transcriber, audio_path)

        summarizer = None
        if needs_llm:
            try:
                summarizer = create_summarizer(config)
            except ImportError as exc:
                click.echo(f"Error: {exc}", err=True)
                raise SystemExit(1) from None

        try:
            if correction_enabled:
                if summarizer is not None and summarizer.is_available():
                    try:
                        result = correct_transcript(
                            summarizer, result, config.correction.max_length_delta_ratio
                        )
                    except Exception:
                        correction_failed = True
                else:
                    correction_unavailable = True

            # Save transcript — silent, no echo
            transcript_str, _ = _format_output(config, result)
            ext = "json" if config.output.format == "json" else "md"
            transcript_path = out_dir / f"transcript.{ext}"
            transcript_path.write_text(transcript_str)

            if sum_enabled and summarizer is not None:
                if not summarizer.is_available():
                    sum_unavailable = True
                else:
                    try:
                        progress.begin("summarizing")
                        if local_sum:
                            progress.begin("downloading_model")
                            _download_summarization_model(
                                config.summarization.model,
                                progress,
                                "downloading_model",
                            )
                            progress.complete("downloading_model")
                        summary = summarizer.summarize(result.full_text)
                        _, summary_str = _format_output(config, result, summary)
                        summary_path = out_dir / f"summary.{ext}"
                        summary_path.write_text(summary_str or summary)
                        title_slug = _generate_title_slug(summary, summarizer)
                        progress.complete("summarizing")
                    except Exception:
                        progress.fail("summarizing")
                        sum_failed = True
        finally:
            if summarizer is not None:
                summarizer.close()

    # --- All user-facing output after TUI exits ---
    click.echo(f"Transcript saved to {transcript_path}")

    if correction_unavailable:
        click.echo(
            "\nWarning: Correction pass enabled but the summarization backend is not reachable. "
            "Skipping correction; transcript is uncorrected.",
            err=True,
        )
    elif correction_failed:
        click.echo(
            "\nWarning: Correction pass failed. Transcript is saved uncorrected.",
            err=True,
        )

    if sum_unavailable:
        if config.summarization.backend == "local":
            click.echo(
                f"\nWarning: Local summarization model '{config.summarization.model}' is not available. "
                "Skipping summarization.",
                err=True,
            )
        else:
            click.echo(
                f"\nWarning: {config.summarization.backend} is not reachable "
                f"at {config.summarization.host}. "
                "Skipping summarization. Is the server running?",
                err=True,
            )
    elif sum_failed:
        click.echo(
            f"\nWarning: Summarization failed. "
            f"Transcript is saved at {transcript_path}\n"
            f"Resume with: ownscribe resume {out_dir}",
            err=True,
        )

    if summary is not None:
        click.echo(f"Summary saved to {out_dir / f'summary.{ext}'}")
        click.echo(f"\n{summary_str or summary}")
        if title_slug:
            out_dir, old_out_dir = _rename_output_dir(out_dir, title_slug), out_dir
            audio_dir = audio_path.parent
            # If the audio lives in its own directory (separate audio_dir
            # configured and the recording not colocated with the text output,
            # as when resuming a directory recorded before audio_dir was set),
            # rename it like out_dir, but only if out_dir was renamed
            # successfully.
            if config.output.uses_separate_audio_dir and audio_dir != old_out_dir:
                if out_dir != old_out_dir:
                    audio_dir = _rename_output_dir(audio_dir, title_slug)
            # Otherwise the audio follows out_dir: adjust audio_dir and
            # audio_path according to the new name of out_dir.
            else:
                audio_dir = out_dir
            audio_path = audio_dir / audio_path.name
    elif not summarize:
        click.echo(f"\n{transcript_str}")

    # Delete recording if configured — use the (possibly renamed) audio_path
    if not config.output.keep_recording and audio_path.exists():
        for retained_path in (audio_path, *_dual_track_paths(audio_path)):
            retained_path.unlink(missing_ok=True)
        # Also remove the parent directory if it is now empty, which is expected
        # when a separate audio_dir is configured.
        if not any(audio_path.parent.iterdir()):
            audio_path.parent.rmdir()
        click.echo(f"Recording deleted (keep_recording=false): {audio_path}")


_AUDIO_EXTENSIONS = {".wav", ".mp3", ".m4a", ".flac", ".ogg", ".webm"}
# Video containers whose audio track ffmpeg/WhisperX can decode (e.g. meeting recordings).
_VIDEO_EXTENSIONS = {".mp4", ".m4v", ".mov", ".mkv"}
_MEDIA_EXTENSIONS = _AUDIO_EXTENSIONS | _VIDEO_EXTENSIONS


def _find_audio(directory: Path) -> Path | None:
    """Find an audio or video file in directory, preferring 'recording.wav'."""
    recording = directory / "recording.wav"
    if recording.exists():
        return recording
    for f in directory.iterdir():
        if f.is_file() and f.suffix.lower() in _MEDIA_EXTENSIONS:
            return f
    return None


def _find_transcript(directory: Path) -> Path | None:
    """Find a transcript file in directory."""
    for ext in ("md", "json"):
        path = directory / f"transcript.{ext}"
        if path.exists():
            return path
    return None


def _find_summary(directory: Path) -> Path | None:
    """Find a summary file in directory."""
    for ext in ("md", "json"):
        path = directory / f"summary.{ext}"
        if path.exists():
            return path
    return None


def run_resume(config: Config, directory: str) -> None:
    """Resume a partially-completed pipeline in the given directory."""
    dir_path = Path(directory).resolve()
    if not dir_path.is_dir():
        click.echo(f"Error: {dir_path} is not a directory.", err=True)
        raise SystemExit(1)

    audio = _resolve_retained_audio(config, dir_path)
    transcript = _find_transcript(dir_path)
    summary = _find_summary(dir_path)

    if transcript and summary:
        click.echo("Nothing to resume — transcript and summary already exist.")
        return

    if not audio and not transcript:
        click.echo(
            f"Error: No audio or transcript found in {dir_path}.\nA recording or transcript is needed to resume.",
            err=True,
        )
        raise SystemExit(1)

    if transcript:
        # Have transcript, missing summary — summarize only
        click.echo(f"Found transcript: {transcript}")
        click.echo("Resuming: summarize only.\n")
        run_summarize(config, str(transcript))
    else:
        # Have audio, missing transcript (and summary) — full transcribe + summarize
        click.echo(f"Found audio: {audio}")
        click.echo("Resuming: transcribe + summarize.\n")
        _do_transcribe_and_summarize(config, audio, dir_path)


def run_enroll(config: Config, name: str, audio_file: str) -> None:
    """Enroll a speaker's voiceprint from a short reference clip."""
    from ownscribe.speakers.base import VoiceprintDB
    from ownscribe.speakers.embedding import SpeakerEmbedder

    if not config.diarization.hf_token:
        click.echo(
            "Error: Enrollment requires a HuggingFace token (same one diarization uses).\n"
            "Set HF_TOKEN env var or hf_token in config.",
            err=True,
        )
        raise SystemExit(1)

    audio_path = Path(audio_file).resolve()
    embedder = SpeakerEmbedder(config.diarization.hf_token)

    try:
        embedding = embedder.embed_file(audio_path)
    except Exception as exc:
        click.echo(f"Error: Failed to compute voiceprint: {exc}", err=True)
        raise SystemExit(1) from None

    db = VoiceprintDB.load()
    db.upsert(name, embedding)
    db.save()

    click.echo(f"Enrolled '{name}' from {audio_path}")


def run_unenroll(name: str) -> None:
    """Remove an enrolled speaker's voiceprint."""
    from ownscribe.speakers.base import VoiceprintDB

    db = VoiceprintDB.load()
    if db.remove(name):
        db.save()
        click.echo(f"Removed voiceprint for '{name}'")
    else:
        click.echo(f"No enrolled voiceprint found for '{name}'", err=True)
        raise SystemExit(1)


def run_list_enrolled() -> None:
    """List all enrolled speaker names."""
    from ownscribe.speakers.base import VoiceprintDB

    db = VoiceprintDB.load()
    if not db.voiceprints:
        click.echo("No enrolled speakers.")
        return
    for vp in db.voiceprints:
        click.echo(vp.name)


def run_watch(config: Config, sustained_seconds: float) -> None:
    """Watch for sustained mic+output activity together, then record+transcribe+summarize."""
    import subprocess

    from ownscribe.audio.coreaudio import _find_binary

    binary = _find_binary()
    if binary is None:
        click.echo(
            "Error: ownscribe-audio binary not found. Run: bash swift/build.sh",
            err=True,
        )
        raise SystemExit(1)

    click.echo(f"Watching for a meeting to start (mic+output active for {sustained_seconds:.0f}s)...")

    process = subprocess.Popen(
        [str(binary), "watch-activity", "--sustained-seconds", str(sustained_seconds)],
        stdout=subprocess.PIPE,
        text=True,
    )
    detected = False
    try:
        for line in process.stdout:
            if line.strip() == "[MEETING_DETECTED]":
                detected = True
                break
        process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.terminate()

    if not detected:
        click.echo(
            "Error: watch-activity exited without detecting a meeting.",
            err=True,
        )
        raise SystemExit(1)

    click.echo("Meeting detected — starting recording.\n")
    run_pipeline(config)


def _resolve_retained_audio(config: Config, directory: Path) -> Path | None:
    """Find retained audio for a meeting directory, checking a separate audio_dir if configured."""
    audio = _find_audio(directory)
    if audio is None and config.output.uses_separate_audio_dir:
        candidate = config.output.resolved_audio_dir / directory.name
        if candidate != directory and candidate.is_dir():
            audio = _find_audio(candidate)
    return audio


def run_reprocess(config: Config, directory: str) -> None:
    """Force a full re-transcribe+summarize from retained audio, even if output already exists."""
    dir_path = Path(directory).resolve()
    if not dir_path.is_dir():
        click.echo(f"Error: {dir_path} is not a directory.", err=True)
        raise SystemExit(1)

    audio = _resolve_retained_audio(config, dir_path)

    if audio is None:
        click.echo(
            f"Error: No retained audio found in {dir_path}.\n"
            "Reprocessing requires the original recording -- check `keep_recording` "
            "was true when this meeting was recorded.",
            err=True,
        )
        raise SystemExit(1)

    for existing in (_find_transcript(dir_path), _find_summary(dir_path)):
        if existing is not None:
            existing.unlink()

    click.echo(f"Reprocessing from: {audio}\n")
    _do_transcribe_and_summarize(config, audio, dir_path)


def run_purge(config: Config, older_than_days: int | None, purge_all: bool, dry_run: bool) -> None:
    """Delete retained audio according to the retention policy (keep-N-days, forever, or --all)."""
    effective_days = config.output.retention_days if older_than_days is None else older_than_days

    if not purge_all and effective_days <= 0:
        click.echo(
            "Retention policy is 'keep forever' (retention_days=0) and --all was not given.\n"
            "Nothing to purge. Pass --all to remove all retained audio regardless of age, "
            "or set retention_days / --older-than to a positive number of days.",
        )
        return

    base = config.output.resolved_dir
    if not base.is_dir():
        click.echo("No retained audio is eligible for purging.")
        return

    eligible: list[tuple[Path, Path]] = []
    for directory in sorted(d for d in base.iterdir() if d.is_dir()):
        audio = _resolve_retained_audio(config, directory)
        if audio is None:
            continue
        if purge_all:
            eligible.append((directory, audio))
            continue
        age_days = (time.time() - audio.stat().st_mtime) / 86400
        if age_days >= effective_days:
            eligible.append((directory, audio))

    if not eligible:
        click.echo("No retained audio is eligible for purging.")
        return

    for directory, audio in eligible:
        if dry_run:
            click.echo(f"Would remove: {directory}")
            continue
        for retained_path in (audio, *_dual_track_paths(audio)):
            retained_path.unlink(missing_ok=True)
        click.echo(f"Removed retained audio: {directory}")

    if dry_run:
        click.echo(f"\n{len(eligible)} meeting(s) would be purged (dry run — nothing deleted).")
    else:
        click.echo(f"\nPurged retained audio from {len(eligible)} meeting(s).")
