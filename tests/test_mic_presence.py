"""Tests for clew.speakers.mic_presence (BUILD NEXT #1 tranche 2, block A4)."""

from __future__ import annotations

import json
from unittest import mock

import numpy as np
import pytest
import soundfile as sf

from clew.pipeline import SPEAKER_EMBEDDINGS_FILENAME
from clew.speakers.base import VoiceprintDB
from clew.speakers.mic_presence import (
    MicPresence,
    cluster_embeddings_for,
    mic_embedding,
    resolve_mic_presence,
    voiced_spans,
)
from clew.transcription.models import Segment, TranscriptResult


def _seg(speaker, start, end=None):
    resolved_end = start if end is None else end
    return Segment(text=f"{speaker}-{start}", start=start, end=resolved_end, speaker=speaker)


def _write_constant_blocks_wav(path, sample_rate, blocks):
    chunks = [np.full(round(dur * sample_rate), value, dtype="float32") for dur, value in blocks]
    data = np.concatenate(chunks)
    sf.write(str(path), data, sample_rate, subtype="FLOAT")


class TestVoicedSpans:
    def test_returns_only_the_loud_region(self, tmp_path):
        sample_rate = 100
        path = tmp_path / "mic.wav"
        _write_constant_blocks_wav(path, sample_rate, [(2.0, 0.0), (2.0, 0.5)])

        assert voiced_spans(path) == [(2.0, 4.0)]

    def test_all_silent_yields_nothing(self, tmp_path):
        sample_rate = 100
        path = tmp_path / "mic.wav"
        _write_constant_blocks_wav(path, sample_rate, [(4.0, 0.0)])

        assert voiced_spans(path) == []

    def test_custom_threshold_rejects_moderate_loudness(self, tmp_path):
        sample_rate = 100
        path = tmp_path / "mic.wav"
        _write_constant_blocks_wav(path, sample_rate, [(2.0, 0.01)])

        assert voiced_spans(path, rms_threshold=0.5) == []
        assert voiced_spans(path, rms_threshold=0.001) == [(0.0, 2.0)]

    def test_longest_first_selection_truncates_to_the_cap(self, tmp_path):
        sample_rate = 100
        # 3s loud, 2s silent, 5s loud -- two separated voiced regions. A 6s cap
        # can only be filled by taking the LONGER (5s) region fully and
        # truncating the shorter one -- taking the shorter one first instead
        # would produce a DIFFERENT exact pair of spans with the same total,
        # so the total alone can't tell the two policies apart.
        path = tmp_path / "mic.wav"
        _write_constant_blocks_wav(path, sample_rate, [(3.0, 0.5), (2.0, 0.0), (5.0, 0.5)])

        spans = voiced_spans(path, max_total_seconds=6.0)

        assert spans == [(0.0, 1.0), (5.0, 10.0)]


class TestMicEmbedding:
    def test_returns_none_when_voiced_total_below_minimum(self, tmp_path):
        sample_rate = 100
        path = tmp_path / "mic.wav"
        _write_constant_blocks_wav(path, sample_rate, [(0.5, 0.5)])  # only 0.5s loud

        fake_embedder = mock.MagicMock()
        result = mic_embedding(path, fake_embedder, min_voiced_seconds=2.0)

        assert result is None
        fake_embedder.embed_file.assert_not_called()

    def test_embeds_a_clip_whose_duration_equals_the_voiced_total(self, tmp_path):
        sample_rate = 100
        path = tmp_path / "mic.wav"
        _write_constant_blocks_wav(path, sample_rate, [(1.0, 0.0), (3.0, 0.5)])

        captured = {}

        def fake_embed_file(clip_path):
            info = sf.info(str(clip_path))
            captured["duration"] = info.frames / info.samplerate
            return [0.9, 0.1]

        fake_embedder = mock.MagicMock()
        fake_embedder.embed_file.side_effect = fake_embed_file

        result = mic_embedding(path, fake_embedder, min_voiced_seconds=2.0)

        assert result == [0.9, 0.1]
        expected_total = sum(end - start for start, end in voiced_spans(path))
        assert captured["duration"] == pytest.approx(expected_total, abs=0.05)


