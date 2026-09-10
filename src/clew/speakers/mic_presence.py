"""Mic-track voice presence: windowed RMS voiced-span selection, an embedding of
the mic track's own voice, and a two-hop cosine match against diarized clusters
and the enrolled voiceprint store.

BUILD NEXT #1 tranche 2, block A4 (see /tmp/atelier/plan-build-next-1-t2.md): this
is the real cosine mic<->cluster identity signal enrollment_suggest.py's tranche-1
module docstring named as future work. resolve_mic_presence is deliberately a
two-hop gate: hop 1 (which diarized cluster is this mic voice) must clear
`threshold` before hop 2 (which enrolled name matches that same mic voice) is even
attempted -- a NAME is never resolved off a single jump.
"""

from __future__ import annotations

import json
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path

from clew.pipeline import _MIC_SEGMENT_SILENCE_THRESHOLD, SPEAKER_EMBEDDINGS_FILENAME
from clew.speakers.base import DEFAULT_MATCH_THRESHOLD, VoiceprintDB
from clew.speakers.cluster_audio import cut_clip, write_cluster_clip
from clew.speakers.matching import cosine_similarity, match_speaker

_DEFAULT_WINDOW_SECONDS = 0.5
_DEFAULT_MAX_TOTAL_SECONDS = 30.0
_DEFAULT_MIN_VOICED_SECONDS = 2.0

_SPEAKER_LABEL_RE = re.compile(r"^SPEAKER_\d+$")


def voiced_spans(
    mic_wav: Path,
    *,
    window_seconds: float = _DEFAULT_WINDOW_SECONDS,
    rms_threshold: float = _MIC_SEGMENT_SILENCE_THRESHOLD,
    max_total_seconds: float = _DEFAULT_MAX_TOTAL_SECONDS,
) -> list[tuple[float, float]]:
    """Windowed RMS over mic_wav: keep windows at or above rms_threshold, merge
    adjacent ones into spans, take the longest spans first up to
    max_total_seconds (truncating the last one to fit), return chronological."""
    import numpy as np
    import soundfile as sf

    info = sf.info(str(mic_wav))
    sample_rate = info.samplerate
    total_frames = info.frames
    window_frames = max(1, round(window_seconds * sample_rate))

    voiced_windows: list[tuple[int, int]] = []
    with sf.SoundFile(str(mic_wav)) as f:
        frame = 0
        while frame < total_frames:
            n = min(window_frames, total_frames - frame)
            data = f.read(n, dtype="float32")
            if data.size == 0:
                break
            if data.ndim > 1:
                data = data.mean(axis=1)
            rms = float(np.sqrt(np.mean(np.square(data))))
            if rms >= rms_threshold:
                voiced_windows.append((frame, frame + n))
            frame += n

    merged: list[tuple[int, int]] = []
    for start_frame, end_frame in voiced_windows:
        if merged and merged[-1][1] == start_frame:
            merged[-1] = (merged[-1][0], end_frame)
        else:
            merged.append((start_frame, end_frame))

    candidates = [(s / sample_rate, e / sample_rate) for s, e in merged]
    candidates.sort(key=lambda span: span[1] - span[0], reverse=True)

    selected: list[tuple[float, float]] = []
    total = 0.0
    for start, end in candidates:
        remaining = max_total_seconds - total
        if remaining <= 0:
            break
        length = end - start
        if length > remaining:
            end = start + remaining
            length = remaining
        selected.append((start, end))
        total += length

    selected.sort(key=lambda span: span[0])
    return selected


def mic_embedding(
    mic_wav: Path, embedder, *, min_voiced_seconds: float = _DEFAULT_MIN_VOICED_SECONDS
) -> list[float] | None:
    """None when the mic track's total voiced time is below min_voiced_seconds --
    a muted or near-silent mic yields None, never a fabricated vector. Otherwise
    cuts the voiced spans into a temporary clip and embeds it."""
    spans = voiced_spans(mic_wav)
    total = sum(end - start for start, end in spans)
    if total < min_voiced_seconds:
        return None

    with tempfile.TemporaryDirectory() as tmp_dir:
        clip_path = Path(tmp_dir) / "mic_clip.wav"
        cut_clip(mic_wav, spans, clip_path)
        return embedder.embed_file(clip_path)


