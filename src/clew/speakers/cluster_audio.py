"""Cut a clean reference audio clip for one diarized speaker cluster.

BUILD NEXT #1 tranche 2, block A1 (see /tmp/atelier/plan-build-next-1-t2.md): selects
"long mid-run monologue" spans for a cluster -- never near a recording edge, never a
short turn -- and cuts them from the meeting's retained dual-track audio into a
temporary clip a SpeakerEmbedder can embed. This is the audio source A3's
`clew enroll-cluster` falls back to when no persisted cluster embedding exists yet.

Deliberately does NOT exclude pyannote overlap zones: Segment carries no overlap data
today, see clew.speakers.enrollment_suggest's module docstring, point 1 -- that is
BUILD NEXT #5, revisit once overlap regions are threaded into TranscriptResult. Only
recording-boundary exclusion (first/last few percent, mirroring
enrollment_suggest._boundary_weight's rule) is applied here.
"""

from __future__ import annotations

import json
from pathlib import Path

from clew.pipeline import _OWNER_SPEAKER_LABEL
from clew.transcription.models import TranscriptResult

_SYSTEM_TRACK_FILENAME = "system.wav"
_MIC_TRACK_FILENAME = "mic.wav"
_ALIGNMENT_FILENAME = "track_alignment.json"

_DEFAULT_MAX_TOTAL_SECONDS = 30.0
_DEFAULT_EDGE_TRIM_SECONDS = 1.0
_DEFAULT_MIN_TURN_SECONDS = 3.0
_DEFAULT_BOUNDARY_FRACTION = 0.05

_WHISPER_MAX_SEGMENT_SECONDS = 30.0


def _effective_end(segments: list, index: int, duration: float) -> float:
    """A segment's end. A real, non-degenerate end (JSON-shape, end > start)
    is trusted as-is and never extended -- only bounded by transcript.duration
    when that duration is actually known (duration > 0), so it can never claim
    to run past the recording. Reconstruction only ever applies to a degenerate
    segment (markdown-shape transcripts have end == start on every segment):
    the next segment's start (any speaker) is the reconstruction target,
    capped at start + _WHISPER_MAX_SEGMENT_SECONDS (a Whisper segment never
    decodes past that window) so a silent gap or recording tail can never
    inflate a turn far enough to escape the boundary-exclusion rule.
    """
    seg = segments[index]
    if seg.end > seg.start:
        return min(seg.end, duration) if duration > 0 else seg.end
    next_start = segments[index + 1].start if index + 1 < len(segments) else duration
    return min(next_start, seg.start + _WHISPER_MAX_SEGMENT_SECONDS)


def cluster_turns(transcript: TranscriptResult, cluster: str) -> list[tuple[float, float]]:
    """Merge consecutive segments belonging to `cluster` into turns -- a run
    ends when interrupted by any other speaker's segment, OR when the gap to
    the next same-speaker segment exceeds _WHISPER_MAX_SEGMENT_SECONDS, so two
    real utterances of the same speaker far apart with nothing transcribed in
    between (review finding R2) can never merge into one inflated turn -- each
    starts its own run, capped the same way _effective_end caps a single one."""
    segments = transcript.segments
    turns: list[tuple[float, float]] = []
    run_start: float | None = None
    run_end = 0.0
    for i, seg in enumerate(segments):
        if seg.speaker == cluster:
            if run_start is not None and seg.start - run_end > _WHISPER_MAX_SEGMENT_SECONDS:
                turns.append((run_start, run_end))
                run_start = None
            if run_start is None:
                run_start = seg.start
            run_end = _effective_end(segments, i, transcript.duration)
        elif run_start is not None:
            turns.append((run_start, run_end))
            run_start = None
    if run_start is not None:
        turns.append((run_start, run_end))
    return turns


