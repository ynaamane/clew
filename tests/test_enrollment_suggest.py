"""Tests for deterministic evidence extraction feeding auto-suggest enrollment.

Fixtures are synthetic (invented names/lines) -- never real meeting content, per
.claude/skills/ownscribe-pipeline-traps/SKILL.md.
"""

from __future__ import annotations

from clew.speakers.enrollment_suggest import (
    Evidence,
    EvidenceKind,
    EvidenceTable,
    extract_self_intro_evidence,
    extract_vocative_evidence,
)
from clew.transcription.models import Segment, TranscriptResult


def _segment(text: str, speaker: str, start: float = 0.0, end: float = 2.0) -> Segment:
    return Segment(text=text, start=start, end=end, speaker=speaker)


class TestEvidenceTable:
    def test_empty_table_has_no_evidence(self):
        table = EvidenceTable()
        assert table.evidence == []

    def test_for_name_filters_by_name(self):
        e1 = Evidence(
            kind=EvidenceKind.SELF_INTRO,
            name="Devon",
            speaker_cluster="SPEAKER_00",
            excluded_cluster=None,
            start=0.0,
            end=1.0,
            weight=1.0,
        )
        e2 = Evidence(
            kind=EvidenceKind.SELF_INTRO,
            name="Kamal",
            speaker_cluster="SPEAKER_01",
            excluded_cluster=None,
            start=1.0,
            end=2.0,
            weight=1.0,
        )
        table = EvidenceTable(evidence=[e1, e2])
        assert table.for_name("Devon") == [e1]
        assert table.for_name("Nobody") == []


class TestExtractSelfIntroEvidence:
    def test_moi_cest_extracts_name_for_speaker(self):
        result = TranscriptResult(segments=[_segment("Moi c'est Devon, je gere le pipeline.", "SPEAKER_00")])
        evidence = extract_self_intro_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].kind == EvidenceKind.SELF_INTRO
        assert evidence[0].name == "Devon"
        assert evidence[0].speaker_cluster == "SPEAKER_00"
        assert evidence[0].excluded_cluster is None

    def test_je_mappelle_extracts_name(self):
        result = TranscriptResult(segments=[_segment("Bonjour, je m'appelle Kamal.", "SPEAKER_01")])
        evidence = extract_self_intro_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].name == "Kamal"
        assert evidence[0].speaker_cluster == "SPEAKER_01"

    def test_im_extracts_name(self):
        result = TranscriptResult(segments=[_segment("Hey, I'm Sarah from the design team.", "SPEAKER_02")])
        evidence = extract_self_intro_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].name == "Sarah"

    def test_my_name_is_extracts_name(self):
        result = TranscriptResult(segments=[_segment("My name is Marcus, I work on backend.", "SPEAKER_03")])
        evidence = extract_self_intro_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].name == "Marcus"

    def test_im_followed_by_common_word_is_not_a_name(self):
        result = TranscriptResult(segments=[_segment("I'm Sorry, I missed that part.", "SPEAKER_00")])
        evidence = extract_self_intro_evidence(result)
        assert evidence == []

    def test_segment_without_self_intro_yields_nothing(self):
        result = TranscriptResult(segments=[_segment("We should ship this by Friday.", "SPEAKER_00")])
        assert extract_self_intro_evidence(result) == []

    def test_location_matches_segment_span(self):
        result = TranscriptResult(segments=[_segment("Moi c'est Devon.", "SPEAKER_00", start=12.0, end=14.5)])
        evidence = extract_self_intro_evidence(result)
        assert evidence[0].start == 12.0
        assert evidence[0].end == 14.5

    def test_multiple_segments_each_contribute_evidence(self):
        result = TranscriptResult(
            segments=[
                _segment("Moi c'est Devon.", "SPEAKER_00", start=0.0, end=1.0),
                _segment("Ok, et moi c'est Kamal.", "SPEAKER_01", start=1.0, end=2.0),
            ]
        )
        evidence = extract_self_intro_evidence(result)
        assert {(e.name, e.speaker_cluster) for e in evidence} == {
            ("Devon", "SPEAKER_00"),
            ("Kamal", "SPEAKER_01"),
        }


class TestExtractVocativeEvidence:
    def test_merci_name_excludes_speaker(self):
        result = TranscriptResult(segments=[_segment("Merci Kamal pour la review.", "SPEAKER_00")])
        evidence = extract_vocative_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].kind == EvidenceKind.VOCATIVE
        assert evidence[0].name == "Kamal"
        assert evidence[0].excluded_cluster == "SPEAKER_00"
        assert evidence[0].speaker_cluster is None

    def test_thanks_name_excludes_speaker(self):
        result = TranscriptResult(segments=[_segment("Thanks, Sarah, that helps a lot.", "SPEAKER_02")])
        evidence = extract_vocative_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].name == "Sarah"
        assert evidence[0].excluded_cluster == "SPEAKER_02"

    def test_name_comma_at_start_excludes_speaker(self):
        result = TranscriptResult(segments=[_segment("Devon, tu peux relancer le build ?", "SPEAKER_01")])
        evidence = extract_vocative_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].name == "Devon"
        assert evidence[0].excluded_cluster == "SPEAKER_01"

    def test_comma_name_at_end_excludes_speaker(self):
        result = TranscriptResult(
            segments=[_segment("On peut le faire ensemble, Marcus.", "SPEAKER_00", start=5.0, end=7.0)]
        )
        evidence = extract_vocative_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].name == "Marcus"
        assert evidence[0].excluded_cluster == "SPEAKER_00"

    def test_speaker_never_excluded_from_own_unaddressed_speech(self):
        result = TranscriptResult(segments=[_segment("We should ship this by Friday.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_vocative_never_assigns_a_positive_cluster(self):
        result = TranscriptResult(segments=[_segment("Merci Kamal pour la review.", "SPEAKER_00")])
        evidence = extract_vocative_evidence(result)
        assert all(e.speaker_cluster is None for e in evidence)
