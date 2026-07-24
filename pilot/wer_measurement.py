"""WER measurement for the Canary-vs-WhisperX A/B pilot, split by reference
language span (overall / FR-only / EN-only / code-switch).

Both engines expose timestamps only at the SEGMENT level in the common case
(Canary has no word-level output at all; see NOTES.md Task#8) -- so every
comparison here operates on time-window overlap between a hypothesis
segment and a reference utterance, not on a word-level alignment across
engines. This is the only fair common denominator between the two engines.

A reference utterance counts as a "switch" utterance if it contains at
least one 'fra' word AND at least one 'eng' word (per-word tags from
cha_parser.parse_cha) -- the definition of intra-sentential code-switching
this whole pilot is built to measure.
"""

from __future__ import annotations

from dataclasses import dataclass

import jiwer
from cha_parser import Utterance

_NORMALIZE = jiwer.Compose(
    [
        jiwer.ToLowerCase(),
        jiwer.RemovePunctuation(),
        jiwer.RemoveMultipleSpaces(),
        jiwer.Strip(),
        jiwer.ReduceToListOfListOfWords(),
    ]
)


@dataclass
class HypothesisSegment:
    text: str
    start_s: float
    end_s: float


def _overlaps(seg_start: float, seg_end: float, window_start: float, window_end: float) -> bool:
    return seg_start < window_end and seg_end > window_start


def _reference_text(utterances: list[Utterance]) -> str:
    return " ".join(" ".join(u.words) for u in utterances)


def _hypothesis_text_for_utterances(
    segments: list[HypothesisSegment], utterances: list[Utterance], window_start_s: float
) -> str:
    """Union of hypothesis segments overlapping ANY of the given utterances' windows,
    deduplicated and returned in chronological order -- a segment spanning multiple
    short reference utterances contributes its text exactly once, not once per
    overlapping utterance."""
    matched_indices: set[int] = set()
    for u in utterances:
        window_start = (u.start_ms / 1000.0) - window_start_s
        window_end = (u.end_ms / 1000.0) - window_start_s
        for i, seg in enumerate(segments):
            if _overlaps(seg.start_s, seg.end_s, window_start, window_end):
                matched_indices.add(i)
    return " ".join(segments[i].text for i in sorted(matched_indices))


def classify_utterance(utterance: Utterance) -> str:
    """'switch' if the utterance mixes fra+eng words, else its dominant tagged language, else 'unknown'."""
    languages = set(utterance.word_languages) - {"unknown"}
    if "fra" in languages and "eng" in languages:
        return "switch"
    if languages == {"fra"}:
        return "fra"
    if languages == {"eng"}:
        return "eng"
    return "unknown"


def compute_wer(reference_text: str, hypothesis_text: str) -> float:
    if not reference_text.strip():
        return float("nan")
    return jiwer.wer(
        reference_text,
        hypothesis_text,
        reference_transform=_NORMALIZE,
        hypothesis_transform=_NORMALIZE,
    )


def wer_by_span(
    reference_utterances: list[Utterance],
    hypothesis_segments: list[HypothesisSegment],
    window_start_s: float,
) -> dict[str, float]:
    """WER for 'overall', 'fra', 'eng', and 'switch' reference spans.

    Reference utterance timestamps are absolute (relative to the source
    recording); window_start_s converts them into the clip-relative
    timeline the hypothesis segments use.
    """
    by_class: dict[str, list[Utterance]] = {"fra": [], "eng": [], "switch": [], "unknown": []}
    for u in reference_utterances:
        by_class[classify_utterance(u)].append(u)

    results: dict[str, float] = {
        "overall": compute_wer(_reference_text(reference_utterances), " ".join(s.text for s in hypothesis_segments))
    }

    for label in ("fra", "eng", "switch"):
        utterances = by_class[label]
        if not utterances:
            results[label] = float("nan")
            continue
        reference_text = _reference_text(utterances)
        hypothesis_text = _hypothesis_text_for_utterances(hypothesis_segments, utterances, window_start_s)
        results[label] = compute_wer(reference_text, hypothesis_text)

    return results
