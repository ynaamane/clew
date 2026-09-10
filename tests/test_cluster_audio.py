"""Tests for clew.speakers.cluster_audio (BUILD NEXT #1 tranche 2, block A1)."""

from __future__ import annotations

import json

import numpy as np
import pytest
import soundfile as sf

from clew.speakers import cluster_audio
from clew.speakers.cluster_audio import (
    cluster_turns,
    cut_clip,
    select_cluster_spans,
    source_track_for,
    track_clock_shift,
    write_cluster_clip,
)
from clew.transcription.models import Segment, TranscriptResult


def _seg(speaker, start, end=None):
    """A markdown-shape segment by default (end == start, the real-world common
    case per _parse_markdown_transcript); pass end explicitly for a JSON-shape one."""
    resolved_end = start if end is None else end
    return Segment(text=f"{speaker}-{start}", start=start, end=resolved_end, speaker=speaker)


def _write_constant_blocks_wav(path, sample_rate, blocks):
    """blocks: list of (duration_seconds, value) concatenated into one mono FLOAT wav."""
    chunks = [np.full(round(dur * sample_rate), value, dtype="float32") for dur, value in blocks]
    data = np.concatenate(chunks)
    sf.write(str(path), data, sample_rate, subtype="FLOAT")


class TestClusterTurns:
    def test_single_segment_reconstructs_end_from_transcript_duration(self):
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0)], duration=10.0)
        assert cluster_turns(transcript, "SPEAKER_00") == [(0.0, 10.0)]

    def test_reconstructs_end_from_next_segment_start_any_speaker(self):
        transcript = TranscriptResult(
            segments=[_seg("A", 0.0), _seg("B", 5.0), _seg("A", 8.0)],
            duration=12.0,
        )
        assert cluster_turns(transcript, "A") == [(0.0, 5.0), (8.0, 12.0)]

    def test_consecutive_same_speaker_segments_merge_into_one_turn(self):
        transcript = TranscriptResult(
            segments=[_seg("A", 0.0), _seg("A", 4.0), _seg("B", 9.0)],
            duration=15.0,
        )
        assert cluster_turns(transcript, "A") == [(0.0, 9.0)]

    def test_effective_end_extends_past_a_smaller_real_end_to_the_next_segment_start(self):
        # Not the last segment: a real end (1.8) smaller than the next segment's
        # start (5.0) is filled up to that start, never left as a premature cut.
        transcript = TranscriptResult(
            segments=[Segment(text="a", start=0.0, end=1.8, speaker="A"), _seg("Z", 5.0)],
            duration=20.0,
        )
        assert cluster_turns(transcript, "A") == [(0.0, 5.0)]

    def test_real_end_past_the_next_segment_start_is_never_shrunk(self):
        transcript = TranscriptResult(
            segments=[
                Segment(text="a", start=0.0, end=3.0, speaker="A"),
                Segment(text="b", start=2.5, end=5.0, speaker="B"),
            ],
            duration=10.0,
        )
        assert cluster_turns(transcript, "A") == [(0.0, 3.0)]

    def test_no_matching_speaker_returns_empty(self):
        transcript = TranscriptResult(segments=[_seg("A", 0.0)], duration=5.0)
        assert cluster_turns(transcript, "B") == []

    def test_a_lone_utterance_far_from_the_next_segment_does_not_inflate_the_turn(self):
        # Review finding F3: a real utterance's end must never absorb an
        # arbitrarily large silent gap into the turn -- a Whisper segment
        # never decodes past 30s, so reconstruction is capped at start + 30.0.
        transcript = TranscriptResult(
            segments=[Segment(text="hi", start=1.0, end=1.0, speaker="SPEAKER_00")],
            duration=1000.0,
        )
        assert cluster_turns(transcript, "SPEAKER_00") == [(1.0, 31.0)]

    def test_the_cap_does_not_shrink_a_normal_small_gap(self):
        transcript = TranscriptResult(segments=[_seg("A", 0.0), _seg("B", 20.0)], duration=100.0)
        assert cluster_turns(transcript, "A") == [(0.0, 20.0)]

    def test_the_cap_does_not_shrink_a_real_end_even_past_30s(self):
        # The cap only ever bounds the RECONSTRUCTION target; a genuinely
        # observed real end is never shrunk below itself (existing invariant,
        # unaffected by F3).
        transcript = TranscriptResult(
            segments=[Segment(text="a", start=0.0, end=45.0, speaker="A"), _seg("B", 50.0)],
            duration=100.0,
        )
        assert cluster_turns(transcript, "A") == [(0.0, 45.0)]

    def test_a_large_gap_to_the_next_same_speaker_segment_splits_the_run(self):
        # Review finding R2: exact reviewer probe (10-13s and 900-903s, 1000s recording).
        transcript = TranscriptResult(
            segments=[
                Segment(text="hi there", start=10.0, end=13.0, speaker="SPEAKER_00"),
                Segment(text="hi again", start=900.0, end=903.0, speaker="SPEAKER_00"),
            ],
            duration=1000.0,
        )
        assert cluster_turns(transcript, "SPEAKER_00") == [(10.0, 40.0), (900.0, 930.0)]

    def test_dense_transcript_with_small_gaps_is_unaffected_by_the_gap_condition(self):
        # Regression guard: R2's gap-split must never fire on ordinary speech.
        transcript = TranscriptResult(
            segments=[
                _seg("A", 0.0),
                _seg("A", 4.0),
                _seg("B", 9.0),
                _seg("A", 20.0),
                _seg("A", 25.0),
                _seg("F", 40.0),
            ],
            duration=100.0,
        )
        assert cluster_turns(transcript, "A") == [(0.0, 9.0), (20.0, 40.0)]


