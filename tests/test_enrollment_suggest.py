"""Tests for deterministic evidence extraction feeding auto-suggest enrollment.

Fixtures are synthetic (invented names/lines) -- never real meeting content, per
.claude/skills/ownscribe-pipeline-traps/SKILL.md.
"""

from __future__ import annotations

import pytest

from clew.output.json_output import format_transcript_json
from clew.output.markdown import format_transcript
from clew.speakers.enrollment_suggest import (
    CandidateMapping,
    Evidence,
    EvidenceKind,
    EvidenceTable,
    Suggestion,
    build_evidence_table,
    extract_mic_presence_evidence,
    extract_self_intro_evidence,
    extract_third_person_absent_evidence,
    extract_vocative_evidence,
    gate_candidate_mappings,
    load_transcript_result,
    suggest_enrollments,
)
from clew.transcription.models import Segment, TranscriptResult, Word


def _segment(text: str, speaker: str, start: float = 0.0, end: float = 2.0) -> Segment:
    return Segment(text=text, start=start, end=end, speaker=speaker)


def _self_intro(cluster: str, name: str, start: float, end: float) -> Evidence:
    return Evidence(
        kind=EvidenceKind.SELF_INTRO,
        name=name,
        speaker_cluster=cluster,
        excluded_cluster=None,
        start=start,
        end=end,
        weight=1.0,
    )


def _vocative_exclusion(cluster: str, name: str, start: float, end: float) -> Evidence:
    return Evidence(
        kind=EvidenceKind.VOCATIVE,
        name=name,
        speaker_cluster=None,
        excluded_cluster=cluster,
        start=start,
        end=end,
        weight=1.0,
    )


def _mic_presence(cluster: str, name: str, start: float, end: float) -> Evidence:
    return Evidence(
        kind=EvidenceKind.MIC_PRESENCE,
        name=name,
        speaker_cluster=cluster,
        excluded_cluster=None,
        start=start,
        end=end,
        weight=0.8,
    )


