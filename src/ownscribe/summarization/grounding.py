"""Deterministic check for names invented by the summarizer that aren't in the source."""

from __future__ import annotations

import re

_CAPITALIZED_WORD_RE = re.compile(r"\b[A-Z][a-z]+\b")

_COMMON_SENTENCE_STARTERS = {
    "The", "This", "That", "These", "Those", "A", "An", "It", "They", "We", "You", "He", "She",
    "I", "Summary", "Key", "Points", "Action", "Items", "Decisions", "Meeting", "Concepts",
    "Takeaways", "Overview", "None", "Mentioned", "Monday", "Tuesday", "Wednesday", "Thursday",
    "Friday", "Saturday", "Sunday", "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}


def find_ungrounded_names(summary_text: str, transcript_text: str) -> list[str]:
    """Return capitalized words in the summary that never appear in the transcript."""
    summary_words = set(_CAPITALIZED_WORD_RE.findall(summary_text)) - _COMMON_SENTENCE_STARTERS
    transcript_lower = transcript_text.lower()
    return sorted(word for word in summary_words if word.lower() not in transcript_lower)