class TestResolveMicPresence:
    def test_both_hops_pass_resolves_name(self):
        db = VoiceprintDB()
        db.upsert("Kamal", [1.0, 0.0, 0.0])
        cluster_embeddings = {"SPEAKER_00": [1.0, 0.0, 0.0], "SPEAKER_01": [0.0, 1.0, 0.0]}

        presence = resolve_mic_presence([1.0, 0.0, 0.0], cluster_embeddings, db, start=1.0, end=2.0)

        assert presence == MicPresence(
            cluster="SPEAKER_00", name="Kamal", score=pytest.approx(1.0), status="matched", start=1.0, end=2.0
        )

    def test_empty_store_never_resolves_a_name_even_with_a_strong_cluster_match(self):
        db = VoiceprintDB()
        cluster_embeddings = {"SPEAKER_00": [1.0, 0.0, 0.0]}

        presence = resolve_mic_presence([1.0, 0.0, 0.0], cluster_embeddings, db, start=0.0, end=1.0)

        assert presence.cluster == "SPEAKER_00"
        assert presence.name is None

    def test_cluster_score_below_threshold_never_resolves_a_name_even_with_a_store_match(self):
        db = VoiceprintDB()
        db.upsert("Kamal", [0.0, 0.0, 1.0])
        cluster_embeddings = {"SPEAKER_00": [0.0, 0.0, 1.0]}
        mic_emb = [0.7, 0.7, 0.14]  # weak cosine vs the cluster

        presence = resolve_mic_presence(mic_emb, cluster_embeddings, db, threshold=0.9, start=0.0, end=1.0)

        assert presence.cluster is None
        assert presence.name is None

    def test_score_is_reported_even_below_threshold(self):
        db = VoiceprintDB()
        cluster_embeddings = {"SPEAKER_00": [0.0, 0.0, 1.0]}
        mic_emb = [0.7, 0.7, 0.14]

        presence = resolve_mic_presence(mic_emb, cluster_embeddings, db, threshold=0.99, start=0.0, end=1.0)

        assert presence.cluster is None
        assert presence.score is not None
        assert presence.score > 0.0

    def test_empty_cluster_embeddings_yields_none_cluster_and_none_score(self):
        db = VoiceprintDB()
        presence = resolve_mic_presence([1.0, 0.0], {}, db, start=0.0, end=1.0)
        assert presence.cluster is None
        assert presence.score is None
        assert presence.name is None
        assert presence.status == "below"

    def test_hop_two_never_runs_when_hop_one_fails_even_if_the_store_would_match(self):
        # The store match would succeed if checked directly against mic_emb --
        # proves hop 2 is gated on hop 1 passing, not merely that this
        # particular store happens to also reject it.
        db = VoiceprintDB()
        db.upsert("Kamal", [1.0, 0.0, 0.0])
        cluster_embeddings = {"SPEAKER_00": [0.0, 1.0, 0.0]}
        mic_emb = [1.0, 0.0, 0.0]

        presence = resolve_mic_presence(mic_emb, cluster_embeddings, db, threshold=0.65, start=0.0, end=1.0)

        assert presence.cluster is None
        assert presence.name is None

    def test_argmax_picks_the_best_matching_cluster(self):
        db = VoiceprintDB()
        cluster_embeddings = {"SPEAKER_00": [0.0, 1.0, 0.0], "SPEAKER_01": [1.0, 0.0, 0.0]}

        presence = resolve_mic_presence([0.9, 0.1, 0.0], cluster_embeddings, db, threshold=0.5, start=0.0, end=1.0)

        assert presence.cluster == "SPEAKER_01"