MIC_PRESENCE_STATUS_MATCHED = "matched"
MIC_PRESENCE_STATUS_BORDERLINE = "borderline"
MIC_PRESENCE_STATUS_BELOW = "below"

_DEFAULT_BORDERLINE_MARGIN = 0.05


@dataclass(frozen=True)
class MicPresence:
    """status is one of "matched" (score >= threshold + margin: cluster set,
    name resolved via hop 2), "borderline" (within the margin band around
    threshold: cluster set to the argmax for display, name always None -- see
    resolve_mic_presence's calibration note), or "below" (score < threshold -
    margin, or no cluster embeddings at all: cluster and name both None).
    score is always the best hop-1 cosine value found, even below threshold --
    reported for transparency, never hidden."""

    cluster: str | None
    name: str | None
    score: float | None
    status: str
    start: float
    end: float


def resolve_mic_presence(
    mic_emb: list[float],
    cluster_embeddings: dict[str, list[float]],
    db: VoiceprintDB,
    *,
    threshold: float = DEFAULT_MATCH_THRESHOLD,
    margin: float = _DEFAULT_BORDERLINE_MARGIN,
    start: float,
    end: float,
) -> MicPresence:
    """Two-hop match, now three-banded around threshold instead of a single
    cliff: hop 1 picks the best-cosine diarized cluster for mic_emb (score
    always reported); hop 2 resolves a voiceprint-store name ONLY when status
    is "matched" -- a name is never resolved from hop 2 alone, and never at
    all in the borderline band.

    Margin calibration (N=1, 2026-08-03/09-10 real data, see
    /tmp/atelier/plan-build-next-1-t2.md "Amendement du schema"): the SAME
    voice's embedding moved 0.017 between a raw and a silence-gated clip of
    itself, and the worst cross-speaker pair in the 2026-08-03 matrix sat
    only 0.013 below the match threshold. A 0.05 margin comfortably covers
    both observed sources of noise -- revisit as more real data accumulates.
    """
    if not cluster_embeddings:
        return MicPresence(cluster=None, name=None, score=None, status=MIC_PRESENCE_STATUS_BELOW, start=start, end=end)

    best_cluster: str | None = None
    best_score: float | None = None
    for cluster_label, embedding in cluster_embeddings.items():
        score = cosine_similarity(mic_emb, embedding)
        if best_score is None or score > best_score:
            best_score = score
            best_cluster = cluster_label

    if best_score >= threshold + margin:
        status = MIC_PRESENCE_STATUS_MATCHED
    elif best_score >= threshold - margin:
        status = MIC_PRESENCE_STATUS_BORDERLINE
    else:
        status = MIC_PRESENCE_STATUS_BELOW

    cluster = best_cluster if status != MIC_PRESENCE_STATUS_BELOW else None

    name = None
    if status == MIC_PRESENCE_STATUS_MATCHED:
        name = match_speaker(mic_emb, db, threshold=threshold)

    return MicPresence(cluster=cluster, name=name, score=best_score, status=status, start=start, end=end)


def cluster_embeddings_for(meeting_dir: Path, transcript, embedder_factory) -> dict[str, list[float]]:
    """speaker_embeddings.json's "clusters" when that file already exists for
    this meeting; otherwise embed each SPEAKER_NN cluster's own long mid-run clip
    (clew.speakers.cluster_audio, block A1), skipping any cluster with no
    qualifying span or missing retained audio rather than raising. {} when
    neither path yields anything. The embedder is constructed at most once, and
    only when actually needed."""
    persisted_path = meeting_dir / SPEAKER_EMBEDDINGS_FILENAME
    if persisted_path.exists():
        try:
            data = json.loads(persisted_path.read_text())
            return data.get("clusters", {})
        except (OSError, ValueError):
            pass

    labels = sorted(
        {seg.speaker for seg in transcript.segments if seg.speaker and _SPEAKER_LABEL_RE.match(seg.speaker)}
    )
    if not labels:
        return {}

    embedder = embedder_factory()
    embeddings: dict[str, list[float]] = {}
    for label in labels:
        with tempfile.TemporaryDirectory() as tmp_dir:
            clip_path = Path(tmp_dir) / "clip.wav"
            try:
                write_cluster_clip(meeting_dir, transcript, label, clip_path)
            except (FileNotFoundError, ValueError):
                continue
            embeddings[label] = embedder.embed_file(clip_path)
    return embeddings
