"""Tests for pilot/wer_measurement.py.

The double-counting bug this suite pins down
(TestNoDoubleCounting.test_no_double_counting_when_one_hypothesis_segment_spans_multiple_short_reference_utterances)
was a real bug caught by running the module against real WhisperX output on
the FEBLOC fallback clip -- not found by inspection. WhisperX's segments span
multiple short reference utterances (turn-taking dialogue), and the first
implementation concatenated the SAME hypothesis segment once per overlapping
reference utterance, producing WER > 1.0 (impossible under jiwer's own
definition unless insertions alone exceed the reference length by a lot,
which is exactly what happened: a 3-word segment counted six times against
six different short reference utterances).
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "pilot"))

from cha_parser import Utterance
from wer_measurement import (
    HypothesisSegment,
    classify_utterance,
    compute_wer,
    wer_by_span,
)


def _utterance(words: list[str], languages: list[str], start_ms: int, end_ms: int) -> Utterance:
    return Utterance(speaker="X", start_ms=start_ms, end_ms=end_ms, words=words, word_languages=languages)


class TestClassifyUtterance:
    def test_all_french_words(self):
        u = _utterance(["bonjour"], ["fra"], 0, 100)
        assert classify_utterance(u) == "fra"

    def test_all_english_words(self):
        u = _utterance(["hello"], ["eng"], 0, 100)
        assert classify_utterance(u) == "eng"

    def test_mixed_french_and_english_is_switch(self):
        u = _utterance(["un", "sac", "chips"], ["fra", "fra", "eng"], 0, 100)
        assert classify_utterance(u) == "switch"

    def test_all_unknown_language_is_unknown(self):
        u = _utterance(["mm"], ["unknown"], 0, 100)
        assert classify_utterance(u) == "unknown"

    def test_unknown_words_ignored_when_classifying_alongside_a_real_language(self):
        u = _utterance(["okay", "toutou"], ["unknown", "fra"], 0, 100)
        assert classify_utterance(u) == "fra"


class TestComputeWer:
    def test_identical_text_is_zero_wer(self):
        assert compute_wer("bonjour le monde", "bonjour le monde") == 0.0

    def test_completely_different_text_is_high_wer(self):
        assert compute_wer("bonjour le monde", "goodbye earth now") > 0.5

    def test_case_and_punctuation_insensitive(self):
        assert compute_wer("Bonjour, le monde!", "bonjour le monde") == 0.0

    def test_empty_reference_is_nan(self):
        assert math.isnan(compute_wer("", "some hypothesis"))


class TestNoDoubleCounting:
    def test_no_double_counting_when_one_hypothesis_segment_spans_multiple_short_reference_utterances(self):
        # Three short reference utterances, all inside ONE long hypothesis segment's window.
        reference_utterances = [
            _utterance(["une"], ["fra"], 0, 500),
            _utterance(["cannette"], ["fra"], 500, 1000),
            _utterance(["mauve"], ["fra"], 1000, 1500),
        ]
        hypothesis_segments = [HypothesisSegment(text="une cannette mauve", start_s=0.0, end_s=1.5)]

        results = wer_by_span(reference_utterances, hypothesis_segments, window_start_s=0.0)

        assert results["fra"] == 0.0
        assert results["overall"] == 0.0

    def test_wer_never_exceeds_reasonable_bound_under_segment_granularity_mismatch(self):
        # Same scenario, but the hypothesis segment omits one reference word --
        # a real error should still produce a bounded WER, never > 1.0 from
        # the pure act of overlapping multiple reference utterances.
        reference_utterances = [
            _utterance(["une"], ["fra"], 0, 500),
            _utterance(["cannette"], ["fra"], 500, 1000),
            _utterance(["mauve"], ["fra"], 1000, 1500),
        ]
        hypothesis_segments = [HypothesisSegment(text="une cannette", start_s=0.0, end_s=1.5)]

        results = wer_by_span(reference_utterances, hypothesis_segments, window_start_s=0.0)

        assert 0.0 < results["fra"] <= 1.0


class TestWerBySpan:
    def test_missing_class_reports_nan_not_zero(self):
        reference_utterances = [_utterance(["bonjour"], ["fra"], 0, 500)]
        hypothesis_segments = [HypothesisSegment(text="bonjour", start_s=0.0, end_s=0.5)]

        results = wer_by_span(reference_utterances, hypothesis_segments, window_start_s=0.0)

        assert math.isnan(results["eng"])
        assert math.isnan(results["switch"])
        assert results["fra"] == 0.0

    def test_window_start_offset_shifts_reference_timestamps_correctly(self):
        # Reference timestamps are absolute; window_start_s must convert them
        # to the clip-relative timeline the hypothesis segments live on.
        reference_utterances = [_utterance(["bonjour"], ["fra"], 100_000, 100_500)]
        hypothesis_segments = [HypothesisSegment(text="bonjour", start_s=0.0, end_s=0.5)]

        results = wer_by_span(reference_utterances, hypothesis_segments, window_start_s=100.0)

        assert results["fra"] == 0.0

    def test_overall_uses_every_segment_regardless_of_class(self):
        reference_utterances = [
            _utterance(["bonjour"], ["fra"], 0, 500),
            _utterance(["hello"], ["eng"], 500, 1000),
        ]
        hypothesis_segments = [
            HypothesisSegment(text="bonjour", start_s=0.0, end_s=0.5),
            HypothesisSegment(text="hello", start_s=0.5, end_s=1.0),
        ]

        results = wer_by_span(reference_utterances, hypothesis_segments, window_start_s=0.0)

        assert results["overall"] == 0.0
        assert results["fra"] == 0.0
        assert results["eng"] == 0.0
