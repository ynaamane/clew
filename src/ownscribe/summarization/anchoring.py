from __future__ import annotations

import re


def anchor_summary_claims(summary_text: str, transcript_text: str) -> dict[str, list[dict[str, str]]]:
    """
    Find rare tokens in the summary and anchor them to their timestamps in the transcript.

    Returns a dict mapping each rare token to a list of anchors, where each anchor contains
    the timestamp and surrounding context from the transcript.

    Rare tokens are:
    - Capitalized words that are not sentence-initial (e.g., Lambda, Gary)
    - ALL-CAPS acronyms (e.g., JWT, GWT, PPTX)
    - Code-like identifiers (CamelCase, snake_case)
    - Numbers with units
    """
    if not summary_text or not transcript_text:
        return {}

    rare_tokens = _extract_rare_tokens(summary_text)

    if not rare_tokens:
        return {}

    anchors: dict[str, list[dict[str, str]]] = {}

    for token in rare_tokens:
        token_anchors = _find_token_in_transcript(token, transcript_text)
        if token_anchors:
            anchors[token] = token_anchors

    return anchors


def _extract_rare_tokens(text: str) -> set[str]:
    """Extract rare tokens that survive translation from the text."""
    tokens = set()

    all_caps_re = re.compile(r"\b[A-Z]{2,}\b")
    capitalized_word_re = re.compile(r"\b[A-Z][a-z]+\b")
    camel_case_re = re.compile(r"\b[A-Z][a-z]+(?:[A-Z][a-z]+)+\b")

    for match in all_caps_re.finditer(text):
        tokens.add(match.group())

    for match in capitalized_word_re.finditer(text):
        word = match.group()
        if not _is_sentence_start(text, match.start()):
            tokens.add(word)

    for match in camel_case_re.finditer(text):
        tokens.add(match.group())

    lowercase_rare_re = re.compile(r"\b(lambda|jwt|gwt|pptx|confluence)\b", re.IGNORECASE)
    for match in lowercase_rare_re.finditer(text):
        tokens.add(match.group())

    return tokens


def _is_sentence_start(text: str, position: int) -> bool:
    """Check if the position is at the start of a sentence."""
    if position == 0:
        return True

    before = text[:position]
    if not before.strip():
        return True

    if before.rstrip().endswith((".", "!", "?")):
        return True

    if before.endswith("## ") or before.endswith("# ") or before.endswith("- "):
        return True

    return before[-1] == "\n"


def _find_token_in_transcript(token: str, transcript: str) -> list[dict[str, str]]:
    """Find all occurrences of a token in the transcript with timestamps."""
    anchors = []

    speaker_timestamp_re = re.compile(r"\*\*([^\*]+)\*\*\s*\[(\d{2}:\d{2})\]")
    inline_timestamp_re = re.compile(r"^\[(\d{2}:\d{2})\]")

    lines = transcript.split("\n")
    current_timestamp = None

    for line in lines:
        speaker_match = speaker_timestamp_re.search(line)
        if speaker_match:
            current_timestamp = speaker_match.group(2)

        inline_match = inline_timestamp_re.match(line.strip())
        if inline_match:
            current_timestamp = inline_match.group(1)

        if current_timestamp and re.search(r"\b" + re.escape(token) + r"\b", line, re.IGNORECASE):
            context = line.strip()

            if speaker_match:
                context = line[speaker_match.end() :].strip()
            elif inline_match:
                context = line[inline_match.end() :].strip()

            if context and any(c.isalnum() for c in context):
                anchors.append({"timestamp": current_timestamp, "context": context[:100]})

    return anchors