class TestResolveMicPresenceBorderlineStatus:
    """Schema amendment (2026-09-10, plan-build-next-1-t2.md "Amendement du
    schema", after the A4/A5 review): a margin band around threshold that
    never resolves a name, so a real-data score of 0.666 against a 0.65
    threshold (0.016 of headroom) reports honestly instead of silently
    passing or failing a coin-flip-close match. Each boundary test patches
    cosine_similarity directly (not derived from vector geometry) so the
    exact >= / < comparisons at the band edges are never blurred by
    floating-point noise from the vectors themselves."""

    def test_exactly_threshold_plus_margin_is_matched(self):
        # The mocked score is the SAME expression (0.65 + 0.05) production
        # computes internally -- a separately-typed 0.70 literal is NOT
        # bit-identical to 0.65 + 0.05 (0.7000000000000001), which would
        # blur exactly the boundary this test exists to pin.
        db = VoiceprintDB()
        with mock.patch("clew.speakers.mic_presence.cosine_similarity", return_value=0.65 + 0.05):
            presence = resolve_mic_presence(
                [1.0], {"SPEAKER_00": [1.0]}, db, threshold=0.65, margin=0.05, start=0.0, end=1.0
            )

        assert presence.status == "matched"
        assert presence.cluster == "SPEAKER_00"

    def test_exactly_threshold_minus_margin_is_borderline(self):
        db = VoiceprintDB()
        with mock.patch("clew.speakers.mic_presence.cosine_similarity", return_value=0.60):
            presence = resolve_mic_presence(
                [1.0], {"SPEAKER_00": [1.0]}, db, threshold=0.65, margin=0.05, start=0.0, end=1.0
            )

        assert presence.status == "borderline"
        assert presence.cluster == "SPEAKER_00"
        assert presence.name is None

    def test_just_below_threshold_minus_margin_is_below(self):
        db = VoiceprintDB()
        with mock.patch("clew.speakers.mic_presence.cosine_similarity", return_value=0.599999):
            presence = resolve_mic_presence(
                [1.0], {"SPEAKER_00": [1.0]}, db, threshold=0.65, margin=0.05, start=0.0, end=1.0
            )

        assert presence.status == "below"
        assert presence.cluster is None
        assert presence.name is None

    def test_borderline_never_resolves_a_name_even_with_a_store_match(self):
        # cosine_similarity is patched only for hop 1 (mic_presence's own
        # reference); match_speaker (hop 2) uses matching.py's own real
        # cosine_similarity, so this proves the status gate itself blocks
        # hop 2 from ever running, not a coincidentally-mocked hop 2 too.
        db = VoiceprintDB()
        db.upsert("Kamal", [1.0])
        with mock.patch("clew.speakers.mic_presence.cosine_similarity", return_value=0.63):
            presence = resolve_mic_presence(
                [1.0], {"SPEAKER_00": [1.0]}, db, threshold=0.65, margin=0.05, start=0.0, end=1.0
            )

        assert presence.status == "borderline"
        assert presence.name is None

    def test_matched_still_resolves_a_name_via_hop_two(self):
        db = VoiceprintDB()
        db.upsert("Kamal", [1.0, 0.0])
        presence = resolve_mic_presence(
            [1.0, 0.0], {"SPEAKER_00": [1.0, 0.0]}, db, threshold=0.65, margin=0.05, start=0.0, end=1.0
        )

        assert presence.status == "matched"
        assert presence.name == "Kamal"


class TestResolveMicPresenceDefaultMargin:
    """Pins _DEFAULT_BORDERLINE_MARGIN (0.05) through the production default.
    Every TestResolveMicPresenceBorderlineStatus test above passes margin=0.05
    explicitly, so none of them would notice the constant itself drifting --
    measured (review finding N1): 0.0, 0.049 and 0.20 all leave the whole
    suite green. Neither edge alone pins 0.05: the lower edge alone can't
    distinguish 0.05 from a wider margin (0.20 also reports "borderline"
    there), and the upper edge alone can't distinguish it from a narrower one
    (0.0 or 0.049 also report "matched" there) -- both together do."""

    def test_default_margin_lower_edge_is_borderline_not_below(self):
        # threshold - _DEFAULT_BORDERLINE_MARGIN == 0.65 - 0.05 == 0.6 exactly
        # (bit-identical, verified). A margin of 0.0 or 0.049 narrows the band
        # past this score, reporting "below" instead.
        db = VoiceprintDB()
        with mock.patch("clew.speakers.mic_presence.cosine_similarity", return_value=0.60):
            presence = resolve_mic_presence([1.0], {"SPEAKER_00": [1.0]}, db, threshold=0.65, start=0.0, end=1.0)

        assert presence.status == "borderline"

    def test_default_margin_upper_edge_is_matched_not_borderline(self):
        # threshold + _DEFAULT_BORDERLINE_MARGIN, computed the same way
        # production computes it internally (a separately-typed 0.70 literal
        # is not bit-identical to 0.65 + 0.05). A margin of 0.20 widens the
        # band past this score, reporting "borderline" instead.
        db = VoiceprintDB()
        with mock.patch("clew.speakers.mic_presence.cosine_similarity", return_value=0.65 + 0.05):
            presence = resolve_mic_presence([1.0], {"SPEAKER_00": [1.0]}, db, threshold=0.65, start=0.0, end=1.0)

        assert presence.status == "matched"