def select_cluster_spans(
    transcript: TranscriptResult,
    cluster: str,
    *,
    max_total_seconds: float = _DEFAULT_MAX_TOTAL_SECONDS,
    edge_trim_seconds: float = _DEFAULT_EDGE_TRIM_SECONDS,
    min_turn_seconds: float = _DEFAULT_MIN_TURN_SECONDS,
    boundary_fraction: float = _DEFAULT_BOUNDARY_FRACTION,
) -> list[tuple[float, float]]:
    """The "long mid-run monologue" selection: drop turns whose midpoint falls in
    the first/last boundary_fraction of the recording, trim edge_trim_seconds off
    both ends of what remains, drop anything too short after trimming, then take
    the longest surviving turns first until max_total_seconds is spent (the last
    one taken is truncated to fit). Returned in chronological order, not selection
    order. Returns [] when nothing qualifies."""
    duration = transcript.duration
    candidates: list[tuple[float, float]] = []
    for start, end in cluster_turns(transcript, cluster):
        if duration > 0:
            midpoint = (start + end) / 2
            if midpoint <= duration * boundary_fraction or midpoint >= duration * (1 - boundary_fraction):
                continue
        trimmed_start = start + edge_trim_seconds
        trimmed_end = end - edge_trim_seconds
        if trimmed_end - trimmed_start < min_turn_seconds:
            continue
        candidates.append((trimmed_start, trimmed_end))

    candidates.sort(key=lambda span: span[1] - span[0], reverse=True)

    selected: list[tuple[float, float]] = []
    total = 0.0
    for start, end in candidates:
        remaining = max_total_seconds - total
        if remaining <= 0:
            break
        span_length = end - start
        if span_length > remaining:
            end = start + remaining
            span_length = remaining
        selected.append((start, end))
        total += span_length

    selected.sort(key=lambda span: span[0])
    return selected


def _read_mic_offset(alignment_path: Path | None) -> float:
    if alignment_path is None or not alignment_path.exists():
        return 0.0
    try:
        data = json.loads(alignment_path.read_text())
        return float(data.get("mic_start_offset_seconds", 0.0))
    except (OSError, ValueError, TypeError):
        return 0.0


def track_clock_shift(alignment_path: Path | None, track: str) -> float:
    """Seconds to subtract from a merged-timeline time to get `track`'s own local
    time. Mirrors pipeline._merge_dual_track_results: a non-negative mic_offset
    shifted the MIC track forward (system stays put); a negative one shifted the
    SYSTEM track forward by its absolute value (mic stays put). Missing/unreadable
    alignment file = shift 0 for both tracks."""
    mic_offset = _read_mic_offset(alignment_path)
    if track == _SYSTEM_TRACK_FILENAME:
        return max(0.0, -mic_offset)
    return max(0.0, mic_offset)


def source_track_for(cluster: str) -> str:
    """The retained-audio filename that actually carries `cluster`'s voice."""
    return _MIC_TRACK_FILENAME if cluster == _OWNER_SPEAKER_LABEL else _SYSTEM_TRACK_FILENAME


def cut_clip(audio_path: Path, spans: list[tuple[float, float]], out_path: Path) -> float:
    """Read only the frames covered by `spans` from audio_path (float32 IEEE WAV,
    hence soundfile rather than stdlib wave), concatenate them in order, and write
    a WAV at the source sample rate to out_path. A span reaching past the end of
    the file is clamped to what's actually there. Returns the written clip's
    duration in seconds."""
    import numpy as np
    import soundfile as sf

    info = sf.info(str(audio_path))
    sample_rate = info.samplerate
    total_frames = info.frames

    chunks = []
    with sf.SoundFile(str(audio_path)) as f:
        for start, end in spans:
            start_frame = max(0, int(start * sample_rate))
            end_frame = min(total_frames, int(end * sample_rate))
            if end_frame <= start_frame:
                continue
            f.seek(start_frame)
            chunks.append(f.read(end_frame - start_frame, dtype="float32"))

    clip = np.concatenate(chunks) if chunks else np.zeros((0,), dtype="float32")
    sf.write(str(out_path), clip, sample_rate, subtype="FLOAT")
    return float(len(clip)) / sample_rate if sample_rate else 0.0


def write_cluster_clip(
    meeting_dir: Path,
    transcript: TranscriptResult,
    cluster: str,
    out_path: Path,
    **selection_kwargs,
) -> float:
    """Compose the pipeline above: resolve which retained track carries `cluster`,
    select its long mid-run spans, reproject them from the merged transcript
    timeline onto that track's own clock, and cut the clip."""
    track_name = source_track_for(cluster)
    audio_path = meeting_dir / track_name
    if not audio_path.exists():
        raise FileNotFoundError(f"{track_name} not found in {meeting_dir} (retained audio may have been purged)")

    spans = select_cluster_spans(transcript, cluster, **selection_kwargs)
    if not spans:
        raise ValueError(f"No qualifying long mid-run turn found for cluster {cluster}")

    shift = track_clock_shift(meeting_dir / _ALIGNMENT_FILENAME, track_name)
    track_spans = [(max(0.0, start - shift), max(0.0, end - shift)) for start, end in spans]

    return cut_clip(audio_path, track_spans, out_path)
