"""Deterministic evidence extraction and LLM-arbitrated auto-suggest enrollment.

Tranche 1 of BUILD NEXT #1 (see TODO.md, enrollment/overlap design paragraphs):
extracts self-introductions and vocatives from a diarized TranscriptResult into a
structured, inspectable Evidence table, then arbitrates cluster<->name suggestions
over that table (never over raw transcript text). Never auto-enrolls.

Known limitation, deliberate for this tranche: downweighting evidence inside
pyannote overlap zones is NOT implemented -- Segment carries no overlap data today.
That is BUILD NEXT #5 (surface pyannote overlap as "chevauchement"); revisit this
module once overlap regions are threaded into TranscriptResult. Only recording-
boundary downweighting (first/last segments) is applied here.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import StrEnum

from clew.transcription.models import TranscriptResult


class EvidenceKind(StrEnum):
    SELF_INTRO = "self_intro"
    VOCATIVE = "vocative"
    THIRD_PERSON_ABSENT = "third_person_absent"
    MIC_PRESENCE = "mic_presence"


@dataclass(frozen=True)
class Evidence:
    """One deterministic observation from the transcript.

    speaker_cluster: the cluster this evidence supports as BEING `name` (positive).
    excluded_cluster: the cluster this evidence proves is NOT `name` (negative --
    a vocative's own speaker can't be who they're addressing).
    location is (start, end) in seconds, never transcript text -- the table is not
    a place to retain quoted content.
    """

    kind: EvidenceKind
    name: str
    speaker_cluster: str | None
    excluded_cluster: str | None
    start: float
    end: float
    weight: float


@dataclass
class EvidenceTable:
    evidence: list[Evidence] = field(default_factory=list)

    def for_name(self, name: str) -> list[Evidence]:
        return [e for e in self.evidence if e.name == name]


_BASE_WEIGHT = 1.0

# Words that can be capitalized mid-sentence without being a name -- guards the
# "I'm X" / "My name is X" patterns against the false positives ASR emits when a
# sentence-initial capital rides through ("I'm Sorry", "I'm Not sure"). Kept small
# and structural, not an attempt at an exhaustive lexicon.
_SELF_INTRO_FALSE_POSITIVES = frozenset(
    {
        "sorry",
        "not",
        "sure",
        "here",
        "afraid",
        "glad",
        "happy",
        "fine",
        "okay",
        "ok",
        "ready",
        "going",
        "trying",
        "back",
        "done",
        "late",
        "early",
    }
)

_NAME_TOKEN = r"[A-ZÀ-Ý][\wÀ-ÿ'-]*"

_SELF_INTRO_PATTERNS = [
    re.compile(rf"\bmoi,?\s+c'est\s+(?P<name>{_NAME_TOKEN})", re.IGNORECASE),
    re.compile(rf"\bje\s+m'appelle\s+(?P<name>{_NAME_TOKEN})", re.IGNORECASE),
    re.compile(rf"\bmy\s+name\s+is\s+(?P<name>{_NAME_TOKEN})", re.IGNORECASE),
    re.compile(rf"\bI'?m\s+(?P<name>{_NAME_TOKEN})\b"),
]


def extract_self_intro_evidence(transcript: TranscriptResult) -> list[Evidence]:
    """A speaker naming themselves is positive evidence: speaker_cluster == name."""
    evidence: list[Evidence] = []
    for seg in transcript.segments:
        for pattern in _SELF_INTRO_PATTERNS:
            for match in pattern.finditer(seg.text):
                name = match.group("name")
                if name.lower() in _SELF_INTRO_FALSE_POSITIVES:
                    continue
                evidence.append(
                    Evidence(
                        kind=EvidenceKind.SELF_INTRO,
                        name=name,
                        speaker_cluster=seg.speaker,
                        excluded_cluster=None,
                        start=seg.start,
                        end=seg.end,
                        weight=_BASE_WEIGHT,
                    )
                )
    return evidence


_VOCATIVE_ANCHOR_PATTERNS = [
    re.compile(rf"\b(?:merci|thanks|thank\s+you),?\s+(?P<name>{_NAME_TOKEN})\b", re.IGNORECASE),
]
_VOCATIVE_LEADING_PATTERN = re.compile(rf"^(?P<name>{_NAME_TOKEN}),\s")
_VOCATIVE_TRAILING_PATTERN = re.compile(rf",\s+(?P<name>{_NAME_TOKEN})[.!?]?\s*$")

# The leading/trailing structural patterns key off "capitalized token next to a
# comma" alone, so the anchor interjections themselves (sentence-initial "Thanks,"
# or "Merci,") get caught as false name candidates -- excluded here rather than
# relying on the anchor patterns to consume them first, since match order isn't set.
_VOCATIVE_STOPWORDS = frozenset(
    {"merci", "thanks", "thank", "ok", "okay", "so", "well", "alors", "donc", "bref", "voila", "voilà", "bon"}
)


def extract_vocative_evidence(transcript: TranscriptResult) -> list[Evidence]:
    """Addressing someone by name is negative evidence for the SPEAKER: excludes
    excluded_cluster == speaker.speaker, never assigns a positive cluster -- per
    the design's own caution, vocatives EXCLUDE, they never directly SUGGEST."""
    evidence: list[Evidence] = []
    for seg in transcript.segments:
        names: list[str] = []
        for pattern in _VOCATIVE_ANCHOR_PATTERNS:
            names.extend(m.group("name") for m in pattern.finditer(seg.text))
        for pattern in (_VOCATIVE_LEADING_PATTERN, _VOCATIVE_TRAILING_PATTERN):
            m = pattern.search(seg.text.strip())
            if m:
                names.append(m.group("name"))

        seen: set[str] = set()
        for name in names:
            if name.lower() in _VOCATIVE_STOPWORDS or name.lower() in seen:
                continue
            seen.add(name.lower())
            evidence.append(
                Evidence(
                    kind=EvidenceKind.VOCATIVE,
                    name=name,
                    speaker_cluster=None,
                    excluded_cluster=seg.speaker,
                    start=seg.start,
                    end=seg.end,
                    weight=_BASE_WEIGHT,
                )
            )
    return evidence
