"""Tests for LLM post-correction of transcript segment text."""

from __future__ import annotations

from unittest import mock

from clew.correction import _is_acceptable_correction, correct_segment_text, correct_transcript
from clew.transcription.models import Segment, TranscriptResult, Word


class TestIsAcceptableCorrection:
    def test_minor_fix_within_delta_accepted(self):
        assert _is_acceptable_correction("bonjour tout le monde", "bonjour a tous", 0.4) is True

    def test_wild_addition_rejected(self):
        original = "hi"
        corrected = "hi, and by the way we should also completely redo the entire roadmap"
        assert _is_acceptable_correction(original, corrected, 0.4) is False

    def test_empty_corrected_rejected(self):
        assert _is_acceptable_correction("hello", "", 0.4) is False

    def test_whitespace_only_corrected_rejected(self):
        assert _is_acceptable_correction("hello", "   ", 0.4) is False

    def test_empty_original_always_rejected(self):
        assert _is_acceptable_correction("", "anything", 0.4) is False

    def test_exact_match_accepted(self):
        assert _is_acceptable_correction("hello world", "hello world", 0.4) is True

    def test_exactly_at_threshold_accepted(self):
        assert _is_acceptable_correction("a" * 10, "a" * 14, 0.4) is True

    def test_just_over_threshold_rejected(self):
        assert _is_acceptable_correction("a" * 10, "a" * 15, 0.4) is False

    def test_shrinking_past_threshold_rejected(self):
        assert _is_acceptable_correction("a" * 10, "a" * 5, 0.4) is False


class TestCorrectSegmentText:
    def test_applies_accepted_correction(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "On continue le sprint review."
        seg = Segment(text="On continu le sprint reviu.", start=0.0, end=1.0, speaker="SPEAKER_00")

        corrected = correct_segment_text(summarizer, seg, 0.4)

        assert corrected.text == "On continue le sprint review."

    def test_preserves_timestamps_and_speaker(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "corrected text"
        seg = Segment(text="original text", start=1.5, end=3.2, speaker="Owner")

        corrected = correct_segment_text(summarizer, seg, 0.4)

        assert corrected.start == 1.5
        assert corrected.end == 3.2
        assert corrected.speaker == "Owner"

    def test_preserves_words(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "corrected"
        words = [Word(text="original", start=0.0, end=1.0)]
        seg = Segment(text="original", start=0.0, end=1.0, words=words)

        corrected = correct_segment_text(summarizer, seg, 0.4)

        assert corrected.words == words

    def test_rejects_hallucinated_correction_keeps_original(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = (
            "this is a wildly different response with a huge amount of unrelated hallucinated text"
        )
        seg = Segment(text="hi", start=0.0, end=1.0)

        corrected = correct_segment_text(summarizer, seg, 0.4)

        assert corrected.text == "hi"
        assert corrected == seg

    def test_does_not_mutate_original_segment(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "corrected text here"
        seg = Segment(text="original text here", start=0.0, end=1.0)

        correct_segment_text(summarizer, seg, 0.4)

        assert seg.text == "original text here"

    def test_calls_summarizer_with_segment_text_as_prompt(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "on continue"
        seg = Segment(text="on continu", start=0.0, end=1.0)

        correct_segment_text(summarizer, seg, 0.4)

        call_args = summarizer.chat.call_args
        assert call_args.args[1] == "on continu"


class TestCorrectTranscript:
    def test_corrects_every_segment(self):
        summarizer = mock.MagicMock()
        summarizer.chat.side_effect = ["Bonjour", "How are you"]
        result = TranscriptResult(
            segments=[
                Segment(text="Bonjur", start=0.0, end=1.0, speaker="SPEAKER_00"),
                Segment(text="How r you", start=1.0, end=2.0, speaker="Owner"),
            ],
            language="fr",
            duration=2.0,
        )

        corrected = correct_transcript(summarizer, result, 0.4)

        assert corrected.segments[0].text == "Bonjour"
        assert corrected.segments[1].text == "How are you"

    def test_preserves_segment_count(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "fixed"
        result = TranscriptResult(
            segments=[
                Segment(text="a", start=0.0, end=1.0),
                Segment(text="b", start=1.0, end=2.0),
                Segment(text="c", start=2.0, end=3.0),
            ]
        )

        corrected = correct_transcript(summarizer, result, 0.4)

        assert len(corrected.segments) == 3

    def test_preserves_language_and_duration(self):
        summarizer = mock.MagicMock()
        summarizer.chat.return_value = "fixed"
        result = TranscriptResult(
            segments=[Segment(text="a", start=0.0, end=1.0)],
            language="fr",
            duration=42.0,
        )

        corrected = correct_transcript(summarizer, result, 0.4)

        assert corrected.language == "fr"
        assert corrected.duration == 42.0

    def test_empty_transcript_returns_empty(self):
        summarizer = mock.MagicMock()
        result = TranscriptResult(segments=[])

        corrected = correct_transcript(summarizer, result, 0.4)

        assert corrected.segments == []
        summarizer.chat.assert_not_called()

    def test_rejects_bad_corrections_per_segment_independently(self):
        summarizer = mock.MagicMock()
        summarizer.chat.side_effect = [
            "Bonjour",
            "this is a wildly unrelated hallucinated addition that is far too long for the original",
        ]
        result = TranscriptResult(
            segments=[
                Segment(text="Bonjur", start=0.0, end=1.0),
                Segment(text="hi", start=1.0, end=2.0),
            ]
        )

        corrected = correct_transcript(summarizer, result, 0.4)

        assert corrected.segments[0].text == "Bonjour"
        assert corrected.segments[1].text == "hi"
