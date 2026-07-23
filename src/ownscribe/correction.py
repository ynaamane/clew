"""LLM post-correction pass over transcript segment text (spelling/code-switch cleanup only)."""

from __future__ import annotations

from dataclasses import replace

from ownscribe.summarization.base import Summarizer
from ownscribe.summarization.prompts import CORRECTION_PROMPT, CORRECTION_SYSTEM
from ownscribe.transcription.models import Segment, TranscriptResult


def _is_acceptable_correction(original: str, corrected: str, max_length_delta_ratio: float) -> bool:
    if not corrected.strip():
        return False
    original_len = len(original)
    if original_len == 0:
        return False
    delta_ratio = abs(len(corrected) - original_len) / original_len
    return delta_ratio <= max_length_delta_ratio


def correct_segment_text(
    summarizer: Summarizer,
    segment: Segment,
    max_length_delta_ratio: float,
) -> Segment:
    original_text = segment.text
    prompt = CORRECTION_PROMPT.format(segment_text=original_text)
    corrected_text = summarizer.chat(CORRECTION_SYSTEM, prompt).strip()

    if not _is_acceptable_correction(original_text, corrected_text, max_length_delta_ratio):
        return segment

    return replace(segment, text=corrected_text)


def correct_transcript(
    summarizer: Summarizer,
    result: TranscriptResult,
    max_length_delta_ratio: float = 0.4,
) -> TranscriptResult:
    corrected_segments = [
        correct_segment_text(summarizer, seg, max_length_delta_ratio) for seg in result.segments
    ]
    return replace(result, segments=corrected_segments)
