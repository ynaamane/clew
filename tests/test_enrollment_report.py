"""Tests for clew.speakers.enrollment_report (BUILD NEXT #1 tranche 2, block A5)."""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime

import pytest

from clew.pipeline import SPEAKER_EMBEDDINGS_FILENAME
from clew.speakers.enrollment_report import (
    ENROLLMENT_REPORT_FILENAME,
    build_enrollment_report,
    write_enrollment_report,
)
from clew.speakers.enrollment_suggest import Evidence, EvidenceKind, Suggestion
from clew.speakers.mic_presence import MicPresence
from clew.transcription.models import Segment, TranscriptResult

_FIXED_NOW = datetime(2026, 9, 10, 12, 34, 56, tzinfo=UTC)


def _seg(speaker, start, end=None):
    resolved_end = start if end is None else end
    return Segment(text=f"{speaker}-{start}", start=start, end=resolved_end, speaker=speaker)


def _evidence(kind, start, end):
    return Evidence(
        kind=kind, name="X", speaker_cluster="SPEAKER_00", excluded_cluster=None, start=start, end=end, weight=1.0
    )


class TestGeneratedAt:
    def test_formats_injected_now_as_iso8601_utc_with_z_suffix(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)
        assert report["generated_at"] == "2026-09-10T12:34:56Z"

    def test_defaults_to_the_current_utc_time_when_omitted(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        before = datetime.now(UTC).replace(microsecond=0)
        report = build_enrollment_report(transcript, tmp_path, [], None)
        after = datetime.now(UTC).replace(microsecond=0)
        generated = datetime.strptime(report["generated_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)
        assert before <= generated <= after

    def test_version_is_always_1(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)
        assert report["version"] == 1


class TestBuildEnrollmentReportClusters:
    def test_markdown_shaped_transcript_speech_seconds_and_turns(self, tmp_path):
        (tmp_path / "system.wav").touch()
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0), _seg("F", 10.0)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["speech_seconds"] == pytest.approx(10.0)
        assert cluster["turns"] == 1

    def test_json_shaped_transcript_speech_seconds_and_turns(self, tmp_path):
        # cluster_turns (block A1) extends a real end up to the next segment's
        # start when there's a gap (max(seg.end, next_start)) -- 8.0 grows to
        # 10.0 here, same rule test_cluster_audio.py already locks in.
        (tmp_path / "system.wav").touch()
        transcript = TranscriptResult(
            segments=[
                Segment(text="a", start=0.0, end=8.0, speaker="SPEAKER_00"),
                Segment(text="f", start=10.0, end=11.0, speaker="F"),
            ],
            duration=100.0,
        )

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["speech_seconds"] == pytest.approx(10.0)
        assert cluster["turns"] == 1

    def test_owner_included_when_owner_segments_exist(self, tmp_path):
        (tmp_path / "mic.wav").touch()
        transcript = TranscriptResult(
            segments=[_seg("SPEAKER_00", 0.0), _seg("Owner", 10.0), _seg("F", 20.0)], duration=100.0
        )

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        assert "Owner" in {c["label"] for c in report["clusters"]}

    def test_owner_excluded_when_no_owner_segments(self, tmp_path):
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0), _seg("F", 10.0)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        assert "Owner" not in {c["label"] for c in report["clusters"]}

    def test_regex_only_matches_speaker_nn_labels_exactly(self, tmp_path):
        # Two distinct ways a label can fail to be a real SPEAKER_NN diarization
        # label: wrong prefix (SPEAKERX_01) and right prefix but non-digit suffix
        # (SPEAKER_ABC) -- the latter is what a loosened `^SPEAKER_` (missing the
        # `\d+$` anchor) would wrongly let through.
        (tmp_path / "system.wav").touch()
        transcript = TranscriptResult(
            segments=[
                _seg("SPEAKER_00", 0.0),
                _seg("SPEAKERX_01", 30.0),
                _seg("SPEAKER_ABC", 60.0),
                _seg("F", 90.0),
            ],
            duration=100.0,
        )

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        assert {c["label"] for c in report["clusters"]} == {"SPEAKER_00"}

    def test_audio_purged_reason_when_track_missing_and_no_persisted_vector(self, tmp_path):
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0), _seg("F", 50.0)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["enrollable"] is False
        assert cluster["reason"] == "audio_purged"

    def test_persisted_vector_makes_an_audio_purged_cluster_enrollable(self, tmp_path):
        (tmp_path / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2]}, "assignments": {}})
        )
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0), _seg("F", 50.0)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["enrollable"] is True
        assert cluster["reason"] is None

    def test_too_short_reason_when_selectable_total_below_minimum_and_no_persisted_vector(self, tmp_path):
        (tmp_path / "system.wav").touch()
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 40.0), _seg("F", 42.5)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW, min_enrollable_seconds=10.0)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["enrollable"] is False
        assert cluster["reason"] == "too_short"

    def test_persisted_vector_makes_a_too_short_cluster_enrollable(self, tmp_path):
        (tmp_path / "system.wav").touch()
        (tmp_path / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2]}, "assignments": {}})
        )
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 40.0), _seg("F", 42.5)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW, min_enrollable_seconds=10.0)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["enrollable"] is True
        assert cluster["reason"] is None

    def test_enrollable_true_with_no_reason_when_long_enough(self, tmp_path):
        (tmp_path / "system.wav").touch()
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 30.0), _seg("F", 70.0)], duration=100.0)

        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)

        cluster = next(c for c in report["clusters"] if c["label"] == "SPEAKER_00")
        assert cluster["enrollable"] is True
        assert cluster["reason"] is None


