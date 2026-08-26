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

import json
import re
from dataclasses import dataclass, field, replace
from enum import StrEnum

from clew.summarization.base import Summarizer
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
    name is None for evidence that has no resolved name (mic_presence in this
    tranche) -- never a fabricated placeholder string, absence must stay absence.
    location is (start, end) in seconds, never transcript text -- the table is not
    a place to retain quoted content.
    """

    kind: EvidenceKind
    name: str | None
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


def _mentions_name(text: str, name: str) -> bool:
    return re.search(rf"\b{re.escape(name)}\b", text, re.IGNORECASE) is not None


def extract_third_person_absent_evidence(
    transcript: TranscriptResult,
    roster: list[str],
    self_intro_evidence: list[Evidence] | None = None,
    vocative_evidence: list[Evidence] | None = None,
) -> list[Evidence]:
    """A roster name that is only ever talked ABOUT -- never self-identified, never
    addressed directly -- is evidence that person is not in the room. Scoped to the
    roster on purpose: without a candidate name to look for, "is this capitalized
    word a name" has no structural answer (tranche-1 simplification).

    self_intro_evidence/vocative_evidence let a caller building the full table
    (build_evidence_table) reuse its own extraction pass instead of re-running it,
    so third-person-absence stays consistent with the self-intro/vocative view of
    the SAME transcript rather than silently drifting from it.
    """
    if self_intro_evidence is None:
        self_intro_evidence = extract_self_intro_evidence(transcript)
    if vocative_evidence is None:
        vocative_evidence = extract_vocative_evidence(transcript)

    self_intro_names = {e.name.lower() for e in self_intro_evidence if e.name is not None}
    vocative_names = {e.name.lower() for e in vocative_evidence if e.name is not None}

    evidence: list[Evidence] = []
    for name in roster:
        key = name.lower()
        if key in self_intro_names or key in vocative_names:
            continue
        for seg in transcript.segments:
            if _mentions_name(seg.text, name):
                evidence.append(
                    Evidence(
                        kind=EvidenceKind.THIRD_PERSON_ABSENT,
                        name=name,
                        speaker_cluster=None,
                        excluded_cluster=None,
                        start=seg.start,
                        end=seg.end,
                        weight=_BASE_WEIGHT,
                    )
                )
    return evidence


_MIC_TRACK_SPEAKER = "Owner"


def extract_mic_presence_evidence(transcript: TranscriptResult) -> list[Evidence]:
    """Structural-only for this tranche: the dual-track pipeline already tags the
    mic track's speaker as "Owner" (pipeline.py:_tag_speaker) whenever it carries
    real content, which is a free physical-presence signal. It resolves no NAME --
    config has no Owner-to-name mapping today, and the real cosine mic<->cluster
    signal belongs to matching.py (tranche 2, after VoiceprintDB multi-sample
    lands there). Never fabricate a name binding this tranche can't support."""
    evidence: list[Evidence] = []
    for seg in transcript.segments:
        if seg.speaker == _MIC_TRACK_SPEAKER and seg.text.strip():
            evidence.append(
                Evidence(
                    kind=EvidenceKind.MIC_PRESENCE,
                    name=None,
                    speaker_cluster=_MIC_TRACK_SPEAKER,
                    excluded_cluster=None,
                    start=seg.start,
                    end=seg.end,
                    weight=_BASE_WEIGHT,
                )
            )
    return evidence


# Both empirically-motivated by the design's own finding (TODO.md, 2026-08-03 call):
# the two contradictory identity clues in that meeting were the literal first and
# last lines of the recording, where diarization mis-attributes most. N=1-calibrated
# like the hallucination list/RMS threshold elsewhere in this repo -- revisit as more
# meetings accumulate. Overlap-ZONE downweighting is separate and NOT implemented
# here; see the module docstring.
_BOUNDARY_FRACTION = 0.05
_BOUNDARY_DOWNWEIGHT = 0.5


def _boundary_weight(start: float, end: float, duration: float, base_weight: float) -> float:
    if duration <= 0:
        return base_weight
    midpoint = (start + end) / 2
    if midpoint <= duration * _BOUNDARY_FRACTION or midpoint >= duration * (1 - _BOUNDARY_FRACTION):
        return base_weight * _BOUNDARY_DOWNWEIGHT
    return base_weight


def build_evidence_table(transcript: TranscriptResult, roster: list[str]) -> EvidenceTable:
    """Run every deterministic extractor over one transcript and combine the
    results into a single, boundary-downweighted table -- the only input the LLM
    arbiter (tranche 1's next commit) ever sees."""
    self_intro = extract_self_intro_evidence(transcript)
    vocative = extract_vocative_evidence(transcript)
    third_person_absent = extract_third_person_absent_evidence(
        transcript, roster, self_intro_evidence=self_intro, vocative_evidence=vocative
    )
    mic_presence = extract_mic_presence_evidence(transcript)

    all_evidence = [
        replace(e, weight=_boundary_weight(e.start, e.end, transcript.duration, e.weight))
        for e in (*self_intro, *vocative, *third_person_absent, *mic_presence)
    ]
    return EvidenceTable(evidence=all_evidence)


@dataclass(frozen=True)
class CandidateMapping:
    """A (cluster, name) pair that has already passed the hard gate below --
    the only shape suggest_enrollments is allowed to hand the LLM."""

    cluster: str
    name: str
    evidence: list[Evidence]