class TestSelectClusterSpans:
    def test_drops_turn_in_first_boundary_fraction(self):
        transcript = TranscriptResult(segments=[_seg("A", 0.0), _seg("F", 8.0)], duration=100.0)
        assert select_cluster_spans(transcript, "A") == []

    def test_drops_turn_in_last_boundary_fraction(self):
        transcript = TranscriptResult(
            segments=[Segment(text="hi", start=92.0, end=100.0, speaker="A")],
            duration=100.0,
        )
        assert select_cluster_spans(transcript, "A") == []

    def test_keeps_a_mid_run_turn(self):
        transcript = TranscriptResult(segments=[_seg("A", 40.0), _seg("F", 50.0)], duration=100.0)
        assert select_cluster_spans(transcript, "A") == [(41.0, 49.0)]

    def test_trims_edge_seconds_off_both_ends(self):
        transcript = TranscriptResult(segments=[_seg("A", 40.0), _seg("F", 50.0)], duration=100.0)
        spans = select_cluster_spans(transcript, "A", edge_trim_seconds=2.0)
        assert spans == [(42.0, 48.0)]

    def test_drops_turns_too_short_after_trimming(self):
        transcript = TranscriptResult(segments=[_seg("A", 40.0), _seg("F", 44.0)], duration=100.0)
        # raw length 4s, trimmed 1s each side -> 2s < min_turn_seconds (3s default)
        assert select_cluster_spans(transcript, "A") == []

    def test_selects_longest_turns_first_and_truncates_to_fit_budget(self):
        transcript = TranscriptResult(
            segments=[_seg("A", 20.0), _seg("B", 32.0), _seg("A", 80.0), _seg("F", 86.0)],
            duration=100.0,
        )
        # A turns: (20,32) len12 -> trimmed (21,31) len10; (80,86) len6 -> trimmed (81,85) len4.
        spans = select_cluster_spans(transcript, "A", max_total_seconds=12.0)
        assert spans == [(21.0, 31.0), (81.0, 83.0)]

    def test_returns_spans_in_chronological_order_even_if_selected_out_of_order(self):
        transcript = TranscriptResult(
            segments=[_seg("A", 10.0), _seg("B", 16.0), _seg("A", 60.0), _seg("F", 70.0)],
            duration=100.0,
        )
        spans = select_cluster_spans(transcript, "A", max_total_seconds=100.0)
        assert spans == [(11.0, 15.0), (61.0, 69.0)]

    def test_prefers_long_mid_run_turn_over_a_longer_boundary_turn(self):
        transcript = TranscriptResult(
            segments=[_seg("A", 0.0), _seg("F", 9.0), _seg("A", 50.0), _seg("F", 56.0)],
            duration=100.0,
        )
        spans = select_cluster_spans(transcript, "A")
        assert spans == [(51.0, 55.0)]

    def test_no_segments_returns_empty(self):
        transcript = TranscriptResult(segments=[], duration=100.0)
        assert select_cluster_spans(transcript, "A") == []

    def test_zero_duration_transcript_does_not_boundary_exclude(self):
        transcript = TranscriptResult(
            segments=[Segment(text="hi", start=0.0, end=10.0, speaker="A")],
            duration=0.0,
        )
        assert select_cluster_spans(transcript, "A") == [(1.0, 9.0)]

    def test_a_sparse_boundary_utterance_is_correctly_excluded_after_the_turn_cap(self):
        # Review finding F3, reproduced exactly (spec probe e): pre-fix,
        # absorbing the whole 1000s tail moved the turn's midpoint outside the
        # boundary zone even though the real speech sits at t=1 -- defeating
        # the boundary-exclusion rule and letting a near-silent 30s clip enroll.
        transcript = TranscriptResult(
            segments=[Segment(text="hi there", start=1.0, end=4.0, speaker="SPEAKER_00")],
            duration=1000.0,
        )
        assert select_cluster_spans(transcript, "SPEAKER_00") == []