class TestBuildEnrollmentReportSuggestions:
    def test_suggestion_mapping_includes_confidence_count_and_sorted_kinds(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        suggestion = Suggestion(
            cluster="SPEAKER_00",
            name="Kamal",
            confidence="high",
            evidence=[
                _evidence(EvidenceKind.SELF_INTRO, 0.0, 1.0),
                _evidence(EvidenceKind.MIC_PRESENCE, 5.0, 6.0),
                _evidence(EvidenceKind.SELF_INTRO, 0.0, 1.0),  # duplicate location
            ],
        )

        report = build_enrollment_report(transcript, tmp_path, [suggestion], None, now=_FIXED_NOW)

        assert report["suggestions"] == [
            {
                "cluster": "SPEAKER_00",
                "name": "Kamal",
                "confidence": "high",
                "evidence_count": 2,
                "evidence_kinds": ["mic_presence", "self_intro"],
            }
        ]

    def test_empty_suggestions_list_is_preserved_not_forced(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)
        assert report["suggestions"] == []


class TestBuildEnrollmentReportMicPresence:
    def test_none_serializes_to_null(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        report = build_enrollment_report(transcript, tmp_path, [], None, now=_FIXED_NOW)
        assert report["mic_presence"] is None

    def test_populated_presence_preserves_nulls(self, tmp_path):
        transcript = TranscriptResult(segments=[], duration=100.0)
        presence = MicPresence(cluster="SPEAKER_02", name=None, score=0.777, start=1.0, end=2.0)

        report = build_enrollment_report(transcript, tmp_path, [], presence, now=_FIXED_NOW)

        assert report["mic_presence"] == {"cluster": "SPEAKER_02", "name": None, "score": 0.777}


class TestWriteEnrollmentReport:
    def test_writes_indented_json_to_the_named_file(self, tmp_path):
        report = {
            "version": 1,
            "generated_at": "2026-09-10T12:34:56Z",
            "clusters": [],
            "suggestions": [],
            "mic_presence": None,
        }

        out_path = write_enrollment_report(report, tmp_path)

        assert out_path == tmp_path / ENROLLMENT_REPORT_FILENAME
        assert json.loads(out_path.read_text()) == report
        assert "\n" in out_path.read_text()

    def test_second_write_replaces_only_its_own_file(self, tmp_path):
        sentinel_path = tmp_path / "transcript.json"
        sentinel_path.write_text('{"hello": "world"}')
        before = os.stat(sentinel_path)

        report1 = {
            "version": 1,
            "generated_at": "2026-09-10T12:34:56Z",
            "clusters": [],
            "suggestions": [],
            "mic_presence": None,
        }
        write_enrollment_report(report1, tmp_path)

        report2 = {
            "version": 1,
            "generated_at": "2026-09-10T13:00:00Z",
            "clusters": [
                {"label": "SPEAKER_00", "speech_seconds": 1.0, "turns": 1, "enrollable": True, "reason": None}
            ],
            "suggestions": [],
            "mic_presence": None,
        }
        out_path = write_enrollment_report(report2, tmp_path)

        after = os.stat(sentinel_path)
        assert after.st_mtime_ns == before.st_mtime_ns
        assert after.st_size == before.st_size
        assert json.loads(out_path.read_text()) == report2
