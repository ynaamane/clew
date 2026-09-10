"""Build and persist enrollment_suggestions.json -- the frozen report `clew
suggest-enrollment --write` leaves next to a meeting for the app to read.

BUILD NEXT #1 tranche 2, block A5 (see /tmp/atelier/plan-build-next-1-t2.md,
section "Schema fige"). The schema is frozen: field names here must match that
section exactly.
"""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from pathlib import Path

from clew.pipeline import _OWNER_SPEAKER_LABEL, SPEAKER_EMBEDDINGS_FILENAME
from clew.speakers.cluster_audio import cluster_turns, select_cluster_spans, source_track_for
from clew.speakers.mic_presence import MicPresence

ENROLLMENT_REPORT_FILENAME = "enrollment_suggestions.json"

_DEFAULT_MIN_ENROLLABLE_SECONDS = 10.0
_SPEAKER_LABEL_RE = re.compile(r"^SPEAKER_\d+$")


def _load_persisted_clusters(meeting_dir: Path) -> dict:
    persisted_path = meeting_dir / SPEAKER_EMBEDDINGS_FILENAME
    if not persisted_path.exists():
        return {}
    try:
        data = json.loads(persisted_path.read_text())
        return data.get("clusters", {})
    except (OSError, ValueError):
        return {}


def _report_labels(transcript) -> list[str]:
    """SPEAKER_NN labels (never an already-resolved name -- the regex only
    matches unresolved diarization labels), plus Owner when it actually
    appears in the transcript."""
    labels = sorted(
        {seg.speaker for seg in transcript.segments if seg.speaker and _SPEAKER_LABEL_RE.match(seg.speaker)}
    )
    if any(seg.speaker == _OWNER_SPEAKER_LABEL for seg in transcript.segments):
        labels.append(_OWNER_SPEAKER_LABEL)
    return labels


def _cluster_report_entry(
    transcript, meeting_dir: Path, label: str, persisted_clusters: dict, min_enrollable_seconds: float
) -> dict:
    turns = cluster_turns(transcript, label)
    speech_seconds = sum(end - start for start, end in turns)
    has_persisted = label in persisted_clusters
    audio_present = (meeting_dir / source_track_for(label)).exists()

    if not audio_present and not has_persisted:
        enrollable, reason = False, "audio_purged"
    else:
        total_selectable = sum(end - start for start, end in select_cluster_spans(transcript, label))
        if total_selectable < min_enrollable_seconds and not has_persisted:
            enrollable, reason = False, "too_short"
        else:
            enrollable, reason = True, None

    return {
        "label": label,
        "speech_seconds": round(speech_seconds, 1),
        "turns": len(turns),
        "enrollable": enrollable,
        "reason": reason,
    }


def build_enrollment_report(
    transcript,
    meeting_dir: Path,
    suggestions: list,
    mic_presence: MicPresence | None,
    *,
    min_enrollable_seconds: float = _DEFAULT_MIN_ENROLLABLE_SECONDS,
    now: datetime | None = None,
) -> dict:
    """Produce exactly the frozen enrollment_suggestions.json schema (never
    write it -- write_enrollment_report does that)."""
    persisted_clusters = _load_persisted_clusters(meeting_dir)

    clusters_report = [
        _cluster_report_entry(transcript, meeting_dir, label, persisted_clusters, min_enrollable_seconds)
        for label in _report_labels(transcript)
    ]

    suggestions_report = [
        {
            "cluster": s.cluster,
            "name": s.name,
            "confidence": s.confidence,
            "evidence_count": len({(e.start, e.end) for e in s.evidence}),
            "evidence_kinds": sorted({e.kind.value for e in s.evidence}),
        }
        for s in suggestions
    ]

    mic_presence_report = (
        None
        if mic_presence is None
        else {"cluster": mic_presence.cluster, "name": mic_presence.name, "score": mic_presence.score}
    )

    return {
        "version": 1,
        "generated_at": (now or datetime.now(UTC)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "clusters": clusters_report,
        "suggestions": suggestions_report,
        "mic_presence": mic_presence_report,
    }


def write_enrollment_report(report: dict, meeting_dir: Path) -> Path:
    """Write enrollment_suggestions.json -- and nothing else -- to meeting_dir.
    A second write replaces only this file; every other file in meeting_dir is
    untouched."""
    out_path = meeting_dir / ENROLLMENT_REPORT_FILENAME
    out_path.write_text(json.dumps(report, indent=2))
    return out_path