class TestTrackClockShift:
    def test_missing_path_yields_zero_shift(self, tmp_path):
        missing = tmp_path / "does-not-exist.json"
        assert track_clock_shift(missing, "system.wav") == 0.0
        assert track_clock_shift(missing, "mic.wav") == 0.0

    def test_none_path_yields_zero_shift(self):
        assert track_clock_shift(None, "system.wav") == 0.0
        assert track_clock_shift(None, "mic.wav") == 0.0

    def test_positive_offset_shifts_mic_only(self, tmp_path):
        path = tmp_path / "track_alignment.json"
        path.write_text(json.dumps({"mic_start_offset_seconds": 2.5}))
        assert track_clock_shift(path, "system.wav") == 0.0
        assert track_clock_shift(path, "mic.wav") == pytest.approx(2.5)

    def test_negative_offset_shifts_system_only(self, tmp_path):
        path = tmp_path / "track_alignment.json"
        path.write_text(json.dumps({"mic_start_offset_seconds": -1.5}))
        assert track_clock_shift(path, "system.wav") == pytest.approx(1.5)
        assert track_clock_shift(path, "mic.wav") == 0.0

    def test_recovers_original_starts_through_the_real_merge_positive_offset(self, tmp_path):
        from clew.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[Segment(text="sys", start=2.0, end=3.0, speaker="SPEAKER_00")],
            duration=10.0,
        )
        mic_result = TranscriptResult(segments=[Segment(text="mic", start=1.0, end=2.0)], duration=8.0)
        mic_offset = 3.0

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset)

        path = tmp_path / "track_alignment.json"
        path.write_text(json.dumps({"mic_start_offset_seconds": mic_offset}))

        system_seg = next(s for s in merged.segments if s.speaker != "Owner")
        mic_seg = next(s for s in merged.segments if s.speaker == "Owner")

        assert system_seg.start - track_clock_shift(path, "system.wav") == pytest.approx(2.0)
        assert mic_seg.start - track_clock_shift(path, "mic.wav") == pytest.approx(1.0)

    def test_recovers_original_starts_through_the_real_merge_negative_offset(self, tmp_path):
        from clew.pipeline import _merge_dual_track_results

        system_result = TranscriptResult(
            segments=[Segment(text="sys", start=2.0, end=3.0, speaker="SPEAKER_00")],
            duration=10.0,
        )
        mic_result = TranscriptResult(segments=[Segment(text="mic", start=1.0, end=2.0)], duration=8.0)
        mic_offset = -2.0

        merged = _merge_dual_track_results(system_result, mic_result, mic_offset)

        path = tmp_path / "track_alignment.json"
        path.write_text(json.dumps({"mic_start_offset_seconds": mic_offset}))

        system_seg = next(s for s in merged.segments if s.speaker != "Owner")
        mic_seg = next(s for s in merged.segments if s.speaker == "Owner")

        assert system_seg.start - track_clock_shift(path, "system.wav") == pytest.approx(2.0)
        assert mic_seg.start - track_clock_shift(path, "mic.wav") == pytest.approx(1.0)


class TestSourceTrackFor:
    def test_owner_label_maps_to_mic_track(self):
        from clew.pipeline import _OWNER_SPEAKER_LABEL

        assert source_track_for(_OWNER_SPEAKER_LABEL) == "mic.wav"

    def test_other_cluster_maps_to_system_track(self):
        assert source_track_for("SPEAKER_00") == "system.wav"