_MIN_INDEPENDENT_EVIDENCE = 2


def _is_excluded(table: EvidenceTable, cluster: str, name: str) -> bool:
    key = name.lower()
    return any(
        e.kind == EvidenceKind.VOCATIVE
        and e.name is not None
        and e.name.lower() == key
        and e.excluded_cluster == cluster
        for e in table.evidence
    )


def gate_candidate_mappings(table: EvidenceTable) -> list[CandidateMapping]:
    """The hard gate: enforced in Python, never delegated to the LLM. Self-intro
    is the only positive-evidence kind in this tranche, so candidates are built by
    grouping it by (cluster, name); a pair a vocative excludes is dropped before
    it ever becomes a candidate; a pair needs >=2 self-intro rows at DISTINCT
    (start, end) locations -- duplicate rows at the same timestamp are one
    observation, not independent corroboration ("jamais de proposition a
    evidence unique")."""
    grouped: dict[tuple[str, str], list[Evidence]] = {}
    for e in table.evidence:
        if e.kind != EvidenceKind.SELF_INTRO or e.name is None or e.speaker_cluster is None:
            continue
        grouped.setdefault((e.speaker_cluster, e.name), []).append(e)

    candidates: list[CandidateMapping] = []
    for (cluster, name), rows in grouped.items():
        if _is_excluded(table, cluster, name):
            continue
        distinct_locations = {(r.start, r.end) for r in rows}
        if len(distinct_locations) < _MIN_INDEPENDENT_EVIDENCE:
            continue
        candidates.append(CandidateMapping(cluster=cluster, name=name, evidence=rows))
    return candidates


@dataclass(frozen=True)
class Suggestion:
    cluster: str
    name: str
    evidence: list[Evidence]
    confidence: str


_DEFAULT_CONFIDENCE = "medium"

_ARBITER_SYSTEM = (
    "You arbitrate speaker-name suggestions for a meeting transcript using ONLY the "
    "candidate list given to you -- never invent a candidate, never reason from anything "
    "outside this list. Each candidate already passed a hard rule (at least two "
    "independent self-introductions, no contradicting address-evidence), so your job is "
    "only to confirm or reject it and give a confidence level. Reject a candidate if the "
    "name looks like a joke, a nickname unlikely to be a real enrollment name, or is "
    "otherwise implausible. You MUST only reference cluster/name pairs from the candidate "
    "list -- never propose a pair that isn't listed."
)

_ARBITER_PROMPT = """Known roster: {roster}

Candidates:
{candidates}

Return ONLY valid JSON: {{"confirmed": [{{"cluster": "...", "name": "...", "confidence": "high"|"medium"}}]}}"""

_ARBITER_SCHEMA = {
    "name": "enrollment_suggestions",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "confirmed": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "cluster": {"type": "string"},
                        "name": {"type": "string"},
                        "confidence": {"type": "string"},
                    },
                    "required": ["cluster", "name"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["confirmed"],
        "additionalProperties": False,
    },
}


def _format_candidates_for_prompt(candidates: list[CandidateMapping]) -> str:
    lines = []
    for c in candidates:
        count = len({(e.start, e.end) for e in c.evidence})
        lines.append(f"- cluster={c.cluster} name={c.name} independent_evidence_count={count}")
    return "\n".join(lines)


def _parse_arbiter_response(response: str) -> list[dict]:
    try:
        data = json.loads(response)
    except (json.JSONDecodeError, TypeError):
        return []
    if not isinstance(data, dict):
        return []
    confirmed = data.get("confirmed")
    if not isinstance(confirmed, list):
        return []
    return [item for item in confirmed if isinstance(item, dict) and "cluster" in item and "name" in item]


def suggest_enrollments(table: EvidenceTable, summarizer: Summarizer, roster: list[str]) -> list[Suggestion]:
    """LLM arbiter over the GATED evidence table -- never the raw transcript, never
    auto-enrolls. gate_candidate_mappings() enforces the hard >=2-independent-
    evidence rule and the vocative-exclusion constraint BEFORE the LLM ever runs;
    the LLM's response is cross-checked against that same candidate list
    afterward -- at neither end can the model manufacture a suggestion the gate
    didn't already allow."""
    candidates = gate_candidate_mappings(table)
    if not candidates:
        return []

    prompt = _ARBITER_PROMPT.format(
        roster=", ".join(roster) if roster else "(none enrolled yet)",
        candidates=_format_candidates_for_prompt(candidates),
    )
    response = summarizer.chat(_ARBITER_SYSTEM, prompt, json_mode=True, json_schema=_ARBITER_SCHEMA)
    confirmed = _parse_arbiter_response(response)

    candidate_by_key = {(c.cluster, c.name): c for c in candidates}
    suggestions: list[Suggestion] = []
    for item in confirmed:
        candidate = candidate_by_key.get((item.get("cluster"), item.get("name")))
        if candidate is None:
            continue  # not in the gated candidate list -- never trust the LLM's echo
        suggestions.append(
            Suggestion(
                cluster=candidate.cluster,
                name=candidate.name,
                evidence=candidate.evidence,
                confidence=item.get("confidence") or _DEFAULT_CONFIDENCE,
            )
        )
    return suggestions