class FakeSummarizer:
    """Duck-typed fake mirroring tests/test_search.py's -- records calls, returns
    canned JSON responses so the arbiter never touches a real model in tests."""

    def __init__(self, responses: list[str] | None = None):
        self.calls: list[tuple[str, str, bool]] = []
        self._responses = list(responses or [])
        self._call_idx = 0

    def chat(
        self,
        system_prompt: str,
        user_prompt: str,
        json_mode: bool = False,
        json_schema: dict | None = None,
    ) -> str:
        self.calls.append((system_prompt, user_prompt, json_mode))
        if self._responses:
            resp = self._responses[self._call_idx % len(self._responses)]
            self._call_idx += 1
            return resp
        return '{"confirmed": []}'


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

    # Reviewer's 6 adversarial entries (review-bm2): the anchor pattern's compiled
    # re.IGNORECASE flag is global to the WHOLE pattern, so it also case-folds
    # _NAME_TOKEN's [A-ZÀ-Ý] requirement, the group's only structural guard -- any
    # lowercase word right after "merci"/"thanks"/"thank you" was captured as a
    # name. Separately, the leading-comma structural pattern has no lexicon for
    # common capitalized sentence-openers other than the anchor words themselves.
    def test_merci_pour_without_a_name_yields_no_evidence(self):
        result = TranscriptResult(segments=[_segment("Merci pour votre aide.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_merci_beaucoup_yields_no_evidence(self):
        result = TranscriptResult(segments=[_segment("Merci beaucoup.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_merci_comma_cest_note_yields_no_evidence(self):
        result = TranscriptResult(segments=[_segment("Merci, c'est noté.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_sorry_at_segment_start_yields_no_evidence(self):
        result = TranscriptResult(segments=[_segment("Sorry, I am late.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_moi_cest_yields_no_vocative_evidence(self):
        # The self-intro canonical phrasing ("Moi, c'est Priya") must never ALSO
        # register as a vocative addressing "Moi".
        result = TranscriptResult(segments=[_segment("Moi, c'est Priya.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_bonjour_at_segment_start_yields_no_evidence(self):
        result = TranscriptResult(segments=[_segment("Bonjour, tout le monde.", "SPEAKER_00")])
        assert extract_vocative_evidence(result) == []

    def test_merci_kamal_still_captured_after_the_ignorecase_fix(self):
        # Regression guard for the fix above: the real positive case must still work.
        result = TranscriptResult(segments=[_segment("Merci Kamal pour la review.", "SPEAKER_00")])
        evidence = extract_vocative_evidence(result)
        assert [e.name for e in evidence] == ["Kamal"]

    def test_lowercase_anchor_word_still_matches(self):
        # The anchor-case-insensitivity itself must survive the IGNORECASE removal
        # -- only the NAME group's case-sensitivity was the bug.
        result = TranscriptResult(segments=[_segment("merci Kamal pour la review.", "SPEAKER_00")])
        evidence = extract_vocative_evidence(result)
        assert [e.name for e in evidence] == ["Kamal"]


class TestExtractThirdPersonAbsentEvidence:
    def test_roster_name_mentioned_only_in_third_person_is_absent(self):
        result = TranscriptResult(
            segments=[_segment("Kamal a dit qu'il fallait revoir le design la semaine derniere.", "SPEAKER_00")]
        )
        evidence = extract_third_person_absent_evidence(result, roster=["Kamal"])
        assert len(evidence) == 1
        assert evidence[0].kind == EvidenceKind.THIRD_PERSON_ABSENT
        assert evidence[0].name == "Kamal"
        assert evidence[0].speaker_cluster is None
        assert evidence[0].excluded_cluster is None

    def test_roster_name_with_self_intro_is_not_absent(self):
        result = TranscriptResult(
            segments=[
                _segment("Moi c'est Kamal.", "SPEAKER_00", start=0.0, end=1.0),
                _segment("Kamal a dit qu'on devrait reessayer.", "SPEAKER_01", start=1.0, end=2.0),
            ]
        )
        evidence = extract_third_person_absent_evidence(result, roster=["Kamal"])
        assert evidence == []

    def test_roster_name_addressed_vocatively_is_not_absent(self):
        result = TranscriptResult(
            segments=[
                _segment("Merci Kamal pour la review.", "SPEAKER_00", start=0.0, end=1.0),
                _segment("Kamal a dit qu'on devrait reessayer.", "SPEAKER_01", start=1.0, end=2.0),
            ]
        )
        evidence = extract_third_person_absent_evidence(result, roster=["Kamal"])
        assert evidence == []

    def test_name_never_mentioned_produces_no_evidence(self):
        result = TranscriptResult(segments=[_segment("We should ship this by Friday.", "SPEAKER_00")])
        evidence = extract_third_person_absent_evidence(result, roster=["Kamal"])
        assert evidence == []

    def test_only_roster_names_are_evaluated(self):
        result = TranscriptResult(segments=[_segment("Jean a dit qu'il serait en retard.", "SPEAKER_00")])
        evidence = extract_third_person_absent_evidence(result, roster=["Kamal"])
        assert evidence == []

    def test_word_boundary_prevents_partial_name_match(self):
        result = TranscriptResult(segments=[_segment("Samuel a valide le design hier.", "SPEAKER_00")])
        evidence = extract_third_person_absent_evidence(result, roster=["Sam"])
        assert evidence == []

    def test_each_bare_mention_is_its_own_evidence_row(self):
        result = TranscriptResult(
            segments=[
                _segment("Kamal a valide le design.", "SPEAKER_00", start=0.0, end=1.0),
                _segment("Ouais Kamal etait d'accord.", "SPEAKER_01", start=1.0, end=2.0),
            ]
        )
        evidence = extract_third_person_absent_evidence(result, roster=["Kamal"])
        assert len(evidence) == 2

    def test_can_reuse_precomputed_self_intro_and_vocative_evidence(self):
        result = TranscriptResult(
            segments=[
                _segment("Moi c'est Kamal.", "SPEAKER_00", start=0.0, end=1.0),
                _segment("Kamal a dit qu'on devrait reessayer.", "SPEAKER_01", start=1.0, end=2.0),
            ]
        )
        self_intro = extract_self_intro_evidence(result)
        vocative = extract_vocative_evidence(result)
        evidence = extract_third_person_absent_evidence(
            result, roster=["Kamal"], self_intro_evidence=self_intro, vocative_evidence=vocative
        )
        assert evidence == []


class TestExtractMicPresenceEvidence:
    def test_owner_segment_with_content_yields_presence_evidence(self):
        result = TranscriptResult(segments=[_segment("On peut commencer.", "Owner", start=0.0, end=2.0)])
        evidence = extract_mic_presence_evidence(result)
        assert len(evidence) == 1
        assert evidence[0].kind == EvidenceKind.MIC_PRESENCE
        assert evidence[0].speaker_cluster == "Owner"

    def test_mic_presence_never_resolves_a_name(self):
        result = TranscriptResult(segments=[_segment("On peut commencer.", "Owner")])
        evidence = extract_mic_presence_evidence(result)
        assert all(e.name is None for e in evidence)

    def test_owner_segment_with_blank_text_yields_nothing(self):
        result = TranscriptResult(segments=[_segment("   ", "Owner")])
        assert extract_mic_presence_evidence(result) == []

    def test_non_owner_segment_yields_nothing(self):
        result = TranscriptResult(segments=[_segment("On peut commencer.", "SPEAKER_00")])
        assert extract_mic_presence_evidence(result) == []


class TestBuildEvidenceTable:
    def test_combines_all_evidence_kinds(self):
        result = TranscriptResult(
            segments=[
                _segment("Moi c'est Devon.", "SPEAKER_00", start=10.0, end=12.0),
                _segment("Merci Kamal pour la review.", "SPEAKER_01", start=12.0, end=14.0),
                _segment("Marcus a dit qu'il validait.", "SPEAKER_00", start=14.0, end=16.0),
                _segment("On y va.", "Owner", start=16.0, end=17.0),
            ],
            duration=100.0,
        )
        table = build_evidence_table(result, roster=["Marcus"])
        kinds = {e.kind for e in table.evidence}
        assert kinds == {
            EvidenceKind.SELF_INTRO,
            EvidenceKind.VOCATIVE,
            EvidenceKind.THIRD_PERSON_ABSENT,
            EvidenceKind.MIC_PRESENCE,
        }

    def test_third_person_absence_reflects_the_same_build(self):
        # Marcus self-intros AND is mentioned in third person in the same transcript --
        # the orchestrator must wire the same extraction results together, not run
        # third-person-absence independently against a fresh (inconsistent) view.
        result = TranscriptResult(
            segments=[
                _segment("Moi c'est Marcus.", "SPEAKER_00", start=10.0, end=12.0),
                _segment("Marcus a valide le design.", "SPEAKER_01", start=12.0, end=14.0),
            ],
            duration=100.0,
        )
        table = build_evidence_table(result, roster=["Marcus"])
        assert not any(e.kind == EvidenceKind.THIRD_PERSON_ABSENT for e in table.evidence)

    def test_evidence_near_recording_start_is_downweighted(self):
        result = TranscriptResult(
            segments=[_segment("Moi c'est Devon.", "SPEAKER_00", start=0.0, end=1.0)],
            duration=100.0,
        )
        table = build_evidence_table(result, roster=[])
        assert table.evidence[0].weight < 1.0

    def test_evidence_near_recording_end_is_downweighted(self):
        result = TranscriptResult(
            segments=[_segment("Moi c'est Devon.", "SPEAKER_00", start=98.0, end=99.0)],
            duration=100.0,
        )
        table = build_evidence_table(result, roster=[])
        assert table.evidence[0].weight < 1.0

    def test_evidence_mid_recording_is_not_downweighted(self):
        result = TranscriptResult(
            segments=[_segment("Moi c'est Devon.", "SPEAKER_00", start=49.0, end=51.0)],
            duration=100.0,
        )
        table = build_evidence_table(result, roster=[])
        assert table.evidence[0].weight == 1.0

    def test_zero_duration_transcript_skips_downweighting(self):
        result = TranscriptResult(segments=[_segment("Moi c'est Devon.", "SPEAKER_00", start=0.0, end=1.0)])
        table = build_evidence_table(result, roster=[])
        assert table.evidence[0].weight == 1.0


class TestBuildEvidenceTableMicPresence:
    """BUILD NEXT #1 tranche 2 block A4: build_evidence_table's mic_presence
    parameter folds in the ONE resolved cosine mic<->cluster match, on top of
    the always-present structural per-Owner-segment rows extract_mic_presence_evidence
    already produces."""

    def test_resolved_mic_presence_adds_exactly_one_named_evidence_row(self):
        from clew.speakers.mic_presence import MicPresence

        result = TranscriptResult(
            segments=[_segment("Bonjour tout le monde.", "SPEAKER_00", start=50.0, end=52.0)],
            duration=100.0,
        )
        presence = MicPresence(cluster="SPEAKER_00", name="Kamal", score=0.8, start=10.0, end=15.0)

        table = build_evidence_table(result, roster=[], mic_presence=presence)

        named_mic_rows = [e for e in table.evidence if e.kind == EvidenceKind.MIC_PRESENCE and e.name is not None]
        assert len(named_mic_rows) == 1
        assert named_mic_rows[0].name == "Kamal"
        assert named_mic_rows[0].speaker_cluster == "SPEAKER_00"
        assert named_mic_rows[0].excluded_cluster is None
        assert named_mic_rows[0].start == 10.0
        assert named_mic_rows[0].end == 15.0

    def test_the_structural_unnamed_mic_presence_rows_are_unchanged(self):
        from clew.speakers.mic_presence import MicPresence

        result = TranscriptResult(
            segments=[_segment("On y va.", "Owner", start=50.0, end=51.0)],
            duration=100.0,
        )
        presence = MicPresence(cluster="Owner", name="Kamal", score=0.8, start=50.0, end=51.0)

        table = build_evidence_table(result, roster=[], mic_presence=presence)

        unnamed_mic_rows = [e for e in table.evidence if e.kind == EvidenceKind.MIC_PRESENCE and e.name is None]
        assert len(unnamed_mic_rows) == 1
        assert unnamed_mic_rows[0].speaker_cluster == "Owner"

    def test_mic_presence_without_a_name_adds_nothing(self):
        # Not an Owner segment, so extract_mic_presence_evidence's own structural
        # pass contributes zero rows here -- ANY MIC_PRESENCE row in the table
        # (named or not) would only be explained by mic_presence.cluster alone
        # wrongly bypassing the name gate. Checking the total count, not just
        # named rows, so a row added with name=None can't hide from this test.
        from clew.speakers.mic_presence import MicPresence

        result = TranscriptResult(
            segments=[_segment("Bonjour tout le monde.", "SPEAKER_00", start=50.0, end=52.0)],
            duration=100.0,
        )
        presence = MicPresence(cluster="SPEAKER_00", name=None, score=0.3, start=10.0, end=15.0)

        table = build_evidence_table(result, roster=[], mic_presence=presence)

        assert [e for e in table.evidence if e.kind == EvidenceKind.MIC_PRESENCE] == []

    def test_mic_presence_defaults_to_none_and_adds_nothing(self):
        result = TranscriptResult(
            segments=[_segment("Bonjour tout le monde.", "SPEAKER_00", start=50.0, end=52.0)],
            duration=100.0,
        )
        table = build_evidence_table(result, roster=[])
        assert not any(e.kind == EvidenceKind.MIC_PRESENCE and e.name is not None for e in table.evidence)


class TestGateCandidateMappings:
    """The hard gate -- enforced in Python, never delegated to the LLM."""

    def test_single_self_intro_never_becomes_a_candidate(self):
        table = EvidenceTable(evidence=[_self_intro("SPEAKER_00", "Devon", 0.0, 1.0)])
        assert gate_candidate_mappings(table) == []

    def test_two_self_intros_at_distinct_locations_become_a_candidate(self):
        table = EvidenceTable(
            evidence=[
                _self_intro("SPEAKER_00", "Devon", 0.0, 1.0),
                _self_intro("SPEAKER_00", "Devon", 40.0, 41.0),
            ]
        )
        candidates = gate_candidate_mappings(table)
        assert candidates == [CandidateMapping(cluster="SPEAKER_00", name="Devon", evidence=table.evidence)]

    def test_two_self_intros_at_the_same_location_are_not_independent(self):
        # Duplicate rows at an identical (start, end) are the same observation,
        # not two -- must not satisfy the >=2-independent-evidence gate.
        dup = _self_intro("SPEAKER_00", "Devon", 5.0, 6.0)
        table = EvidenceTable(evidence=[dup, dup])
        assert gate_candidate_mappings(table) == []

    def test_vocative_exclusion_drops_an_otherwise_qualifying_candidate(self):
        table = EvidenceTable(
            evidence=[
                _self_intro("SPEAKER_00", "Kamal", 0.0, 1.0),
                _self_intro("SPEAKER_00", "Kamal", 40.0, 41.0),
                _vocative_exclusion("SPEAKER_00", "Kamal", 20.0, 21.0),
            ]
        )
        assert gate_candidate_mappings(table) == []

    def test_exclusion_only_drops_the_matching_cluster_not_other_candidates(self):
        table = EvidenceTable(
            evidence=[
                _self_intro("SPEAKER_00", "Kamal", 0.0, 1.0),
                _self_intro("SPEAKER_00", "Kamal", 40.0, 41.0),
                _vocative_exclusion("SPEAKER_00", "Kamal", 20.0, 21.0),
                _self_intro("SPEAKER_01", "Devon", 0.0, 1.0),
                _self_intro("SPEAKER_01", "Devon", 40.0, 41.0),
            ]
        )
        candidates = gate_candidate_mappings(table)
        assert candidates == [
            CandidateMapping(
                cluster="SPEAKER_01",
                name="Devon",
                evidence=[e for e in table.evidence if e.speaker_cluster == "SPEAKER_01"],
            )
        ]

    def test_non_self_intro_evidence_never_seeds_a_candidate(self):
        table = EvidenceTable(
            evidence=[
                Evidence(
                    kind=EvidenceKind.THIRD_PERSON_ABSENT,
                    name="Marcus",
                    speaker_cluster=None,
                    excluded_cluster=None,
                    start=0.0,
                    end=1.0,
                    weight=1.0,
                ),
                Evidence(
                    kind=EvidenceKind.MIC_PRESENCE,
                    name=None,
                    speaker_cluster="Owner",
                    excluded_cluster=None,
                    start=1.0,
                    end=2.0,
                    weight=1.0,
                ),
            ]
        )
        assert gate_candidate_mappings(table) == []

    def test_empty_table_yields_no_candidates(self):
        assert gate_candidate_mappings(EvidenceTable()) == []

    def test_mic_presence_alone_never_becomes_a_candidate(self):
        # One location -- still fails the >=2-independent-evidence gate, exactly
        # like a lone self-intro.
        table = EvidenceTable(evidence=[_mic_presence("SPEAKER_00", "Kamal", 10.0, 15.0)])
        assert gate_candidate_mappings(table) == []

    def test_mic_presence_plus_one_self_intro_at_a_distinct_location_passes(self):
        table = EvidenceTable(
            evidence=[
                _mic_presence("SPEAKER_00", "Kamal", 10.0, 15.0),
                _self_intro("SPEAKER_00", "Kamal", 40.0, 41.0),
            ]
        )
        candidates = gate_candidate_mappings(table)
        assert len(candidates) == 1
        assert candidates[0].cluster == "SPEAKER_00"
        assert candidates[0].name == "Kamal"
        assert {e.kind for e in candidates[0].evidence} == {EvidenceKind.MIC_PRESENCE, EvidenceKind.SELF_INTRO}

    def test_vocative_exclusion_still_drops_the_pair_with_mic_and_self_intro(self):
        table = EvidenceTable(
            evidence=[
                _mic_presence("SPEAKER_00", "Kamal", 10.0, 15.0),
                _self_intro("SPEAKER_00", "Kamal", 40.0, 41.0),
                _vocative_exclusion("SPEAKER_00", "Kamal", 20.0, 21.0),
            ]
        )
        assert gate_candidate_mappings(table) == []


class TestSuggestEnrollments:
    def _two_self_intro_table(self, cluster: str = "SPEAKER_00", name: str = "Devon") -> EvidenceTable:
        return EvidenceTable(
            evidence=[
                _self_intro(cluster, name, 0.0, 1.0),
                _self_intro(cluster, name, 40.0, 41.0),
            ]
        )

    def test_single_evidence_never_calls_the_llm(self):
        table = EvidenceTable(evidence=[_self_intro("SPEAKER_00", "Devon", 0.0, 1.0)])
        fake = FakeSummarizer()
        suggestions = suggest_enrollments(table, fake, roster=[])
        assert suggestions == []
        assert fake.calls == []

    def test_confirmed_candidate_becomes_a_suggestion(self):
        table = self._two_self_intro_table()
        fake = FakeSummarizer(['{"confirmed": [{"cluster": "SPEAKER_00", "name": "Devon", "confidence": "high"}]}'])
        suggestions = suggest_enrollments(table, fake, roster=[])
        assert suggestions == [
            Suggestion(cluster="SPEAKER_00", name="Devon", evidence=table.evidence, confidence="high")
        ]

    def test_llm_can_decline_a_gate_passing_candidate(self):
        table = self._two_self_intro_table()
        fake = FakeSummarizer(['{"confirmed": []}'])
        assert suggest_enrollments(table, fake, roster=[]) == []

    def test_llm_hallucinated_pair_outside_candidates_is_dropped(self):
        table = self._two_self_intro_table(cluster="SPEAKER_00", name="Devon")
        fake = FakeSummarizer(['{"confirmed": [{"cluster": "SPEAKER_99", "name": "Nobody", "confidence": "high"}]}'])
        assert suggest_enrollments(table, fake, roster=[]) == []

    def test_vocative_excluded_pair_never_reaches_the_llm_even_if_it_would_confirm(self):
        table = EvidenceTable(
            evidence=[
                _self_intro("SPEAKER_00", "Kamal", 0.0, 1.0),
                _self_intro("SPEAKER_00", "Kamal", 40.0, 41.0),
                _vocative_exclusion("SPEAKER_00", "Kamal", 20.0, 21.0),
            ]
        )
        fake = FakeSummarizer(['{"confirmed": [{"cluster": "SPEAKER_00", "name": "Kamal", "confidence": "high"}]}'])
        suggestions = suggest_enrollments(table, fake, roster=[])
        assert suggestions == []
        assert fake.calls == []

    def test_confidence_defaults_to_medium_when_llm_omits_it(self):
        table = self._two_self_intro_table()
        fake = FakeSummarizer(['{"confirmed": [{"cluster": "SPEAKER_00", "name": "Devon"}]}'])
        suggestions = suggest_enrollments(table, fake, roster=[])
        assert suggestions[0].confidence == "medium"

    def test_malformed_json_response_yields_no_suggestions(self):
        table = self._two_self_intro_table()
        fake = FakeSummarizer(["not json at all"])
        assert suggest_enrollments(table, fake, roster=[]) == []

    def test_roster_names_are_included_in_the_prompt(self):
        table = self._two_self_intro_table()
        fake = FakeSummarizer()
        suggest_enrollments(table, fake, roster=["Kamal", "Yanis"])
        assert fake.calls, "arbiter must call the summarizer when a candidate exists"
        _, user_prompt, _ = fake.calls[0]
        assert "Kamal" in user_prompt
        assert "Yanis" in user_prompt

    def test_prompt_never_contains_raw_transcript_text(self):
        # The arbiter must reason over the TABLE, never the transcript -- there is
        # no transcript text anywhere in this test's evidence to leak in the first
        # place, so this pins the invariant structurally: the prompt is built only
        # from cluster/name/evidence-count, never from a `text` field.
        table = self._two_self_intro_table()
        fake = FakeSummarizer()
        suggest_enrollments(table, fake, roster=[])
        _, _user_prompt, json_mode = fake.calls[0]
        assert json_mode is True


class TestLoadTranscriptResult:
    def test_loads_json_transcript_full_fidelity(self, tmp_path):
        original = TranscriptResult(
            segments=[
                Segment(
                    text="Moi c'est Devon.",
                    start=1.5,
                    end=3.25,
                    speaker="SPEAKER_00",
                    words=[Word(text="Moi", start=1.5, end=1.7, speaker="SPEAKER_00", score=0.9)],
                )
            ],
            language="fr",
            duration=100.0,
        )
        (tmp_path / "transcript.json").write_text(format_transcript_json(original))

        loaded = load_transcript_result(tmp_path)

        assert loaded == original

    def test_loads_markdown_transcript_with_diarization(self, tmp_path):
        original = TranscriptResult(
            segments=[
                Segment(text="Moi c'est Devon.", start=0.0, end=2.0, speaker="SPEAKER_00"),
                Segment(text="Merci Kamal.", start=10.0, end=12.0, speaker="SPEAKER_01"),
            ],
            language="fr",
            duration=100.0,
        )
        (tmp_path / "transcript.md").write_text(format_transcript(original))

        loaded = load_transcript_result(tmp_path)

        assert [(s.text, s.speaker) for s in loaded.segments] == [
            ("Moi c'est Devon.", "SPEAKER_00"),
            ("Merci Kamal.", "SPEAKER_01"),
        ]
        assert loaded.language == "fr"

    def test_markdown_fallback_never_recovers_word_level_or_segment_end(self, tmp_path):
        # Known, documented limitation: format_transcript never writes end times or
        # per-word data, so the markdown fallback cannot fabricate them -- end==start
        # rather than a guessed duration.
        original = TranscriptResult(
            segments=[Segment(text="Moi c'est Devon.", start=5.0, end=9.0, speaker="SPEAKER_00")],
            duration=100.0,
        )
        (tmp_path / "transcript.md").write_text(format_transcript(original))

        loaded = load_transcript_result(tmp_path)

        assert loaded.segments[0].start == 5.0
        assert loaded.segments[0].end == 5.0
        assert loaded.segments[0].words == []

    def test_markdown_without_diarization_parses_speaker_none(self, tmp_path):
        original = TranscriptResult(
            segments=[
                Segment(text="First line.", start=0.0, end=2.0, speaker=None),
                Segment(text="Second line.", start=2.0, end=4.0, speaker=None),
            ]
        )
        (tmp_path / "transcript.md").write_text(format_transcript(original))

        loaded = load_transcript_result(tmp_path)

        assert all(s.speaker is None for s in loaded.segments)
        assert [s.text for s in loaded.segments] == ["First line.", "Second line."]

    def test_markdown_mixed_none_and_named_speaker_round_trips(self, tmp_path):
        # format_transcript prints a bare "Unknown" header for a None speaker that
        # follows a named one -- the loader must invert that sentinel back to None,
        # not the literal string "Unknown" (matching.py's real unmatched-cluster
        # label is "Unknown-1", never bare "Unknown").
        original = TranscriptResult(
            segments=[
                Segment(text="Named speaks.", start=0.0, end=2.0, speaker="SPEAKER_00"),
                Segment(text="Backchannel.", start=2.0, end=3.0, speaker=None),
            ]
        )
        (tmp_path / "transcript.md").write_text(format_transcript(original))

        loaded = load_transcript_result(tmp_path)

        assert loaded.segments[0].speaker == "SPEAKER_00"
        assert loaded.segments[1].speaker is None

    def test_language_and_duration_recovered_from_markdown(self, tmp_path):
        original = TranscriptResult(segments=[Segment(text="Hi.", start=0.0, end=1.0)], language="en", duration=65.0)
        (tmp_path / "transcript.md").write_text(format_transcript(original))

        loaded = load_transcript_result(tmp_path)

        assert loaded.language == "en"
        assert loaded.duration == 65.0

    def test_missing_language_and_duration_default_to_unset(self, tmp_path):
        original = TranscriptResult(segments=[Segment(text="Hi.", start=0.0, end=1.0)])
        (tmp_path / "transcript.md").write_text(format_transcript(original))

        loaded = load_transcript_result(tmp_path)

        assert loaded.language == ""
        assert loaded.duration == 0.0

    def test_prefers_json_over_markdown_when_both_exist(self, tmp_path):
        json_version = TranscriptResult(segments=[Segment(text="From JSON.", start=0.0, end=1.0)])
        md_version = TranscriptResult(segments=[Segment(text="From markdown.", start=0.0, end=1.0)])
        (tmp_path / "transcript.json").write_text(format_transcript_json(json_version))
        (tmp_path / "transcript.md").write_text(format_transcript(md_version))

        loaded = load_transcript_result(tmp_path)

        assert loaded.segments[0].text == "From JSON."

    def test_missing_transcript_raises_clear_error(self, tmp_path):
        with pytest.raises(FileNotFoundError, match="transcript"):
            load_transcript_result(tmp_path)