class TestClusterEmbeddingsFor:
    def test_prefers_persisted_embeddings_and_never_calls_the_factory(self, tmp_path):
        (tmp_path / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2]}, "assignments": {}})
        )
        transcript = TranscriptResult(segments=[_seg("SPEAKER_00", 0.0)], duration=10.0)

        def exploding_factory():
            raise AssertionError("embedder factory must never be called on the persisted path")

        result = cluster_embeddings_for(tmp_path, transcript, exploding_factory)

        assert result == {"SPEAKER_00": [0.1, 0.2]}

    def test_falls_back_to_embedding_each_speaker_cluster(self, tmp_path):
        sample_rate = 50
        system_path = tmp_path / "system.wav"
        _write_constant_blocks_wav(system_path, sample_rate, [(100.0, 0.0)])

        transcript = TranscriptResult(
            segments=[_seg("SPEAKER_00", 0.0), _seg("OTHER", 30.0), _seg("SPEAKER_01", 40.0), _seg("OTHER", 90.0)],
            duration=100.0,
        )

        fake_embedder = mock.MagicMock()
        fake_embedder.embed_file.side_effect = [[0.1, 0.1], [0.2, 0.2]]
        factory = mock.MagicMock(return_value=fake_embedder)

        result = cluster_embeddings_for(tmp_path, transcript, factory)

        assert result == {"SPEAKER_00": [0.1, 0.1], "SPEAKER_01": [0.2, 0.2]}
        assert factory.call_count == 1
        assert fake_embedder.embed_file.call_count == 2

    def test_skips_a_cluster_with_no_qualifying_turn_without_raising(self, tmp_path):
        sample_rate = 50
        system_path = tmp_path / "system.wav"
        _write_constant_blocks_wav(system_path, sample_rate, [(100.0, 0.0)])

        transcript = TranscriptResult(
            segments=[_seg("SPEAKER_00", 40.0), _seg("OTHER", 41.5), _seg("SPEAKER_01", 50.0), _seg("OTHER", 90.0)],
            duration=100.0,
        )

        fake_embedder = mock.MagicMock()
        fake_embedder.embed_file.return_value = [0.3, 0.3]
        factory = mock.MagicMock(return_value=fake_embedder)

        result = cluster_embeddings_for(tmp_path, transcript, factory)

        assert result == {"SPEAKER_01": [0.3, 0.3]}

    def test_no_speaker_labels_returns_empty_without_calling_factory(self, tmp_path):
        transcript = TranscriptResult(segments=[_seg("Owner", 0.0)], duration=10.0)

        def exploding_factory():
            raise AssertionError("must never be called when there are no SPEAKER_NN labels")

        assert cluster_embeddings_for(tmp_path, transcript, exploding_factory) == {}

    def test_missing_audio_skips_clusters_without_raising(self, tmp_path):
        transcript = TranscriptResult(
            segments=[_seg("SPEAKER_00", 0.0), _seg("OTHER", 30.0)],
            duration=100.0,
        )
        fake_embedder = mock.MagicMock()
        factory = mock.MagicMock(return_value=fake_embedder)

        result = cluster_embeddings_for(tmp_path, transcript, factory)

        assert result == {}
        fake_embedder.embed_file.assert_not_called()