class TestCutClip:
    def test_cuts_and_concatenates_the_exact_samples_for_each_span(self, tmp_path):
        sample_rate = 100
        source = tmp_path / "source.wav"
        _write_constant_blocks_wav(
            source,
            sample_rate,
            [(2.0, 0.1), (2.0, 0.2), (2.0, 0.3), (2.0, 0.4), (2.0, 0.5)],
        )
        out_path = tmp_path / "clip.wav"

        duration = cut_clip(source, [(2.0, 4.0), (6.0, 8.0)], out_path)

        assert duration == pytest.approx(4.0)
        data, sr = sf.read(str(out_path), dtype="float32")
        assert sr == sample_rate
        assert len(data) == 400
        assert np.allclose(data[:200], 0.2, atol=1e-6)
        assert np.allclose(data[200:], 0.4, atol=1e-6)

    def test_clamps_spans_past_the_end_of_the_file(self, tmp_path):
        sample_rate = 100
        source = tmp_path / "source.wav"
        _write_constant_blocks_wav(source, sample_rate, [(10.0, 0.5)])
        out_path = tmp_path / "clip.wav"

        duration = cut_clip(source, [(9.0, 15.0)], out_path)

        assert duration == pytest.approx(1.0)
        data, _ = sf.read(str(out_path), dtype="float32")
        assert len(data) == 100
        assert np.allclose(data, 0.5, atol=1e-6)


class TestWriteClusterClip:
    def test_missing_source_track_raises_filenotfounderror_naming_it(self, tmp_path):
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0)], duration=20.0)
        with pytest.raises(FileNotFoundError, match=r"system\.wav"):
            write_cluster_clip(tmp_path, transcript, "SPEAKER_00", tmp_path / "clip.wav")

    def test_no_qualifying_span_raises_valueerror(self, tmp_path):
        (tmp_path / "system.wav").touch()
        transcript = TranscriptResult(
            segments=[_seg("SPEAKER_00", 40.0), _seg("F", 42.5)],
            duration=100.0,
        )
        with pytest.raises(ValueError, match="SPEAKER_00"):
            write_cluster_clip(tmp_path, transcript, "SPEAKER_00", tmp_path / "clip.wav")

    def test_happy_path_writes_a_clip_and_returns_its_duration(self, tmp_path):
        sample_rate = 50
        system_path = tmp_path / "system.wav"
        _write_constant_blocks_wav(system_path, sample_rate, [(100.0, 0.3)])

        transcript = TranscriptResult(
            segments=[_seg("OTHER", 0.0), _seg("SPEAKER_00", 30.0)],
            duration=100.0,
        )
        out_path = tmp_path / "clip.wav"

        expected_spans = select_cluster_spans(transcript, "SPEAKER_00")
        expected_total = sum(end - start for start, end in expected_spans)

        duration = write_cluster_clip(tmp_path, transcript, "SPEAKER_00", out_path)

        assert out_path.exists()
        assert expected_total > 0
        assert duration == pytest.approx(expected_total, abs=0.05)

    def test_applies_track_clock_shift_before_cutting(self, tmp_path, monkeypatch):
        from clew.pipeline import _OWNER_SPEAKER_LABEL

        transcript = TranscriptResult(
            segments=[_seg("SPEAKER_00", 0.0), _seg(_OWNER_SPEAKER_LABEL, 20.0)],
            duration=40.0,
        )
        (tmp_path / "track_alignment.json").write_text(json.dumps({"mic_start_offset_seconds": 5.0}))
        mic_path = tmp_path / "mic.wav"
        mic_path.touch()

        captured = {}

        def fake_cut_clip(audio_path, spans, out_path):
            captured["audio_path"] = audio_path
            captured["spans"] = spans
            return 5.0

        monkeypatch.setattr(cluster_audio, "cut_clip", fake_cut_clip)

        write_cluster_clip(tmp_path, transcript, _OWNER_SPEAKER_LABEL, tmp_path / "clip.wav")

        assert captured["audio_path"] == mic_path
        merged_spans = select_cluster_spans(transcript, _OWNER_SPEAKER_LABEL)
        assert merged_spans
        expected = [(start - 5.0, end - 5.0) for start, end in merged_spans]
        assert captured["spans"] == pytest.approx(expected)
